import Foundation

private let numeric: Set<String> = ["nps", "enps", "star", "csat", "ces", "smileys"]

private func numericValue(_ a: Answer) -> Int? {
    if numeric.contains(a.kind), case .num(let v) = a.value { return v }
    return nil
}

private func scalarValue(_ a: Answer) -> Any? {
    switch a.value {
    case .num(let v): return numeric.contains(a.kind) ? v : nil
    case .choice(let v): return v
    case .text(_, let t): return t
    case .one(let s): return s
    case .many: return nil
    }
}

package func evaluateShowIf(_ rule: ShowIf?, _ answers: [Answer]) -> Bool {
    guard let rule else { return true }
    guard let prior = answers.first(where: { $0.stepId == rule.stepId }) else { return false }
    if rule.op == "any" { return true }
    let scalar = scalarValue(prior)
    switch rule.op {
    case "eq": return jsEquals(scalar, rule.value)
    case "neq": return !jsEquals(scalar, rule.value)
    case "in": return scalar != nil && rule.values.contains { jsEquals($0, scalar) }
    case "lte", "gte", "lt", "gt":
        guard let n = numericValue(prior).map(Double.init), let t = jsNumber(rule.value) else { return false }
        switch rule.op { case "lte": return n <= t; case "gte": return n >= t; case "lt": return n < t; default: return n > t }
    default: return false
    }
}

private let emailPattern = try! NSRegularExpression(pattern: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

package func isEmail(_ s: String) -> Bool {
    emailPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

package func isAnswerValid(_ step: Step, _ answer: Answer?) -> Bool {
    let required = step.kind != "followup" ? step.required != false : step.required == true
    guard let answer else { return !required }
    guard answer.stepId == step.id, answer.kind == step.kind else { return false }
    switch (step.kind, answer.value) {
    case ("nps", .num(let v)), ("enps", .num(let v)): return (0...10).contains(v)
    case ("star", .num(let v)): return v >= 1 && v <= (step.max ?? Defaults.starMax)
    case ("csat", .num(let v)), ("smileys", .num(let v)): return (1...5).contains(v)
    case ("ces", .num(let v)): return v >= 1 && v <= (step.scale ?? Defaults.cesScale)
    case ("thumbs", .choice(let v)): return v == "up" || v == "down"
    case ("pmf", .choice(let v)): return ["very", "somewhat", "not"].contains(v)
    case ("followup", let v): return isFollowUpValid(step, v)
    default: return false
    }
}

private func isFollowUpValid(_ step: Step, _ v: AnswerValue) -> Bool {
    guard let input = step.input else { return false }
    let required = step.required == true
    switch (input.type, v) {
    case ("free", .text(let t, let s)), ("name", .text(let t, let s)):
        guard t == input.type else { return false }
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return !required }
        // UTF-16 length, as JavaScript counts it.
        if input.type == "free", let max = input.maxLength { return text.utf16.count <= max }
        return true
    case ("email", .text(let t, let s)):
        guard t == "email" else { return false }
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? !required : isEmail(text)
    case ("selectOne", .one(let s)):
        return s.isEmpty ? !required : input.options.contains { $0.value == s }
    case ("selectMultiple", .many(let s)):
        let picks = s.filter { p in input.options.contains { $0.value == p } }
        let min = input.minPick ?? (required ? 1 : 0)
        return picks.count >= min && picks.count <= (input.maxPick ?? Int.max)
    default: return false
    }
}

package func isPageValid(_ steps: [Step], _ answers: [Answer]) -> Bool {
    steps.allSatisfy { step in isAnswerValid(step, answers.first { $0.stepId == step.id }) }
}
