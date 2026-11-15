import Foundation

private func blank(_ s: String?) -> Bool { s == nil || s!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

/// Translation, else the form's own text, else the built-in fill. Nil when none exists.
package func pick(_ tr: String?, _ own: String?, _ fill: String? = nil) -> String? { blank(tr) ? (own ?? fill) : tr }

private extension Dictionary where Key == String, Value == Any {
    /// A copy with `k` set when `v` is non-nil.
    func with(_ k: String, _ v: String?) -> JSONObject { var d = self; if let v { d[k] = v }; return d }
}

private func optionJson(_ o: ChoiceOption, label: String? = nil) -> JSONObject {
    var d: JSONObject = ["value": o.value, "label": label ?? o.label]
    if let e = o.emoji { d["emoji"] = e }
    return d
}

/// Options with each label translated by value; the one mapping for pmf steps and select inputs.
private func localizeOptions(_ opts: [JSONObject], _ tr: JSONObject?) -> [JSONObject] {
    opts.map { o in o.with("label", pick(tr?.str(o.str("value") ?? ""), o.str("label"))) }
}

/// [default, ...others] in the admin's spelling; only codes equal after normalisation collapse.
package func formLanguages(_ content: JSONObject) -> [String] {
    let def = content.str("defaultLanguage")
    var out = [norm(def).isEmpty ? "en" : def!]
    for case let l as String in content.arr("languages") ?? [] where !norm(l).isEmpty && !out.contains(where: { norm($0) == norm(l) }) { out.append(l) }
    return out
}

private func localizeStep(_ step: JSONObject, _ tr: JSONObject?, _ b: BuiltinTexts?) -> JSONObject {
    var s = step
    s = s.with("title", pick(tr?.str("title"), step.str("title")))
    if step.has("subtitle") { s = s.with("subtitle", pick(tr?.str("subtitle"), step.str("subtitle"))) }
    let trLabels = tr?["labels"]
    func pair(_ def: (String, String), _ low: String?, _ high: String?) {
        let l = trLabels as? JSONObject, own = step["labels"] as? JSONObject
        let lo = pick(l?.str("low"), own?.str("low"), low), hi = pick(l?.str("high"), own?.str("high"), high)
        if lo != nil || hi != nil { s["labels"] = ["low": lo ?? def.0, "high": hi ?? def.1] as JSONObject }
    }
    let trOptions = tr?.obj("options")
    switch step.str("kind") {
    case "nps": pair(Defaults.nps, b?.npsLow, b?.npsHigh)
    case "enps": pair(Defaults.enps, b?.enpsLow, b?.enpsHigh)
    case "ces": pair(Defaults.ces, b?.cesLow, b?.cesHigh)
    case "csat":
        let l = trLabels as? [Any] ?? []
        func tl(_ i: Int) -> String? { i < l.count ? l[i] as? String : nil }
        // Without stored labels, English defaults are only written when a translation needs a base.
        let base = step.strings("labels") ?? b?.csat ?? (l.contains { !blank($0 as? String) } ? Defaults.csatLabels : nil)
        if let base { s["labels"] = base.enumerated().map { pick(tl($0.offset), $0.element)! } }
    case "pmf":
        let own = step.objects("options")
        let ownOptions = step.arr("options").flatMap { $0.isEmpty ? nil : own } // [] counts as absent, like the renderers
        let translated = trOptions?.values.contains { !blank($0 as? String) } == true
        let base: [JSONObject]? = ownOptions
            ?? b.map { t in Defaults.pmf.map { optionJson($0, label: t.pmf[$0.value]!) } }
            ?? (translated ? Defaults.pmf.map { optionJson($0) } : nil)
        if let base { s["options"] = localizeOptions(base, trOptions) }
    case "followup": if let i = step.obj("input") { s["input"] = localizeInput(i, tr, b) }
    default: break
    }
    return s
}

private func localizeInput(_ input: JSONObject, _ tr: JSONObject?, _ b: BuiltinTexts?) -> JSONObject {
    let type = input.str("type")
    if type == "selectOne" || type == "selectMultiple" {
        guard input.arr("options") != nil else { return input }
        var o = input
        o["options"] = localizeOptions(input.objects("options"), tr?.obj("options"))
        return o
    }
    let fill = type == "free" ? b?.answer : nil
    let own = input.str("placeholder")
    if own == nil && fill == nil { return input }
    return input.with("placeholder", pick(tr?.str("placeholder"), own, fill))
}

/// Built-in fill for one step outside a form, e.g. a follow-up question a conversation sent. English returns it untouched.
package func fillStep(_ step: JSONObject, _ lang: String) -> JSONObject {
    if let code = matchLanguage(lang, builtinLanguages), baseOf(code) != "en" { return localizeStep(step, nil, builtinTexts(code)) }
    return step
}

package func localizeContent(_ content: JSONObject, _ lang: String) -> JSONObject {
    let offered = formLanguages(content)
    let code = matchLanguage(lang, offered) ?? offered[0]
    let isDefault = code == offered[0]
    let builtinCode = matchLanguage(code, builtinLanguages)
    // English output never changes: the built-in fill is for other languages only.
    let b = builtinCode.flatMap { baseOf($0) != "en" ? builtinTexts($0) : nil }
    // Nothing to swap and nothing to fill: every existing form comes back untouched.
    if isDefault && b == nil { return content }

    let translations = content.obj("translations")
    let key = translations?.keys.first { norm($0) == norm(code) }
    let tr = isDefault ? nil : key.flatMap { translations?.obj($0) }

    var out = content
    ["languages", "defaultLanguage", "translations"].forEach { out[$0] = nil }
    if let steps = content.arr("steps") {
        out["steps"] = steps.compactMap { $0 as? JSONObject }.map { localizeStep($0, tr?.obj("steps")?.obj($0.str("id") ?? ""), b) }
    }
    out = out.with("submitLabel", pick(tr?.str("submitLabel"), content.str("submitLabel"), b?.submit))
        .with("nextLabel", pick(tr?.str("nextLabel"), content.str("nextLabel"), b?.next))
        .with("backLabel", pick(tr?.str("backLabel"), content.str("backLabel"), b?.back))
    if let h = content.obj("header") {
        out["header"] = h.with("title", pick(tr?.obj("header")?.str("title"), h.str("title")))
            .with("subtitle", pick(tr?.obj("header")?.str("subtitle"), h.str("subtitle")))
    }
    let th = content.obj("thanks")
    let tTitle = pick(tr?.obj("thanks")?.str("title"), th?.str("title"), b?.thanksTitle)
    let tSub = pick(tr?.obj("thanks")?.str("subtitle"), th?.str("subtitle"), b?.thanksSubtitle)
    if th != nil || tTitle != nil || tSub != nil { out["thanks"] = (th ?? [:]).with("title", tTitle).with("subtitle", tSub) }
    let fills: [(String, String?)] = [("sendLabel", b?.send), ("skipLabel", b?.skip), ("endLabel", b?.end), ("typingLabel", b?.typing), ("logLabel", b?.log)]
    var chat = content.obj("chat") ?? [:]
    for (k, fill) in fills { chat = chat.with(k, pick(tr?.obj("chat")?.str(k), content.obj("chat")?.str(k), fill)) }
    if !chat.isEmpty { out["chat"] = chat }
    return out
}
