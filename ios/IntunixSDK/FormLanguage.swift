import Foundation

/// Where a form's language preferences come from; read only for multi-language forms.
package struct LocaleSource {
    package let developer: () -> String?
    package let remembered: () -> String?
    package let remember: (String) -> Void
    package init(developer: @escaping () -> String?, remembered: @escaping () -> String?, remember: @escaping (String) -> Void) {
        self.developer = developer; self.remembered = remembered; self.remember = remember
    }
}

/// The language state of one form: resolved at start, switchable, re-localizing the content.
package final class FormLanguage {
    private let raw: JSONObject
    private let source: LocaleSource?
    package let multi: Bool
    package private(set) var lang: String
    /// True when the content differs from the raw form (several languages, or a non-English one to fill).
    package let decorated: Bool
    package private(set) var content: FeedbackContent
    package let options: [LanguageInfo]

    package init(raw: JSONObject, source: LocaleSource?, device: [String]) {
        self.raw = raw; self.source = source
        multi = formLanguages(raw).count >= 2
        let l = multi ? resolveLanguage(raw, remembered: source?.remembered(), developer: source?.developer(), device: device) : formLanguages(raw)[0]
        lang = l
        decorated = multi || baseOf(l) != "en"
        content = FormLanguage.build(raw, l, decorated)
        options = formLanguages(raw).map(languageInfo)
    }

    package var rtl: Bool { decorated && languageInfo(lang).rtl }

    /// Built-in texts for the chrome (buttons, page labels); nil for a plain English form.
    package var texts: BuiltinTexts? { decorated ? builtinTexts(lang) : nil }

    package func switchTo(_ code: String) -> Bool {
        guard multi, code != lang, options.contains(where: { $0.code == code }) else { return false }
        source?.remember(code)
        lang = code
        content = FormLanguage.build(raw, code, decorated)
        return true
    }

    /// Multi-language forms report the language the respondent answered in.
    package func decorate(_ r: FeedbackResponse) -> FeedbackResponse {
        guard multi else { return r }
        var o = r; o.language = lang; return o
    }

    private static func build(_ raw: JSONObject, _ lang: String, _ decorated: Bool) -> FeedbackContent {
        parseFeedbackContent(decorated ? localizeContent(raw, lang) : raw)!
    }
}
