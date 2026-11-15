import Foundation

/// One spelling rule for every language comparison: trimmed, `_` as `-`, lower case. Not a string = "".
package func norm(_ code: Any?) -> String {
    (code as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").lowercased() ?? ""
}
package func baseOf(_ code: Any?) -> String { String(norm(code).split(separator: "-", omittingEmptySubsequences: false).first ?? "") }

package struct LanguageInfo: Equatable { package let code: String, name: String; package let rtl: Bool }

// Region variants a respondent must tell apart; looked up by full tag before the base language.
private let regional = [
    "pt-br": "Português (Brasil)", "pt-pt": "Português (Portugal)",
    "zh-hans": "简体中文", "zh-hant": "繁體中文", "zh-cn": "简体中文", "zh-tw": "繁體中文",
    "en-us": "English (US)", "en-gb": "English (UK)",
    "es-419": "Español (Latinoamérica)", "es-es": "Español (España)", "fr-ca": "Français (Canada)",
]

private let names = [
    "en": "English", "bn": "বাংলা", "hi": "हिन्दी", "ur": "اردو", "ar": "العربية", "es": "Español", "fr": "Français",
    "de": "Deutsch", "pt": "Português", "id": "Bahasa Indonesia", "tr": "Türkçe", "zh": "中文", "ja": "日本語",
    "fa": "فارسی", "he": "עברית", "ru": "Русский", "it": "Italiano", "ko": "한국어", "th": "ไทย", "vi": "Tiếng Việt",
    "ms": "Bahasa Melayu", "ta": "தமிழ்", "ne": "नेपाली", "si": "සිංහල",
]
private let rtlBases: Set<String> = ["ar", "fa", "he", "ur"]

private func displayName(_ code: String) -> String? {
    let id = norm(code)
    let loc = Locale(identifier: id)
    guard let n = loc.localizedString(forIdentifier: id), !n.isEmpty, norm(n) != id else { return nil }
    return n.prefix(1).uppercased(with: loc) + n.dropFirst()
}

package func languageInfo(_ code: String) -> LanguageInfo {
    let b = baseOf(code), n = norm(code)
    // Table names first so the switcher label never depends on the platform's locale data.
    let name = regional[n] ?? (n == b ? names[b] : nil) ?? displayName(code) ?? names[b] ?? code
    return LanguageInfo(code: code, name: name, rtl: rtlBases.contains(b))
}

/// Exact tag, then `wanted` truncated one subtag at a time (zh-Hant-TW, zh-Hant, zh), then the
/// first offered code with the same base language. Returns the offered code's own spelling.
package func matchLanguage(_ wanted: String?, _ offered: [String]) -> String? {
    let w = norm(wanted)
    if w.isEmpty { return nil }
    func find(_ pred: (String) -> Bool) -> String? { offered.first { pred(norm($0)) } }
    let parts = w.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    for n in stride(from: parts.count, through: 1, by: -1) {
        let tag = parts.prefix(n).joined(separator: "-")
        if let m = find({ $0 == tag }) { return m }
    }
    // Chinese devices send regions (zh-TW), forms list scripts (zh-Hant): pick the script before any zh.
    if parts[0] == "zh" && !parts.contains("hans") && !parts.contains("hant") {
        let script = parts.contains { $0 == "tw" || $0 == "hk" || $0 == "mo" } ? "zh-hant" : "zh-hans"
        if let m = find({ $0 == script || $0.hasPrefix("\(script)-") }) { return m }
    }
    return find { $0.split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) == parts[0] }
}

/// First of remembered, developer, then device languages the form offers; else its default.
package func resolveLanguage(_ content: JSONObject, remembered: String?, developer: String?, device: [String]) -> String {
    let offered = formLanguages(content)
    for c in [remembered, developer] + device.map(Optional.some) {
        if let m = matchLanguage(c, offered) { return m }
    }
    return offered[0]
}

package func deviceLanguages() -> [String] { Locale.preferredLanguages }
