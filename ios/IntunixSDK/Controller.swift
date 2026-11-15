import Foundation

package struct ConversationTiming {
    package var turnTimeoutMs: UInt64 = 10_000
    package var busyRetryMs: UInt64 = 700
    package var probeTimeoutMs: UInt64 = 10_000
    package init(turnTimeoutMs: UInt64 = 10_000, busyRetryMs: UInt64 = 700, probeTimeoutMs: UInt64 = 10_000) {
        self.turnTimeoutMs = turnTimeoutMs; self.busyRetryMs = busyRetryMs; self.probeTimeoutMs = probeTimeoutMs
    }
}

let maxBusyRetries = 2

/// A one-shot flag that callbacks and awaiters can wait on.
@MainActor final class Signal {
    private(set) var fired = false
    private var subs: [() -> Void] = []
    func fire() { guard !fired else { return }; fired = true; let s = subs; subs = []; s.forEach { $0() } }
    func on(_ f: @escaping () -> Void) { if fired { f() } else { subs.append(f) } }
    func wait() async { await withCheckedContinuation { c in on { c.resume() } } }
}

@MainActor private final class Once<T> {
    var cont: CheckedContinuation<Result<T, Error>?, Never>?
    var tasks: [Task<Void, Never>] = []
    func finish(_ r: Result<T, Error>?) { guard let c = cont else { return }; cont = nil; tasks.forEach { $0.cancel() }; c.resume(returning: r) }
}

/// Runs `op` as its own task and resumes with its outcome, or nil when `ms` passes or `stop` fires first.
/// Unlike a task group this does not wait for `op` to return, so an HTTP call that ignores cancellation
/// cannot hold the caller back; its late result is dropped.
@MainActor func bounded<T>(ms: UInt64, stop: Signal? = nil, _ op: @escaping @MainActor () async throws -> T) async -> Result<T, Error>? {
    let once = Once<T>()
    let r: Result<T, Error>? = await withCheckedContinuation { c in
        once.cont = c
        once.tasks.append(Task { @MainActor in
            do { once.finish(.success(try await op())) } catch { once.finish(.failure(error)) }
        })
        once.tasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            once.finish(nil)
        })
        stop?.on { once.finish(nil) }
    }
    return r
}

package struct ConversationState {
    package var messages: [ChatMessage]
    package var input: Step?
    package var inputJson: JSONObject?
    package var answered: Int, total: Int
    package var pending: Bool, done: Bool, endedByRespondent: Bool, local: Bool
    /// The current input may be skipped right now.
    package var canSkip: Bool
}

private func isProbe(_ id: String) -> Bool { id.hasPrefix("probe:") }
private func probeStep(_ id: String) -> Step { Step(id: id, kind: "followup", title: "", required: false, input: FollowUpInput(type: "free")) }

