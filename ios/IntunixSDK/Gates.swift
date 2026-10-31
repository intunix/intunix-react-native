import Foundation

package struct GateUser {
    package var id: String?
    package var traits: JSONObject
    package init(id: String?, traits: JSONObject) { self.id = id; self.traits = traits }
}

/// This SDK runs in apps; a form limited to the web never shows here.
package func checkPlatform(_ exp: Experience) -> Bool { exp.platforms?.contains("app") ?? true }

private func evalRule(_ rule: TargetingRule, _ user: GateUser?, _ context: JSONObject, _ screen: String) -> Bool {
    let missing: Bool
    let subject: Any?
    switch rule.kind {
    // Web matches 'url' against the page URL; in apps the current screen plays that role.
    case "url": subject = screen; missing = false
    case "trait":
        let m = user?.traits
        missing = rule.key == nil || m == nil || m?[rule.key!] == nil
        subject = rule.key.flatMap { m?[$0] }
    default:
        missing = rule.key == nil || context[rule.key!] == nil
        subject = rule.key.flatMap { context[$0] }
    }
    if missing && rule.op != "exists" && rule.op != "neq" && rule.op != "nin" { return false }
    switch rule.op {
    case "eq": return jsEquals(subject, rule.value)
    case "neq": return missing ? rule.hasValue : !jsEquals(subject, rule.value)
    case "in": return (rule.value as? [Any])?.contains { jsEquals($0, subject) } ?? false
    case "nin": return (rule.value as? [Any]).map { list in !list.contains { jsEquals($0, subject) } } ?? false
    case "gt": if let a = jsNumber(subject), let b = jsNumber(rule.value) { return a > b }; return false
    case "lt": if let a = jsNumber(subject), let b = jsNumber(rule.value) { return a < b }; return false
    case "contains": return jsString(subject).contains(jsString(rule.value))
    case "exists": return !missing && jv(subject) != .null
    default: return false
    }
}

package func checkTargeting(_ exp: Experience, _ user: GateUser?, _ context: JSONObject, screen: String) -> Bool {
    guard let t = exp.targeting else { return true }
    if !t.traitEquals.isEmpty {
        guard let user else { return false }
        for (k, v) in t.traitEquals where !jsEquals(user.traits[k], v) { return false }
    }
    return t.rules.allSatisfy { evalRule($0, user, context, screen) }
}

package func checkEligibility(_ exp: Experience, _ profile: ProfileData, now: Int64) -> Bool {
    guard let e = exp.eligibility else { return true }
    if let d = e.minDaysSinceFirstSeen, Double(now - profile.firstSeenAt) / Double(DAY_MS) < d { return false }
    if let s = e.minSessions, profile.sessionCount < s { return false }
    if let s = e.startAt { guard let at = parseIsoMillis(s), now >= at else { return false } }
    if let s = e.endAt { guard let at = parseIsoMillis(s), now <= at else { return false } }
    return true
}

/// ISO-8601 to epoch ms, or nil when malformed (a malformed window fails closed, as on web).
package func parseIsoMillis(_ s: String) -> Int64? {
    let text = s.trimmingCharacters(in: .whitespaces)
    let iso = ISO8601DateFormatter()
    for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
        iso.formatOptions = opts
        if let d = iso.date(from: text) { return Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    }
    // Date-only strings are UTC in JavaScript; date-times without an offset are local time.
    for (pattern, utc) in [("yyyy-MM-dd", true), ("yyyy-MM-dd'T'HH:mm:ss.SSS", false), ("yyyy-MM-dd'T'HH:mm:ss", false), ("yyyy-MM-dd'T'HH:mm", false)] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.isLenient = false
        f.dateFormat = pattern
        f.timeZone = utc ? TimeZone(identifier: "UTC") : TimeZone.current
        if let d = f.date(from: text) { return Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    }
    return nil
}

/// The identity a shown/outcome record is scoped to (uid + the traits and context this form cares about).
package func identityKey(_ exp: Experience, uid: String, traits: JSONObject, context: JSONObject) -> String {
    var traitKeys = Set<String>()
    exp.targeting?.traitEquals.keys.forEach { traitKeys.insert($0) }
    exp.targeting?.rules.forEach { if $0.kind == "trait", let k = $0.key { traitKeys.insert(k) } }
    for t in exp.triggers { if case .user(let te) = t { te.keys.forEach { traitKeys.insert($0) } } }

    var key = uid
    if !traitKeys.isEmpty {
        key += "|" + traitKeys.sorted().map { k in "\(k)=\(traits[k].flatMap { jv($0) == .null ? nil : jsString($0) } ?? "")" }.joined(separator: "|")
    }
    if exp.frequencyScope == "form_context" {
        let ruleKeys = Set(exp.targeting?.rules.filter { $0.kind == "context" }.compactMap(\.key) ?? [])
        let keys = (ruleKeys.isEmpty ? Set(context.keys) : ruleKeys).sorted().filter { context[$0] != nil }
        let body = keys.map { k in "\(jsonQuote(k)):\(literal(context[k]))" }.joined(separator: ",")
        key += "|ctx={\(body)}"
    }
    return key
}

private func literal(_ v: Any?) -> String {
    switch jv(v) {
    case .str(let s): return jsonQuote(s)
    case .null: return "null"
    default: return jsString(v)
    }
}
