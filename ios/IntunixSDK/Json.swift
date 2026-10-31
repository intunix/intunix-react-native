import Foundation

package typealias JSONObject = [String: Any]

/// A JSON value as JavaScript sees it, so comparisons match the web SDK.
package enum JV: Equatable {
    case null, bool(Bool), num(Double), str(String), other
}

package func jv(_ value: Any?) -> JV {
    guard let v = value else { return .null }
    if v is NSNull { return .null }
    if let s = v as? String { return .str(s) }
    #if canImport(ObjectiveC)
    if let n = v as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .num(n.doubleValue)
    }
    #else
    // swift-corelibs: Swift Bool, or __NSCFBoolean from JSONSerialization.
    if type(of: v) == Bool.self || String(describing: type(of: v)) == "__NSCFBoolean", let b = v as? Bool { return .bool(b) }
    if let i = v as? Int { return .num(Double(i)) }
    if let d = v as? Double { return .num(d) }
    if let n = v as? NSNumber { return .num(n.doubleValue) }
    #endif
    return .other
}

/// `===` over JSON values: numbers compare by value whatever their Swift type.
package func jsEquals(_ a: Any?, _ b: Any?) -> Bool {
    let x = jv(a), y = jv(b)
    if x == .other || y == .other { return false }
    return x == y
}

/// `String(x)` as JavaScript prints it (1.0 prints as "1").
package func jsString(_ v: Any?) -> String {
    switch jv(v) {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .num(let d): return d.truncatingRemainder(dividingBy: 1) == 0 && abs(d) < 1e15 ? String(Int64(d)) : String(d)
    case .str(let s): return s
    case .other: return jsonSafe(v!) is String ? "\(v!)" : jsonString(v!)
    }
}

package func jsNumber(_ v: Any?) -> Double? {
    if case .num(let d) = jv(v) { return d }
    return nil
}

package func parseJSON(_ data: Data?) -> Any? {
    guard let data, !data.isEmpty else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

package func parseJSON(_ text: String?) -> Any? { parseJSON(text?.data(using: .utf8)) }

/// A value JSONSerialization accepts, matching what JSON.stringify writes on web:
/// non-finite numbers become null, dates become ISO strings, anything else becomes its description.
package func jsonSafe(_ value: Any?) -> Any {
    guard let v = value else { return NSNull() }
    if v is NSNull || v is String { return v }
    switch jv(v) {
    case .bool(let b): return b
    case .num(let d): return d.isFinite ? v : NSNull()
    case .null: return NSNull()
    default: break
    }
    if let d = v as? [String: Any] { return d.mapValues { jsonSafe($0) } }
    if let a = v as? [Any] { return a.map { jsonSafe($0) } }
    if let date = v as? Date { return ISO8601DateFormatter().string(from: date) }
    if let url = v as? URL { return url.absoluteString }
    return "\(v)"
}

package func jsonString(_ value: Any) -> String {
    let safe = jsonSafe(value)
    guard JSONSerialization.isValidJSONObject(safe),
          let d = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: d, as: UTF8.self)
}

/// A JSON string literal, quoted and escaped.
package func jsonQuote(_ s: String) -> String {
    let d = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data("[\"\"]".utf8)
    let arr = String(decoding: d, as: UTF8.self)
    return String(arr.dropFirst().dropLast())
}

package extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? { self[k] as? String }
    func double(_ k: String) -> Double? { jsNumber(self[k]) }
    func int(_ k: String) -> Int? { double(k).map { Int($0) } }
    func int64(_ k: String) -> Int64? { double(k).map { Int64($0) } }
    func bool(_ k: String) -> Bool? { if case .bool(let b) = jv(self[k]) { return b }; return nil }
    func obj(_ k: String) -> JSONObject? { self[k] as? JSONObject }
    func arr(_ k: String) -> [Any]? { self[k] as? [Any] }
    func objects(_ k: String) -> [JSONObject] { arr(k)?.compactMap { $0 as? JSONObject } ?? [] }
    func strings(_ k: String) -> [String]? { arr(k)?.compactMap { $0 as? String } }
    func has(_ k: String) -> Bool { self[k] != nil }
}
