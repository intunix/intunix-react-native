#if os(iOS)
import SwiftUI

private let autoSubmitKinds: Set<String> = ["thumbs", "pmf", "smileys"]

/// Form state and the rules of FeedbackExperience (React), independent of where it is drawn.
@MainActor
final class FormHost: ObservableObject {
    let exp: Experience
    let content: FeedbackContent
    private let cb: RenderCallbacks
    private let runner: FeedbackRunner
    private let onResult: (ExperienceResult) -> Void
    private var settled = false
    private(set) var review: ReviewPresenter?
    @Published private(set) var state: RunnerState

    init(exp: Experience, content: FeedbackContent, callbacks: RenderCallbacks, openUrl: @escaping (String) -> Bool,
         onResult: @escaping (ExperienceResult) -> Void) {
        self.exp = exp; self.content = content; cb = callbacks; self.onResult = onResult
        runner = FeedbackRunner(content, review: exp.reviewRequest)
        state = runner.state()
        review = ReviewPresenter.create(exp.reviewRequest, formId: exp.id, clientResponseId: callbacks.clientResponseId,
                                        brandColor: content.brand.color, emit: callbacks.onReviewEvent, openUrl: openUrl) { [weak self] in self?.finish() }
    }

    var closable: Bool { content.closable }
    func isLastPage() -> Bool { runner.isLastPage() }
    private var impressed = false
    /// Once per form instance, however often the view appears (navigation, tabs, lists).
    func impression() {
        guard !impressed else { return }
        impressed = true
        cb.onImpression()
    }

    private func bump() { state = runner.state() }

    private func finalize(_ r: ExperienceResult) {
        guard !settled else { return }
        settled = true
        onResult(r)
    }

    func finish() {
        finalize(ExperienceResult(outcome: "responded", response: runner.finish()))
        bump()
    }

    func close() {
        guard !settled else { return }
        switch runner.state().phase {
        case .review: if let review { review.onSkip() } else { finish() }
        case .thanks, .done: finish()
        case .running:
            let r = runner.dismiss()
            cb.onDismiss()
            finalize(ExperienceResult(outcome: r.answers.isEmpty ? "dismissed" : "responded", response: r))
            bump()
        }
    }

    /// Thumbs / PMF / smileys submit on tap only when the whole form is that one question.
    func autoSubmit() -> Bool {
        let s = runner.state()
        guard s.visibleSteps.count == 1, s.pageSteps.count == 1, let only = s.pageSteps.first else { return false }
        return autoSubmitKinds.contains(only.kind) && (only.page == nil || content.steps.filter { $0.page == only.page }.count == 1)
    }

    func onChange(_ stepId: String, _ answer: Answer?) {
        let auto = autoSubmit()
        if let answer { runner.record(answer) } else { runner.clear(stepId) }
        if auto && answer != nil { submitPage() } else { bump() }
    }

    func submitPage() {
        let s = runner.state()
        guard isPageValid(s.pageSteps, s.answers) else { return }
        for step in s.pageSteps { if let a = s.answers.first(where: { $0.stepId == step.id }) { cb.onResponse(a) } }
        runner.submitPage()
        bump()
    }

    func back() { runner.back(); bump() }
}

private struct WidthPref: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The form itself (header, questions, footer, thanks, review card). The host decides the frame.
struct FeedbackFormView: View {
    @ObservedObject var host: FormHost
    /// Fixed layout width (snapshots); nil measures the space given.
    var fixedWidth: CGFloat? = nil
    @State private var measured: CGFloat = 0

