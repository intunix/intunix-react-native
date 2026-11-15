import Foundation

private let autoSubmitKinds: Set<String> = ["thumbs", "pmf", "smileys"]

/// Form and chat rules of FeedbackExperience (React), independent of how they are drawn: languages,
/// enhanced probes, the chat controller, finishing and closing. The SwiftUI `FormHost` only forwards.
@MainActor
package final class FormController {
    package let exp: Experience
    package let language: FormLanguage
    package private(set) var content: FeedbackContent
    package private(set) var review: ReviewPresenter?
    package let chat: ConversationController?
    /// True while an enhanced probe is being asked (the form waits).
    package private(set) var probing = false
    /// The chat ended and the review card replaces its action row.
    package private(set) var chatReview = false
    /// Called after every state change.
    package var onChange: () -> Void = {}

    private let cb: RenderCallbacks
    private let runner: FeedbackRunner
    private let onResult: (ExperienceResult) -> Void
    private let handle: ConversationHandle?
    private let probes: EnhancedProbes?
    private var settled = false
    private var impressed = false
    private var doneHandled = false
    private var unsubscribe: (() -> Void)?
    private var tasks: [Task<Void, Never>] = []

    package init(exp: Experience, callbacks: RenderCallbacks, openUrl: @escaping (String) -> Bool,
                 device: [String] = deviceLanguages(), onResult: @escaping (ExperienceResult) -> Void) {
        self.exp = exp; cb = callbacks; self.onResult = onResult
        language = FormLanguage(raw: exp.content, source: callbacks.locale, device: device)
        content = language.content
        runner = FeedbackRunner(language.content, review: exp.reviewRequest)
        handle = callbacks.conversation
        probes = handle?.config.mode == "enhanced" ? EnhancedProbes(handle: handle!, locale: language.multi ? language.lang : nil) : nil
        if let h = handle, h.config.mode == "conversational" {
            var local = h
            if language.multi { local.config = localizeConversation(h.config, language.lang) }
            chat = ConversationController(content: language.content, handle: local, locale: language.multi ? language.lang : nil)
        } else { chat = nil }
        review = ReviewPresenter.create(exp.reviewRequest, formId: exp.id, clientResponseId: callbacks.clientResponseId,
                                        brandColor: language.content.brand.color, emit: callbacks.onReviewEvent, openUrl: openUrl) { [weak self] in self?.finish() }
        unsubscribe = chat?.subscribe { [weak self] in self?.onChatState(); self?.onChange() }
    }

    package var closable: Bool { language.content.closable }
    package func state() -> RunnerState { runner.state() }
    package func isLastPage() -> Bool { runner.isLastPage() }
    package func chatState() -> ConversationState { chat!.state }
    package func labels() -> ChatLabels { chatLabels(content, handle!.config) }

    /// The input the chat asks for: the server's raw step gets built-in texts for the current language.
    package func chatInput() -> Step? {
        let s = chatState()
        return s.inputJson.flatMap { parseStep(fillStep($0, language.lang)) } ?? s.input
    }

    /// Once per form instance, however often the view appears.
    package func impression() {
        guard !impressed else { return }
        impressed = true
        if let c = chat { launch { await c.start() } }
        cb.onImpression()
    }

    private func launch(_ op: @escaping @MainActor () async -> Void) { tasks.append(Task { @MainActor in await op() }) }

    private func finalize(_ outcome: String, _ r: FeedbackResponse) {
        guard !settled else { return }
        settled = true
        unsubscribe?()
        if chat?.state.endedByRespondent != true { chat?.dispose() }
        var full = r
        if chat == nil, let handle { full.conversationId = handle.conversationId }
        tasks.forEach { $0.cancel() }
        onResult(ExperienceResult(outcome: outcome, response: language.decorate(full)))
    }

    package func finish() {
        finalize("responded", chat?.result() ?? runner.finish())
        onChange()
    }

    package func close() {
        guard !settled else { return }
        if let chat { return closeChat(chat) }
        switch runner.state().phase {
        case .review: if let review { review.onSkip() } else { finish() }
        case .thanks, .done: finish()
        case .running:
            let r = runner.dismiss()
            cb.onDismiss()
            finalize(r.answers.isEmpty ? "dismissed" : "responded", r)
            onChange()
        }
    }

    private func closeChat(_ c: ConversationController) {
        if chatReview { if let review { review.onSkip() } else { finish() }; return }
        if c.state.done { return finish() }
        unsubscribe?() // ending must not start the thanks timer
        c.end()
        cb.onDismiss()
        let r = c.result()
        finalize(r.answers.isEmpty ? "dismissed" : "responded", r)
        onChange()
    }

    private func onChatState() {
        guard let c = chat, c.state.done, !doneHandled else { return }
        doneHandled = true
        if let review, reviewQualifies(exp.reviewRequest, c.result().answers) {
            chatReview = true
            review.onShown()
        } else {
            let ms = content.thanks?.autoCloseMs ?? Defaults.thanksAutoCloseMs
            if ms > 0 {
                launch { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                    if !Task.isCancelled { self?.finish() }
                }
            }
        }
    }

    package func sendChat(_ a: Answer) {
        guard let c = chat else { return }
        launch { [weak self] in
            if await c.answer(a), self?.settled == false { self?.cb.onResponse(a) }
        }
    }

    package func skipChat() { if let c = chat { launch { await c.skip() } } }

    /// Thumbs / PMF / smileys submit on tap only when the whole form is that one question.
    package func autoSubmit() -> Bool {
        let s = runner.state()
        guard s.visibleSteps.count == 1, s.pageSteps.count == 1, let only = s.pageSteps.first else { return false }
        return autoSubmitKinds.contains(only.kind) && (only.page == nil || content.steps.filter { $0.page == only.page }.count == 1)
    }

    package func onAnswer(_ stepId: String, _ answer: Answer?) {
        let auto = autoSubmit()
        if let answer { runner.record(answer) } else { runner.clear(stepId) }
        if auto && answer != nil { submitPage() } else { onChange() }
    }

    package func submitPage() {
        if probing { return }
        let s = runner.state()
        guard isPageValid(s.pageSteps, s.answers) else { return }
        for step in s.pageSteps { if let a = s.answers.first(where: { $0.stepId == step.id }) { cb.onResponse(a) } }
        guard let p = probes else { runner.submitPage(); onChange(); return }
        probing = true
        onChange()
        launch { [weak self] in
            let u = await p.afterPage(s.pageSteps, s.answers)
            guard let self, !self.settled else { return }
            self.probing = false
            u.drop.forEach { self.runner.removeInsertedAfter($0) }
            u.insert.forEach { self.runner.insertAfter($0.anchor, $0.step) }
            self.runner.submitPage()
            self.onChange()
        }
    }

    package func back() { if probing { return }; runner.back(); onChange() }

    package func switchLanguage(_ code: String) {
        guard language.switchTo(code) else { return }
        content = language.content
        runner.setContent(content)
        probes?.setLocale(code)
        if let handle { chat?.setLanguage(code, content: content, config: localizeConversation(handle.config, code)) }
        onChange()
    }
}

/// "Page 2 of 3" / "Done" in the form's language (built-in texts), English when there are none.
package func pageLabel(_ texts: BuiltinTexts?, ending: Bool, paged: Bool, index: Int, count: Int) -> String {
    guard let texts else { return ending ? "Done" : "\(paged ? "Page" : "Question") \(index + 1) of \(count)" }
    if ending { return texts.done }
    return (paged ? texts.pageOf : texts.questionOf).replacingOccurrences(of: "{n}", with: "\(index + 1)").replacingOccurrences(of: "{total}", with: "\(count)")
}
