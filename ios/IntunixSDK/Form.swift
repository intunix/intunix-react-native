#if os(iOS)
import SwiftUI

/// SwiftUI face of ``FormController``: forwards state and bumps `version` so views redraw.
@MainActor
final class FormHost: ObservableObject {
    let core: FormController
    @Published private(set) var version = 0

    init(exp: Experience, callbacks: RenderCallbacks, openUrl: @escaping (String) -> Bool, device: [String] = deviceLanguages(),
         onResult: @escaping (ExperienceResult) -> Void) {
        core = FormController(exp: exp, callbacks: callbacks, openUrl: openUrl, device: device, onResult: onResult)
        core.onChange = { [weak self] in self?.version += 1 }
    }

    var exp: Experience { core.exp }
    var content: FeedbackContent { core.content }
    var language: FormLanguage { core.language }
    var review: ReviewPresenter? { core.review }
    var closable: Bool { core.closable }
    var probing: Bool { core.probing }
    var chat: ConversationController? { core.chat }
    var chatReview: Bool { core.chatReview }
    var state: RunnerState { core.state() }
    var chatState: ConversationState { core.chatState() }
    var chatInput: Step? { core.chatInput() }
    var chatLabels: ChatLabels { core.labels() }
    func isLastPage() -> Bool { core.isLastPage() }
    func autoSubmit() -> Bool { core.autoSubmit() }
    func impression() { core.impression() }
    func finish() { core.finish() }
    func close() { core.close() }
    func onChange(_ stepId: String, _ answer: Answer?) { core.onAnswer(stepId, answer) }
    func submitPage() { core.submitPage() }
    func back() { core.back() }
    func sendChat(_ a: Answer) { core.sendChat(a) }
    func skipChat() { core.skipChat() }
    func switchLanguage(_ code: String) { core.switchLanguage(code) }
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
    @Environment(\.formDark) private var dark
    @Environment(\.layoutDirection) private var direction // the parent's: RtlRoot is applied inside body

    var body: some View {
        let state = host.state
        let brand = BrandColors(host.content.brand.color, dark: dark)
        let width = fixedWidth ?? (measured > 0 ? measured : 320)
        let ending = state.phase == .thanks || state.phase == .review
        let texts = host.language.texts
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Header(pageIndex: state.pageIndex, pageCount: state.pageCount, paged: state.paged, ending: ending, closable: host.closable,
                       texts: texts, language: state.phase == .running && host.language.multi ? switcher(texts) : nil)
                if state.phase == .review, let review = host.review {
                    ReviewCard(p: review)
                } else if state.phase == .thanks {
                    Thanks(title: host.content.thanks?.title ?? texts?.thanksTitle ?? Defaults.thanksTitle,
                           subtitle: host.content.thanks?.subtitle ?? texts?.thanksSubtitle ?? Defaults.thanksSubtitle)
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
                               backLabel: host.content.backLabel ?? texts?.back ?? Defaults.back,
                               nextLabel: host.isLastPage() ? host.content.submitLabel ?? texts?.submit ?? Defaults.submit : host.content.nextLabel ?? texts?.next ?? Defaults.next,
                               nextEnabled: isPageValid(state.pageSteps, state.answers) && !host.probing,
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
                .accessibilityLabel(texts?.close ?? "Close")
                .offset(x: (host.language.decorated ? host.language.rtl : direction == .rightToLeft) ? -8 : 8, y: -8)
            }
        }
        .environment(\.brand, brand)
        .environment(\.formWidth, width)
        .modifier(RtlRoot(language: host.language))
        .background(GeometryReader { g in Color.clear.preference(key: WidthPref.self, value: g.size.width) })
        .onPreferenceChange(WidthPref.self) { measured = $0 }
        .onAppear { host.impression() }
        .task(id: state.phase) { await phaseChanged(state.phase) }
    }

    private func switcher(_ texts: BuiltinTexts?) -> LanguageSwitcher? {
        texts.map { LanguageSwitcher(current: host.language.lang, options: host.language.options, label: $0.language, onChange: host.switchLanguage) }
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
    var texts: BuiltinTexts? = nil
    var language: LanguageSwitcher? = nil
    @Environment(\.brand) var brand
    var body: some View {
        if pageCount <= 1 && language == nil {
            Spacer().frame(height: closable ? 30 : 0)
        } else {
            let label = pageLabel(texts, ending: ending, paged: paged, index: pageIndex, count: pageCount)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if pageCount > 1 || language == nil { Text(label).crispFont(12, .semibold, Crisp.muted).frame(minHeight: 24) }
                    Spacer(minLength: 0)
                    if let language { language }
                }
                .padding(.trailing, closable || language == nil ? 36 : 0)
                if pageCount > 1 {
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
}

private struct Footer: View {
    let showBack: Bool, backLabel: String, nextLabel: String, nextEnabled: Bool
    let onBack: () -> Void, onNext: () -> Void
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width
    @Environment(\.layoutDirection) var direction

    var body: some View {
        let wide = width >= Crisp.wideAt
        let arrow = direction == .rightToLeft ? "→" : "←"
        HStack(spacing: 10) {
            if showBack {
                Button(action: onBack) {
                    Text(wide ? "\(arrow)  \(backLabel)" : arrow).crispFont(15, .semibold, Crisp.scaleText)
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

struct ReviewCard: View {
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
