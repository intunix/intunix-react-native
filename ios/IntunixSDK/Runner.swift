import Foundation

package enum Phase { case running, thanks, review, done }

package struct RunnerState {
    package let currentIndex: Int
    package let visibleSteps: [Step]
    package let pageSteps: [Step]
    package let pageIndex: Int
    package let pageCount: Int
    package let paged: Bool
    package let answers: [Answer]
    package let phase: Phase
}

/// Consecutive steps sharing a `page` value form one page; a step without `page` is its own page.
package func groupPages(_ steps: [Step]) -> [[Step]] {
    var pages: [[Step]] = []
    var prev: Step?
    for s in steps {
        if let p = prev, let page = s.page, page == p.page, !pages.isEmpty { pages[pages.count - 1].append(s) }
        else { pages.append([s]) }
        prev = s
    }
    return pages
}

/// Port of @intunix/core FeedbackRunner.
package final class FeedbackRunner {
    private var content: FeedbackContent
    /// Own copy so insertAfter never changes the caller's content.
    private var steps: [Step]
    /// Inserted step id -> id of the step it follows.
    private var anchors: [String: String] = [:]
    private let review: ReviewRequestConfig?
    private let clock: () -> Int64
    private var answers: [Answer] = []
    private var visible: [Step] = []
    private var pages: [[Step]] = []
    private var page = 0
    private var phase = Phase.running
    private let startedAt: Int64
    private let paged: Bool

    package init(_ content: FeedbackContent, review: ReviewRequestConfig?, clock: @escaping () -> Int64 = nowMs) {
        self.content = content; steps = content.steps; self.review = review; self.clock = clock
        startedAt = clock()
        paged = content.steps.contains { $0.page != nil }
        recompute()
        if visible.isEmpty { advanceToEnd() }
    }

    package func state() -> RunnerState {
        let running = phase == .running
        return RunnerState(currentIndex: running ? pages.prefix(page).reduce(0) { $0 + $1.count } : visible.count,
                           visibleSteps: visible,
                           pageSteps: running && page < pages.count ? pages[page] : [],
                           pageIndex: running ? page : pages.count,
                           pageCount: pages.count, paged: paged, answers: answers, phase: phase)
    }

    @discardableResult package func record(_ a: Answer) -> RunnerState {
        guard phase == .running, onPage(a.stepId) else { return state() }
        if isEmptyAnswer(a) { return clear(a.stepId) }
        if let i = answers.firstIndex(where: { $0.stepId == a.stepId }) { answers[i] = a } else { answers.append(a) }
        recompute()
        return state()
    }

    @discardableResult package func clear(_ stepId: String) -> RunnerState {
        guard phase == .running, onPage(stepId) else { return state() }
        answers.removeAll { $0.stepId == stepId }
        recompute()
        return state()
    }

    @discardableResult package func submitPage() -> RunnerState {
        guard phase == .running else { return state() }
        if page >= pages.count - 1 { advanceToEnd() } else { page += 1 }
        return state()
    }

    @discardableResult package func answer(_ a: Answer) -> RunnerState {
        guard phase == .running, onPage(a.stepId) else { return state() }
        record(a)
        return submitPage()
    }

    @discardableResult package func back() -> RunnerState {
        guard phase == .running, page > 0 else { return state() }
        page -= 1
        recompute()
        return state()
    }

    package func dismiss() -> FeedbackResponse { phase = .done; return FeedbackResponse(answers: answersForVisible(), completed: false, durationMs: clock() - startedAt) }
    package func finish() -> FeedbackResponse { phase = .done; return FeedbackResponse(answers: answersForVisible(), completed: true, durationMs: clock() - startedAt) }
    package func isLastPage() -> Bool { page == pages.count - 1 }

    /// Insert a step right after `afterStepId` (a page of its own). No-op if that id is unknown, the step id exists, or the form is no longer running.
    @discardableResult package func insertAfter(_ afterStepId: String, _ step: Step) -> RunnerState {
        guard phase == .running, let at = steps.firstIndex(where: { $0.id == afterStepId }), !steps.contains(where: { $0.id == step.id }) else { return state() }
        // Keep a grouped page whole: insert after its last step, then after probes already inserted for this anchor.
        var end = at
        if let group = steps[at].page { while end + 1 < steps.count, steps[end + 1].page == group { end += 1 } }
        let mine = insertedUnder(afterStepId)
        while end + 1 < steps.count, mine.contains(steps[end + 1].id) { end += 1 }
        keepPage {
            steps.insert(step, at: end + 1)
            anchors[step.id] = afterStepId
        }
        return state()
    }

    /// Swap the text of the form (a language switch). Steps are replaced by id; probes, answers, page and phase stay.
    @discardableResult package func setContent(_ content: FeedbackContent) -> RunnerState {
        let fresh = Dictionary(content.steps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        keepPage {
            self.content = content
            steps = steps.map { s in fresh[s.id].flatMap { $0.kind == s.kind ? $0 : nil } ?? s } // a changed kind would orphan its answer
        }
        return state()
    }

    /// Remove every step inserted after `anchorStepId` (directly or chained), with their answers.
    @discardableResult package func removeInsertedAfter(_ anchorStepId: String) -> RunnerState {
        let dead = insertedUnder(anchorStepId)
        if dead.isEmpty { return state() }
        keepPage { removeSteps(dead) }
        return state()
    }

    package func thanksEnabled() -> Bool { content.thanks?.enabled != false }

    private func insertedUnder(_ anchor: String) -> Set<String> {
        var out = Set<String>()
        var grew = true
        while grew {
            grew = false
            for (id, a) in anchors where !out.contains(id) && (a == anchor || out.contains(a)) { out.insert(id); grew = true }
        }
        return out
    }

    private func removeSteps(_ dead: Set<String>) {
        steps.removeAll { dead.contains($0.id) }
        dead.forEach { anchors[$0] = nil }
        answers.removeAll { dead.contains($0.stepId) }
    }

    /// Run a steps change, recompute, and stay on the step the respondent was on.
    private func keepPage(_ change: () -> Void) {
        let here = phase == .running && page < pages.count ? pages[page].first?.id : nil
        change()
        recompute()
        if let here, let moved = pages.firstIndex(where: { $0.contains { $0.id == here } }) { page = moved }
    }

    private func onPage(_ id: String) -> Bool { page < pages.count && pages[page].contains { $0.id == id } }

    private func advanceToEnd() {
        if reviewQualifies(review, answersForVisible()) { phase = .review; page = pages.count; return }
        if content.thanks?.enabled != false { phase = .thanks; page = pages.count } else { phase = .done }
    }

    private func recompute() {
        while true {
            var shown = Set<String>(), orphans = Set<String>()
            visible = steps.filter { s in
                // An inserted probe is removed for good with the step it followed.
                if let a = anchors[s.id], !shown.contains(a) { orphans.insert(s.id); return false }
                let ok = evaluateShowIf(s.showIf, answers)
                if ok { shown.insert(s.id) }
                return ok
            }
            if !orphans.isEmpty { removeSteps(orphans) }
            let ids = Set(visible.map(\.id))
            let kept = answers.filter { ids.contains($0.stepId) }
            if kept.count == answers.count { break }
            answers = kept
        }
        pages = groupPages(visible)
        if phase == .running && page >= pages.count { page = max(0, pages.count - 1) }
    }

    private func answersForVisible() -> [Answer] {
        answers.filter { a in visible.first { $0.id == a.stepId }.map { isAnswerValid($0, a) } ?? false }
    }
}

package func isEmptyAnswer(_ a: Answer) -> Bool {
    switch a.value {
    case .text(_, let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .many(let s): return s.isEmpty
    case .one(let s): return s.isEmpty
    default: return false
    }
}
