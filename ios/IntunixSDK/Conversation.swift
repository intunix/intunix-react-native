import Foundation

package struct ConversationTranslation {
    package var welcomeMessage: String?, completionMessage: String?
}

package struct ConversationConfig {
    /// "enhanced" | "conversational".
    package var mode: String
    package var assistantName: String?
    package var welcomeMessage: String?
    package var completionMessage: String?
    /// Language code -> messages.
    package var translations: [String: ConversationTranslation]?
    package init(mode: String, assistantName: String? = nil, welcomeMessage: String? = nil, completionMessage: String? = nil,
                 translations: [String: ConversationTranslation]? = nil) {
        self.mode = mode; self.assistantName = assistantName; self.welcomeMessage = welcomeMessage
        self.completionMessage = completionMessage; self.translations = translations
    }
}

package func parseConversationConfig(_ o: JSONObject?) -> ConversationConfig? {
    guard let o, let mode = o.str("mode"), mode == "enhanced" || mode == "conversational" else { return nil }
    let tr = o.obj("translations").map { t in
        t.reduce(into: [String: ConversationTranslation]()) { out, kv in
            if let v = kv.value as? JSONObject { out[kv.key] = ConversationTranslation(welcomeMessage: v.str("welcomeMessage"), completionMessage: v.str("completionMessage")) }
        }
    }
    return ConversationConfig(mode: mode, assistantName: o.str("assistantName"), welcomeMessage: o.str("welcomeMessage"),
                              completionMessage: o.str("completionMessage"), translations: tr)
}

/// The config in `lang`: translated messages fall back per field to the default; `translations` is dropped.
package func localizeConversation(_ config: ConversationConfig, _ lang: String) -> ConversationConfig {
    guard let translations = config.translations else { return config }
    // Sorted so a base-language match picks the same entry on every run.
    let tr = matchLanguage(lang, translations.keys.sorted()).flatMap { translations[$0] }
    var c = config
    c.translations = nil
    c.welcomeMessage = pick(tr?.welcomeMessage, config.welcomeMessage)
    c.completionMessage = pick(tr?.completionMessage, config.completionMessage)
    return c
}

package struct TurnRequest: Equatable {
    package var conversationId: String
    package var turn: Int
    /// "answer" | "skip" | "end" | "resume".
    package var action: String
    package var answer: Answer?
    package var locale: String?
    package init(_ conversationId: String, _ turn: Int, _ action: String, _ answer: Answer? = nil, _ locale: String? = nil) {
        self.conversationId = conversationId; self.turn = turn; self.action = action; self.answer = answer; self.locale = locale
    }
    package var json: JSONObject {
        var o: JSONObject = ["conversation_id": conversationId, "turn": turn, "action": action]
        if let answer { o["answer"] = answer.wire }
        if let locale { o["locale"] = locale }
        return o
    }
}

/// Where a bubble's text came from; only form-owned text re-renders on a language switch.
package enum MessageSource: Equatable {
    case welcome, completion
    case step(String), answer(String)
}

package struct ChatMessage: Equatable {
    /// "nia" | "respondent".
    package let role: String
    package var text: String
    package var source: MessageSource?
    package init(_ role: String, _ text: String, source: MessageSource? = nil) { self.role = role; self.text = text; self.source = source }
}

package struct TurnReply {
    package var messages: [String]
    package var input: Step?
    package var inputJson: JSONObject?
    package var answered: Int, total: Int
    package var done: Bool
    package var nextTurn: Int
    package var busy: Bool
    package var transcript: [ChatMessage]?
    package var answers: [JSONObject]?
    package var skipped: [String]?
}

/// Shape check of a turn reply's `data`, as the web SDK does it.
package func isValidTurnReply(_ v: Any?) -> Bool {
    guard let o = v as? JSONObject, let p = o.obj("progress"), let messages = o.arr("messages"),
          jsNumber(o["next_turn"]) != nil, o.bool("done") != nil, jsNumber(p["answered"]) != nil, jsNumber(p["total"]) != nil else { return false }
    if o.has("answers") && !(o["answers"] is [Any]) { return false }
    if o.has("skipped") && !((o["skipped"] as? [Any])?.allSatisfy { $0 is String } == true) { return false }
    if !messages.allSatisfy({ ($0 as? JSONObject)?.str("text") != nil }) { return false }
    guard let i = o["input"] else { return false }
    if i is NSNull { return true }
    guard let io = i as? JSONObject, io.str("id") != nil, let kind = io.str("kind") else { return false }
    return kind != "followup" || io.obj("input") != nil
}

/// Nil when the reply is invalid or its input is a step this SDK cannot show.
package func parseTurnReply(_ o: JSONObject) -> TurnReply? {
    guard isValidTurnReply(o), let p = o.obj("progress") else { return nil }
    let inputJson = o.obj("input")
    var input: Step?
    if let inputJson { guard let s = parseStep(inputJson) else { return nil }; input = s }
    return TurnReply(
        messages: o.objects("messages").compactMap { $0.str("text") },
        input: input, inputJson: inputJson, answered: p.int("answered") ?? 0, total: p.int("total") ?? 0,
        done: o.bool("done") == true, nextTurn: o.int("next_turn") ?? 0, busy: o.bool("busy") == true,
        transcript: o.arr("transcript").map { $0.compactMap { ($0 as? JSONObject) }.compactMap { m in
            guard let role = m.str("role"), role == "nia" || role == "respondent", let t = m.str("text") else { return nil }
            return ChatMessage(role, t)
        } },
        answers: o.arr("answers").map { $0.compactMap { $0 as? JSONObject } },
        skipped: o.strings("skipped"))
}