/// Renderer-agnostic chat controller. Public async methods never throw.
/// Call `dispose()` when the view is torn down without a result and `end()` only when the
/// respondent ends or closes the conversation.
@MainActor package final class ConversationController {
    package private(set) var state = ConversationState(messages: [], input: nil, inputJson: nil, answered: 0, total: 0, pending: false,
                                                       done: false, endedByRespondent: false, local: false, canSkip: false)
    private var content: FeedbackContent
    private var handle: ConversationHandle
    private var locale: String?
    private let timing: ConversationTiming
    private var listeners: [(id: Int, fn: () -> Void)] = []
    private var nextListener = 0
    private var answers: [Answer] = []
    private var skipped = Set<String>()
    private var seen: [String: Step] = [:] // steps the server sent as input
    private var nextTurn = 0
    private var started = false
    private var disposed = false
    private var waits: [Signal] = [] // busy-retry waits: fired by dispose()
    private var calls: [Signal] = [] // in-flight calls: fired by dispose() unless end() was called
    private var broken = false // a request failed: never contact the transport again
    private var inflight: Signal?
    private let startedAt = nowMs()

    package init(content: FeedbackContent, handle: ConversationHandle, locale: String?, timing: ConversationTiming = .init()) {
        self.content = content; self.handle = handle; self.locale = locale; self.timing = timing
    }

    /// Later requests carry `lang`. Bubbles that came from the form (welcome, predefined questions, completion,
    /// answers to predefined steps) are re-rendered; AI follow-ups and other server text stay as asked.
    package func setLanguage(_ lang: String, content: FeedbackContent, config: ConversationConfig? = nil) {
        locale = lang
        self.content = content
        if let config { handle.config = config }
        var messages = state.messages
        for i in messages.indices {
            if let t = sourceText(messages[i].source), t != messages[i].text { messages[i].text = t }
        }
        let same = state.input.flatMap { i in content.steps.first { $0.id == i.id } }
        if messages != state.messages || same != nil {
            set { $0.messages = messages; if let same { $0.input = same; $0.inputJson = nil } }
        }
    }

    private func completionText() -> String { handle.config.completionMessage ?? content.thanks?.title ?? Defaults.thanksTitle }

    private func sourceText(_ src: MessageSource?) -> String? {
        switch src {
        case nil: return nil
        case .welcome?: return handle.config.welcomeMessage
        case .completion?: return completionText()
        case .step(let id)?: return content.steps.first { $0.id == id }?.title
        case .answer(let id)?:
            guard let step = content.steps.first(where: { $0.id == id }), let a = answers.first(where: { $0.stepId == id }) else { return nil }
            return answerLabel(step, a)
        }
    }

    /// Server text carries no origin: match it against the form's own texts as they were when it arrived.
    private func tagServer(_ text: String, done: Bool) -> MessageSource? {
        if text == handle.config.welcomeMessage { return .welcome }
        if let s = content.steps.first(where: { $0.title == text }) { return .step(s.id) }
        return done && text == completionText() ? .completion : nil
    }

    /// A restored respondent bubble right after a predefined question is that question's answer.
    private func tagTranscript(_ list: [ChatMessage], done: Bool) -> [ChatMessage] {
        list.enumerated().map { i, m in
            var m = m
            if m.source != nil { return m }
            if m.role == "nia" { m.source = tagServer(m.text, done: done && i == list.count - 1); return m }
            if i > 0, list[i - 1].role == "nia", let id = content.steps.first(where: { $0.title == list[i - 1].text })?.id, answered(id) { m.source = .answer(id) }
            return m
        }
    }

    package func subscribe(_ cb: @escaping () -> Void) -> () -> Void {
        let id = nextListener; nextListener += 1
        listeners.append((id, cb))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    /// Stop locally and tell the server nothing. Later calls are no-ops; `result()` still works.
    package func dispose() {
        disposed = true
        listeners.removeAll()
        waits.forEach { $0.fire() }
        // After end(), the in-flight call stays bounded by its timeout so the deferred `end` still follows it.
        if !state.endedByRespondent { calls.forEach { $0.fire() } }
    }

    package func start() async {
        if started || disposed { return }
        started = true
        await send("resume", nil)
    }

    /// True when the answer was accepted, false when ignored (a blank answer becomes a skip).
    package func answer(_ a: Answer) async -> Bool {
        guard !disposed, !state.pending, !state.done, let input = state.input, a.stepId == input.id, isAnswerValid(input, a) else { return false }
        if isEmptyAnswer(a) { await skip(); return false }
        answers = answers.filter { $0.stepId != a.stepId } + [a]
        let source: MessageSource? = content.steps.contains { $0.id == a.stepId } ? .answer(a.stepId) : nil
        set { $0.messages.append(ChatMessage("respondent", answerLabel(input, a), source: source)) }
        if state.local { advanceLocal() } else { await send("answer", a) }
        return true
    }

    package func skip() async {
        guard !disposed, state.canSkip, let input = state.input else { return }
        skipped.insert(input.id)
        if state.local { advanceLocal() } else { await send("skip", nil) }
    }

    /// Detached so a hung request cannot block teardown; the server records `end` only after the request in flight.
    package func end() {
        if disposed || state.done { return }
        set { $0.endedByRespondent = true; $0.done = true; $0.pending = false; $0.input = nil; $0.inputJson = nil }
        if state.local { return }
        let before = inflight
        Task { @MainActor [self] in
            await before?.wait()
            if !state.local && !broken { _ = await call(request("end", nextTurn, nil)) }
        }
    }

    package func result() -> FeedbackResponse {
        let valid = answers.filter { a in stepFor(a.stepId).map { isAnswerValid($0, a) } == true }
        return FeedbackResponse(answers: valid, completed: state.done && !state.endedByRespondent, durationMs: nowMs() - startedAt, conversationId: handle.conversationId)
    }

    private func stepFor(_ id: String) -> Step? {
        content.steps.first { $0.id == id } ?? seen[id] ?? (isProbe(id) ? probeStep(id) : nil)
    }

    private func request(_ action: String, _ turn: Int, _ answer: Answer?) -> TurnRequest {
        TurnRequest(handle.conversationId, turn, action, answer, locale.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Bounded transport call; nil on failure, timeout or dispose.
    private func call(_ req: TurnRequest) async -> JSONObject? {
        let stop = Signal()
        calls.append(stop)
        defer { calls.removeAll { $0 === stop } }
        let transport = handle.transport
        if case .success(let o)? = await bounded(ms: timing.turnTimeoutMs, stop: stop, { try await transport(req) }) { return o }
        return nil
    }

    private func callReply(_ req: TurnRequest) async -> TurnReply? {
        guard let o = await call(req), isValidTurnReply(o) else { return nil }
        return parseTurnReply(o)
    }

    private func send(_ action: String, _ answer: Answer?) async {
        set { $0.pending = true }
        let mine = Signal()
        inflight = mine
        await run(action, answer)
        mine.fire()
    }

    private func run(_ action: String, _ answer: Answer?) async {
        var turn = nextTurn
        var retries = 0
        while true {
            guard let reply = await callReply(request(action, turn, answer)) else { return fail(action) }
            if !reply.busy { nextTurn = reply.nextTurn }
            if disposed || state.endedByRespondent { return }
            if !reply.busy { return applyReply(reply, isStart: action == "resume") }
            if retries >= maxBusyRetries { return fail(action) }
            turn = reply.nextTurn
            await pause(timing.busyRetryMs)
            if disposed || state.endedByRespondent { return }
            retries += 1
        }
    }

    private func fail(_ action: String) {
        broken = true
        if disposed { return }
        if !state.endedByRespondent { goLocal(action) }
    }

    private func pause(_ ms: UInt64) async {
        let w = Signal()
        waits.append(w)
        _ = await bounded(ms: ms, stop: w, { try await Task.sleep(nanoseconds: ms * 1_000_000) })
        waits.removeAll { $0 === w }
    }

    private func applyReply(_ reply: TurnReply, isStart: Bool) {
        let added = reply.messages.map { ChatMessage("nia", $0, source: tagServer($0, done: reply.done)) }
        if let i = reply.input { seen[i.id] = i }
        if isStart { seed(reply) }
        let restored = isStart ? reply.transcript.flatMap { $0.isEmpty ? nil : tagTranscript($0, done: reply.done) } : nil
        set {
            $0.messages = restored ?? (isStart ? added : $0.messages + added)
            $0.input = reply.input; $0.inputJson = reply.inputJson; $0.answered = reply.answered; $0.total = reply.total
            $0.done = reply.done; $0.pending = false
        }
    }

    /// Answers and skips given before a reload, when the server sends them.
    private func seed(_ reply: TurnReply) {
        guard let list = reply.answers else { return }
        var byStep: [Answer] = [] // last entry per step wins
        for o in list {
            guard let id = o.str("stepId") else { continue }
            let step = content.steps.first { $0.id == id } ?? (isProbe(id) ? probeStep(id) : nil)
            byStep.removeAll { $0.stepId == id }
            if let step, let a = parseAnswer(o), isAnswerValid(step, a) { byStep.append(a) }
        }
        answers = byStep
        reply.skipped.map { skipped.formUnion($0) }
    }

    private func goLocal(_ action: String) {
        set { $0.local = true; $0.pending = false }
        if action == "resume", state.messages.isEmpty, let w = handle.config.welcomeMessage, !w.isEmpty { pushNia(w, source: .welcome) }
        // The failed action consumed the current input, so move to the next predefined step.
        advanceLocal(dedupe: true)
    }

    private func advanceLocal(dedupe: Bool = false) {
        let next = visibleSteps().first { !answered($0.id) && !skipped.contains($0.id) }
        pushNia(next?.title ?? completionText(), dedupe: dedupe, source: next.map { .step($0.id) } ?? .completion)
        let steps = visibleSteps()
        let n = steps.filter { answered($0.id) || skipped.contains($0.id) }.count
        set {
            $0.input = next; $0.inputJson = nil; $0.answered = n; $0.total = steps.count
            if next == nil { $0.done = true }
        }
    }

    /// Hiding a step can hide its dependants, so filter until stable.
    private func visibleSteps() -> [Step] {
        var visible = content.steps
        while true {
            let ids = Set(visible.map(\.id))
            let current = answers.filter { ids.contains($0.stepId) }
            let next = content.steps.filter { evaluateShowIf($0.showIf, current) }
            if next.count == visible.count { return next }
            visible = next
        }
    }

    private func answered(_ id: String) -> Bool { answers.contains { $0.stepId == id } }

    /// `dedupe`: skip a message the server already showed as the last one.
    private func pushNia(_ text: String, dedupe: Bool = false, source: MessageSource? = nil) {
        if dedupe, let last = state.messages.last, last.role == "nia", last.text == text { return }
        set { $0.messages.append(ChatMessage("nia", text, source: source)) }
    }

    private func set(_ patch: (inout ConversationState) -> Void) {
        if disposed { return }
        var s = state
        patch(&s)
        s.canSkip = !s.pending && !s.done && s.input.map { isAnswerValid($0, nil) } == true
        state = s
        listeners.map(\.fn).forEach { $0() }
    }
}
