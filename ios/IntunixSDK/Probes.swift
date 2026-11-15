import Foundation

private let inputTypes: Set<String> = ["free", "email", "name", "selectOne", "selectMultiple"]

package struct ProbeUpdate {
    package var drop: [String]
    package var insert: [(anchor: String, step: Step)]
}

private struct InvalidReply: Error {}

/// Asks the server, after answers to `aiFollowUp` steps, for one follow-up question (a probe).
@MainActor package final class EnhancedProbes {
    private let handle: ConversationHandle
    private var locale: String?
    private let timing: ConversationTiming
    private var turn = 0
    private var disabled = false
    private var finished = false // server said done: ask no more
    private var sent: [String: AnswerValue] = [:]
    private var seen = Set<String>()
    /// Probe ids returned per asked step id.
    private var origin: [String: [String]] = [:]

    package init(handle: ConversationHandle, locale: String?, timing: ConversationTiming = .init()) {
        self.handle = handle; self.locale = locale; self.timing = timing
    }

    package func setLocale(_ lang: String) { locale = lang }

    package func afterPage(_ steps: [Step], _ answers: [Answer]) async -> ProbeUpdate {
        var drop: [String] = []
        var insert: [(anchor: String, step: Step)] = []
        for step in steps where step.aiFollowUp || step.id.hasPrefix("probe:") {
            let ans = answers.first { $0.stepId == step.id }
            let key = ans?.value
            if let prev = sent[step.id], prev != key {
                drop.append(step.id)
                forget(step.id)
                sent[step.id] = nil
            }
            guard let ans, sent[step.id] != key else { continue }
            sent[step.id] = ans.value
            if disabled || finished { continue }
            let reply = await ask(ans)
            if reply?.done == true { finished = true }
            if let input = reply?.input, input.id.hasPrefix("probe:"), input.kind == "followup", inputTypes.contains(input.input?.type ?? ""),
               !input.title.isEmpty, seen.insert(input.id).inserted {
                origin[step.id, default: []].append(input.id)
                insert.append((step.id, input))
            }
        }
        return ProbeUpdate(drop: drop, insert: insert)
    }

    /// Forget probes issued for a step and, through them, their own chain.
    private func forget(_ stepId: String) {
        for id in origin[stepId] ?? [] {
            seen.remove(id)
            sent[id] = nil
            forget(id)
        }
        origin[stepId] = nil
    }

    /// Invalid shape is a failure; a valid reply whose input step we cannot build just carries no question.
    private func parse(_ o: JSONObject) throws -> TurnReply {
        guard isValidTurnReply(o) else { throw InvalidReply() }
        if let r = parseTurnReply(o) { return r }
        var c = o
        c["input"] = NSNull()
        return parseTurnReply(c)!
    }

    /// One request (plus one busy retry) inside a single probe budget. Nil on failure.
    private func ask(_ ans: Answer) async -> TurnReply? {
        let locale = self.locale.flatMap { $0.isEmpty ? nil : $0 } // one locale per request, busy retry included
        let transport = handle.transport
        let busyMs = timing.busyRetryMs
        var busyTwice = false
        let outcome = await bounded(ms: timing.probeTimeoutMs, { [self] () -> TurnReply? in
            let req = { TurnRequest(self.handle.conversationId, self.turn, "answer", ans, locale) }
            var r = try parse(try await transport(req()))
            try Task.checkCancellation() // a timed-out request must not change state when it finally returns
            turn = r.nextTurn
            if r.busy {
                try await Task.sleep(nanoseconds: busyMs * 1_000_000)
                r = try parse(try await transport(req()))
                try Task.checkCancellation()
                if r.busy { busyTwice = true; return nil }
                turn = r.nextTurn
            }
            return r
        })
        if case .success(let r?)? = outcome { return r }
        if !busyTwice { disabled = true }
        return nil
    }
}