/// Resolves with the reply's `data`; throws on anything else.
package typealias ConversationTransport = (TurnRequest) async throws -> JSONObject

package struct MalformedTurnReply: Error {}

/// POST /sdk/forms/{id}/turn, no retry (the controller owns timeouts and fallbacks).
package func sdkTransport(http: Http, formId: String) -> ConversationTransport {
    { req in
        let res = try await http.request("POST", "/sdk/forms/\(enc(formId))/turn", body: req.json)
        guard let data = (parseJSON(res.body) as? JSONObject)?["data"], isValidTurnReply(data), let o = data as? JSONObject else { throw MalformedTurnReply() }
        return o
    }
}

package struct ConversationHandle {
    package var config: ConversationConfig
    package let transport: ConversationTransport
    package let conversationId: String
    package init(config: ConversationConfig, transport: @escaping ConversationTransport, conversationId: String) {
        self.config = config; self.transport = transport; self.conversationId = conversationId
    }
}

/// Wire shape to model; the inverse of `Answer.wire`. Nil when the value does not look like any answer.
package func parseAnswer(_ o: JSONObject) -> Answer? {
    guard let id = o.str("stepId"), let kind = o.str("kind") else { return nil }
    let value: AnswerValue
    switch jv(o["value"]) {
    case .num(let d):
        guard d == d.rounded(), abs(d) < 2_147_483_648 else { return nil }
        value = .num(Int(d))
    case .str(let s): value = .choice(s)
    case .other:
        guard let v = o["value"] as? JSONObject, let type = v.str("type") else { return nil }
        switch type {
        case "free", "email", "name": guard let t = v.str("text") else { return nil }; value = .text(type: type, text: t)
        case "selectOne": guard let s = v.str("selected") else { return nil }; value = .one(s)
        case "selectMultiple":
            guard let a = v.arr("selected"), a.allSatisfy({ $0 is String }) else { return nil }
            value = .many(a.compactMap { $0 as? String })
        default: return nil
        }
    default: return nil
    }
    return Answer(id, kind, value)
}

private func plain(_ v: AnswerValue) -> String {
    switch v {
    case .num(let n): return String(n)
    case .choice(let s), .one(let s): return s
    case .text(_, let t): return t
    case .many(let s): return s.joined(separator: ",")
    }
}

private func at(_ a: [String], _ i: Int) -> String? { a.indices.contains(i) ? a[i] : nil }

/// What the respondent "said", for their chat bubble.
package func answerLabel(_ step: Step, _ a: Answer) -> String {
    let v = a.value
    var label: String?
    switch a.kind {
    case "nps", "enps", "ces": label = plain(v)
    case "star": label = "\(plain(v)) / \(step.kind == "star" ? step.max ?? Defaults.starMax : 5)"
    case "csat": if case .num(let n) = v { label = at(step.csatLabels ?? Defaults.csatLabels, n - 1) }
    case "smileys":
        if case .num(let n) = v { label = at(step.faces.flatMap { $0.isEmpty ? nil : $0 } ?? Defaults.smileys, n - 1) }
    case "thumbs": if case .choice("up") = v { label = "👍" } else { label = "👎" }
    case "pmf":
        if case .choice(let c) = v {
            let opts = step.pmfOptions.flatMap { $0.isEmpty ? nil : $0 } ?? Defaults.pmf
            label = opts.first { $0.value == c }?.label ?? c
        }
    case "followup":
        let opts = step.kind == "followup" ? step.input?.options ?? [] : []
        func name(_ s: String) -> String { opts.first { $0.value == s }?.label ?? s }
        switch v {
        case .text(_, let t): label = t.trimmingCharacters(in: .whitespacesAndNewlines)
        case .one(let s): label = name(s)
        case .many(let s): label = s.map(name).joined(separator: ", ")
        default: break
        }
    default: break
    }
    return label.flatMap { $0.isEmpty ? nil : $0 } ?? plain(v)
}

/// True when choosing a value is the whole answer (no Send button needed).
package func submitsOnTap(_ step: Step) -> Bool { step.kind != "followup" || step.input?.type == "selectOne" }

package struct ChatLabels: Equatable {
    package let name, send, skip, end, typing, log: String
}

// Same rule as the server: only spaces trim and collapse; a newline or tab makes the name invalid.
package func assistantName(_ raw: String?) -> String {
    var n = (raw ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " "))
    while n.contains("  ") { n = n.replacingOccurrences(of: "  ", with: " ") }
    let ok = !n.isEmpty && n.unicodeScalars.count <= 40 && n.unicodeScalars.allSatisfy { s in
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber: return true
        default: return " .'-".unicodeScalars.contains(s)
        }
    }
    return ok ? n : "Nia"
}

/// The chat's visible texts, with `{name}` filled in.
package func chatLabels(_ content: FeedbackContent, _ config: ConversationConfig) -> ChatLabels {
    let name = assistantName(config.assistantName)
    let c = content.chat
    func f(_ s: String?, _ d: String) -> String { (s ?? d).replacingOccurrences(of: "{name}", with: name) }
    return ChatLabels(name: name, send: f(c?.sendLabel, Defaults.chatSend), skip: f(c?.skipLabel, Defaults.chatSkip), end: f(c?.endLabel, Defaults.chatEnd),
                      typing: f(c?.typingLabel, Defaults.chatTyping), log: f(c?.logLabel, Defaults.chatLog))
}
