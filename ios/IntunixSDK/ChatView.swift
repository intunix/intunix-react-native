#if os(iOS)
import SwiftUI

/// A conversational form: the controller's state drawn as a message log with one input at a time.
struct ChatForm: View {
    @ObservedObject var host: FormHost
    var fixedWidth: CGFloat? = nil
    @State private var measured: CGFloat = 0
    @Environment(\.formDark) private var dark

    var body: some View {
        let state = host.chatState
        let width = fixedWidth ?? (measured > 0 ? measured : 320)
        ChatView(state: state, input: host.chatInput, labels: host.chatLabels, texts: host.language.texts,
                 language: host.language.multi && !state.done ? switcher : nil, closable: host.closable,
                 onAnswer: host.sendChat, onSkip: host.skipChat, onEnd: host.close, onClose: host.close,
                 footer: host.chatReview ? host.review : nil)
            .environment(\.brand, BrandColors(host.content.brand.color, dark: dark))
            .environment(\.formWidth, width)
            .modifier(RtlRoot(language: host.language))
            .background(GeometryReader { g in Color.clear.preference(key: ChatWidthPref.self, value: g.size.width) })
            .onPreferenceChange(ChatWidthPref.self) { measured = $0 }
            .onAppear { host.impression() }
    }

    private var switcher: LanguageSwitcher? {
        host.language.texts.map { LanguageSwitcher(current: host.language.lang, options: host.language.options, label: $0.language, onChange: host.switchLanguage) }
    }
}

private struct ChatWidthPref: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Stateless chat view; `footer` (the review card) replaces the Skip / End row.
struct ChatView: View {
    let state: ConversationState
    let input: Step?
    let labels: ChatLabels
    let texts: BuiltinTexts?
    let language: LanguageSwitcher?
    let closable: Bool
    let onAnswer: (Answer) -> Void
    let onSkip: () -> Void
    let onEnd: () -> Void
    let onClose: () -> Void
    var footer: ReviewPresenter? = nil
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let pages = max(state.total, 1)
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                ChatHeader(index: state.done ? pages : min(state.answered, pages - 1), count: pages, done: state.done,
                           closable: closable, texts: texts, language: language)
                ChatLog(state: state, labels: labels)
                if let input, !state.pending, !state.done { ChatInput(step: input, labels: labels, onAnswer: onAnswer) }
                if let footer { ReviewCard(p: footer) }
                else {
                    HStack(spacing: 8) {
                        if state.canSkip { ChatLink(label: labels.skip, action: onSkip) }
                        Spacer(minLength: 0)
                        if !state.done { ChatLink(label: labels.end, action: onEnd) }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if closable {
                Button(action: onClose) { Text("×").crispFont(22, .regular, Crisp.muted).frame(width: 36, height: 36) }
                    .buttonStyle(TapStyle())
                    .accessibilityLabel(texts?.close ?? "Close")
                    .offset(x: direction == .rightToLeft ? -8 : 8, y: -8)
            }
        }
    }
}

private struct ChatHeader: View {
    let index: Int, count: Int, done: Bool, closable: Bool
    let texts: BuiltinTexts?
    let language: LanguageSwitcher?
    @Environment(\.brand) private var brand

    var body: some View {
        if count <= 1 && language == nil {
            Spacer().frame(height: closable ? 30 : 0)
        } else {
            let label = pageLabel(texts, ending: done, paged: true, index: index, count: count)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if count > 1 { Text(label).crispFont(12, .semibold, Crisp.muted).frame(minHeight: 24) }
                    Spacer(minLength: 0)
                    if let language { language }
                }
                .padding(.trailing, closable ? (language == nil ? 36 : 28) : 0) // 8pt toward the close button: the switcher's own touch padding would double the gap
                if count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4).fill(done || i <= index ? brand.color : Crisp.track).frame(height: 4)
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
    }
}

private struct ChatLog: View {
    let state: ConversationState
    let labels: ChatLabels
    @Environment(\.brand) private var brand
    private let bottom = "chat-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(state.messages.enumerated()), id: \.offset) { i, m in
                        let nia = m.role == "nia"
                        if nia && (i == 0 || state.messages[i - 1].role != "nia") { NameLabel(name: labels.name) }
                        bubble(nia ? brand.soft : brand.color) { Text(m.text).crispFont(14, .regular, nia ? Crisp.text : brand.onColor).fixedSize(horizontal: false, vertical: true) }
                            .frame(maxWidth: .infinity, alignment: nia ? .leading : .trailing)
                    }
                    if state.pending {
                        if state.messages.last?.role != "nia" { NameLabel(name: labels.name) }
                        bubble(brand.soft) {
                            HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Crisp.muted).frame(width: 6, height: 6) } }.frame(height: 20)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(labels.typing)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
            }
            .frame(maxHeight: 360)
            // After layout: the new bubble exists by the time this runs (not before it, as with an onChange of the state).
            .onChange(of: state.messages.count) { _ in
                DispatchQueue.main.async { proxy.scrollTo(bottom, anchor: .bottom) }
                // The iOS stand-in for a polite live region: VoiceOver reads each new assistant message.
                if let m = state.messages.last, m.role == "nia" { UIAccessibility.post(notification: .announcement, argument: m.text) }
            }
            .onChange(of: state.pending) { _ in DispatchQueue.main.async { proxy.scrollTo(bottom, anchor: .bottom) } }
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(bottom, anchor: .bottom) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(labels.log)
    }

    private func bubble<C: View>(_ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        content().padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(color))
            .frame(maxWidth: 280, alignment: .leading)
    }
}

private struct NameLabel: View {
    let name: String
    var body: some View { Text(name).crispFont(11, .semibold, Crisp.muted).padding(.leading, 4) }
}

private struct ChatInput: View {
    let step: Step
    let labels: ChatLabels
    let onAnswer: (Answer) -> Void
    @Environment(\.brand) private var brand
    @State private var current: Answer?

    var body: some View {
        let tap = submitsOnTap(step)
        let sendable = current.map { isAnswerValid(step, $0) && !isEmptyAnswer($0) } == true
        VStack(alignment: .leading, spacing: 12) {
            StepView(step: step, answer: current) { a in
                current = a
                if tap, let a { onAnswer(a) }
            }
            if !tap {
                Button { if let current { onAnswer(current) } } label: {
                    Text(labels.send).crispFont(14, .semibold, brand.onColor).padding(.horizontal, 22).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(brand.color)).opacity(sendable ? 1 : 0.4)
                }
                .buttonStyle(TapStyle()).disabled(!sendable)
            }
        }
        .padding(.top, 12)
        // A new question starts blank; a language switch keeps the same id, so typed text stays.
        .id(step.id)
    }
}

private struct ChatLink: View {
    let label: String, action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).crispFont(14, .medium, Crisp.muted).padding(.horizontal, 8).frame(minHeight: 44) }.buttonStyle(TapStyle())
    }
}

#endif