    var body: some View {
        let state = host.state
        let brand = BrandColors(host.content.brand.color)
        let width = fixedWidth ?? (measured > 0 ? measured : 320)
        let ending = state.phase == .thanks || state.phase == .review
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Header(pageIndex: state.pageIndex, pageCount: state.pageCount, paged: state.paged, ending: ending, closable: host.closable)
                if state.phase == .review, let review = host.review {
                    ReviewCard(p: review)
                } else if state.phase == .thanks {
                    Thanks(title: host.content.thanks?.title ?? Defaults.thanksTitle, subtitle: host.content.thanks?.subtitle ?? Defaults.thanksSubtitle)
                } else if !state.pageSteps.isEmpty {
                    ForEach(Array(state.pageSteps.enumerated()), id: \.element.id) { i, step in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(step.title).crispFont(18, .semibold).fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader).padding(.bottom, 6)
                            if let sub = step.subtitle, !sub.isEmpty {
                                Text(sub).crispFont(14, .regular, Crisp.muted).fixedSize(horizontal: false, vertical: true).padding(.bottom, 16)
                            } else { Spacer().frame(height: 8) }
                            StepView(step: step, answer: state.answers.first { $0.stepId == step.id }) { host.onChange(step.id, $0) }
                        }
                        .padding(.top, i > 0 ? 28 : 0)
                    }
                    if !host.autoSubmit() {
                        Footer(showBack: state.pageIndex > 0,
                               backLabel: host.content.backLabel ?? Defaults.back,
                               nextLabel: host.isLastPage() ? host.content.submitLabel ?? Defaults.submit : host.content.nextLabel ?? Defaults.next,
                               nextEnabled: isPageValid(state.pageSteps, state.answers),
                               onBack: host.back, onNext: host.submitPage)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if host.closable {
                Button(action: host.close) {
                    Text("×").crispFont(22, .regular, Crisp.muted).frame(width: 36, height: 36)
                }
                .buttonStyle(TapStyle())
                .accessibilityLabel("Close")
                .offset(x: 8, y: -8)
            }
        }
        .environment(\.brand, brand)
        // Forms are light-only, as on web; keeps system text views white in dark mode.
        .environment(\.colorScheme, .light)
        .environment(\.formWidth, width)
        .background(GeometryReader { g in Color.clear.preference(key: WidthPref.self, value: g.size.width) })
        .onPreferenceChange(WidthPref.self) { measured = $0 }
        .onAppear { host.impression() }
        .task(id: state.phase) { await phaseChanged(state.phase) }
    }

    @MainActor private func phaseChanged(_ phase: Phase) async {
        switch phase {
        case .thanks:
            let ms = host.content.thanks?.autoCloseMs ?? Defaults.thanksAutoCloseMs
            if ms > 0 {
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                if !Task.isCancelled { host.finish() }
            }
        case .review: host.review?.onShown()
        case .done: host.finish()
        case .running: break
        }
    }
}

private struct Header: View {
    let pageIndex: Int, pageCount: Int, paged: Bool, ending: Bool, closable: Bool
    @Environment(\.brand) var brand
    var body: some View {
        if pageCount <= 1 {
            Spacer().frame(height: closable ? 30 : 0)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(ending ? "Done" : "\(paged ? "Page" : "Question") \(pageIndex + 1) of \(pageCount)")
                    .crispFont(12, .semibold, Crisp.muted).padding(.trailing, 36).frame(minHeight: 24)
                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4).fill(ending || i <= pageIndex ? brand.color : Crisp.track).frame(height: 4)
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }
}

private struct Footer: View {
    let showBack: Bool, backLabel: String, nextLabel: String, nextEnabled: Bool
    let onBack: () -> Void, onNext: () -> Void
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let wide = width >= Crisp.wideAt
        HStack(spacing: 10) {
            if showBack {
                Button(action: onBack) {
                    Text(wide ? "←  \(backLabel)" : "←").crispFont(15, .semibold, Crisp.scaleText)
                        .padding(.horizontal, wide ? 18 : 0)
                        .frame(minWidth: 50, minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Crisp.border, lineWidth: 1.5))
                }
                .buttonStyle(TapStyle())
                .accessibilityLabel(backLabel)
            }
            if wide { Spacer(minLength: 0) }
            Button(action: onNext) {
                Text(nextLabel).crispFont(15, .semibold, brand.onColor)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: wide ? nil : .infinity, minHeight: 50)
                    .frame(minWidth: wide ? 120 : nil)
                    .background(RoundedRectangle(cornerRadius: 14).fill(brand.color))
                    .opacity(nextEnabled ? 1 : 0.4)
            }
            .buttonStyle(TapStyle())
            .disabled(!nextEnabled)
        }
        .padding(.top, 24)
    }
}

private struct Thanks: View {
    let title: String, subtitle: String
    @Environment(\.brand) var brand
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(brand.soft)
                CheckIcon(color: brand.color).frame(width: 24, height: 24)
            }
            .frame(width: 52, height: 52)
            .padding(.bottom, 14)
            Text(title).crispFont(18, .semibold).multilineTextAlignment(.center)
            if !subtitle.isEmpty { Text(subtitle).crispFont(14, .regular, Crisp.muted).multilineTextAlignment(.center).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 16, leading: 4, bottom: 4, trailing: 4))
    }
}

private struct ReviewCard: View {
    let p: ReviewPresenter
    @Environment(\.brand) var brand
    var body: some View {
        let accent = Color.parse(p.themeColor) ?? brand.color
        let on = Color.parse(p.themeColor) != nil ? BrandColors(p.themeColor).onColor : brand.onColor
        VStack(spacing: 0) {
            Text(p.title).crispFont(18, .semibold).multilineTextAlignment(.center)
            Text(p.description).crispFont(14, .regular, Crisp.muted).multilineTextAlignment(.center).padding(.top, 6)
            Button { p.onClick() } label: {
                Text(p.buttonText).crispFont(15, .semibold, p.outline ? accent : on)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(p.outline ? Color.clear : accent))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.outline ? accent : .clear, lineWidth: 1.5))
            }
            .buttonStyle(TapStyle())
            .accessibilityLabel("\(p.buttonText) (opens in your browser)")
            .padding(.top, 20)
            Button { p.onSkip() } label: {
                Text(p.skipText).crispFont(14, .medium, Crisp.muted).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(TapStyle())
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
}
#endif
