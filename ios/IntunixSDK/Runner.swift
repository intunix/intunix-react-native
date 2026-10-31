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
    private let content: FeedbackContent
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
        self.content = content; self.review = review; self.clock = clock
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
        if isEmpty(a) { return clear(a.stepId) }
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

    private func onPage(_ id: String) -> Bool { page < pages.count && pages[page].contains { $0.id == id } }

    private func advanceToEnd() {
        if reviewQualifies(review, answersForVisible()) { phase = .review; page = pages.count; return }
        if content.thanks?.enabled != false { phase = .thanks; page = pages.count } else { phase = .done }
    }

    private func recompute() {
        while true {
            visible = content.steps.filter { evaluateShowIf($0.showIf, answers) }
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

    private func isEmpty(_ a: Answer) -> Bool {
        switch a.value {
        case .text(_, let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .many(let s): return s.isEmpty
        case .one(let s): return s.isEmpty
        default: return false
        }
    }
}
