#if os(iOS)
import SwiftUI

/// Mirrors the layout for right-to-left languages. One wrapper for the form and the chat; a plain form is untouched.
struct RtlRoot: ViewModifier {
    let language: FormLanguage
    func body(content: Content) -> some View {
        if language.decorated { content.environment(\.layoutDirection, language.rtl ? .rightToLeft : .leftToRight) } else { content }
    }
}

/// The language button of the header: a native Menu (own focus, dismissal and VoiceOver behaviour).
struct LanguageSwitcher: View {
    let current: String
    let options: [LanguageInfo]
    /// Built-in "Language" text of the current language, for VoiceOver.
    let label: String
    let onChange: (String) -> Void

    /// Read in its own language by VoiceOver.
    private func spoken(_ o: LanguageInfo) -> Text {
        var a = AttributedString(o.name)
        a.languageIdentifier = o.code
        return Text(a)
    }

    var body: some View {
        let now = languageInfo(current)
        Menu {
            ForEach(options, id: \.code) { o in
                Button { if o.code != current { onChange(o.code) } } label: {
                    if o.code == current { Label { spoken(o) } icon: { Image(systemName: "checkmark") } } else { spoken(o) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 14))
                spoken(now).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Crisp.scaleText)
            .padding(.horizontal, 10).frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Crisp.border, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44) // touch target
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: "\(label), \(now.name)"))
    }
}
#endif
