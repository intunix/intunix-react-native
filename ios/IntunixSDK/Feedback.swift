import Foundation

package struct Brand {
    package var color: String
    package var logoUrl: String?
    /// Console lock: "light", "dark", or nil (follow the app).
    package var darkMode: String? = nil
    /// #rrggbb card colour in dark mode; nil or invalid = default.
    package var darkBackground: String? = nil
}
package struct ChoiceOption { package let value: String, label: String; package let emoji: String? }

package struct FollowUpInput {
    package var type: String
    package var placeholder: String? = nil
    package var maxLength: Int? = nil
    package var options: [ChoiceOption] = []
    package var minPick: Int? = nil
    package var maxPick: Int? = nil
    package init(type: String, placeholder: String? = nil, maxLength: Int? = nil, options: [ChoiceOption] = [], minPick: Int? = nil, maxPick: Int? = nil) {
        self.type = type; self.placeholder = placeholder; self.maxLength = maxLength; self.options = options; self.minPick = minPick; self.maxPick = maxPick
    }
}

package struct ShowIf { package let stepId: String, op: String; package let value: Any?; package let values: [Any] }

/// One question. Kind-specific fields are nil when they don't apply.
package struct Step {
    package var id: String, kind: String, title: String
    package var subtitle: String? = nil
    package var required: Bool? = nil
    package var showIf: ShowIf? = nil
    package var page: Int? = nil
    package var max: Int? = nil
    package var scale: Int? = nil
    package var low: String? = nil, high: String? = nil
    package var csatLabels: [String]? = nil
    package var faces: [String]? = nil
    package var pmfOptions: [ChoiceOption]? = nil
    package var input: FollowUpInput? = nil
    package var icons: String? = nil
    package init(id: String, kind: String, title: String, required: Bool? = nil, max: Int? = nil, input: FollowUpInput? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.required = required; self.max = max; self.input = input
    }
}

package struct ThanksConfig { package let enabled: Bool?, title: String?, subtitle: String?; package let autoCloseMs: Int64? }

package struct FeedbackContent {
    package var steps: [Step]
    package var brand: Brand
    package var thanks: ThanksConfig? = nil
    package var submitLabel: String? = nil, nextLabel: String? = nil, backLabel: String? = nil
    package var closable = true
}

package enum Defaults {
    package static let nps = ("Not likely", "Extremely likely")
    package static let enps = ("Unlikely", "Very likely")
    package static let ces = ("Very hard", "Very easy")
    package static let csatLabels = ["Very dissatisfied", "Dissatisfied", "Neutral", "Satisfied", "Very satisfied"]
    package static let csatEmoji = ["😞", "🙁", "😐", "🙂", "😄"]
    package static let smileys = ["😠", "🙁", "😐", "🙂", "😄"]
    package static let pmf = [ChoiceOption(value: "very", label: "Very disappointed", emoji: "😢"),
                              ChoiceOption(value: "somewhat", label: "Somewhat disappointed", emoji: "😕"),
                              ChoiceOption(value: "not", label: "Not disappointed", emoji: "🤷")]
    package static let starMax = 5
    package static let cesScale = 7
    package static let thanksTitle = "Thanks for the feedback!"
    package static let thanksSubtitle = "We read every response — really."
    package static let thanksAutoCloseMs: Int64 = 2500
    package static let submit = "Submit", next = "Next", back = "Back"
}

private let kinds: Set<String> = ["nps", "enps", "star", "csat", "ces", "smileys", "thumbs", "pmf", "followup"]

private func parseOptions(_ a: [JSONObject]?) -> [ChoiceOption]? {
    a?.compactMap { o in o.str("value").map { ChoiceOption(value: $0, label: o.str("label") ?? $0, emoji: o.str("emoji")) } }
}

package func parseStep(_ o: JSONObject) -> Step? {
    guard let id = o.str("id"), let kind = o.str("kind"), kinds.contains(kind) else { return nil }
    let input = o.obj("input").flatMap { i -> FollowUpInput? in
        guard let type = i.str("type") else { return nil }
        return FollowUpInput(type: type, placeholder: i.str("placeholder"), maxLength: i.int("maxLength"),
                             options: parseOptions(i.objects("options")) ?? [], minPick: i.int("minPick"), maxPick: i.int("maxPick"))
    }
    if kind == "followup" && input == nil { return nil }
    var s = Step(id: id, kind: kind, title: o.str("title") ?? "")
    s.subtitle = o.str("subtitle")
    s.required = o.bool("required")
    s.showIf = o.obj("showIf").flatMap { r in
        guard let sid = r.str("stepId"), let op = r.str("op") else { return nil }
        let v = r["value"]
        return ShowIf(stepId: sid, op: op, value: v is NSNull ? nil : v, values: r.arr("values") ?? [])
    }
    s.page = o.int("page"); s.max = o.int("max"); s.scale = o.int("scale")
    if let l = o.obj("labels") { s.low = l.str("low"); s.high = l.str("high") }
    if let l = o.strings("labels"), l.count == 5 { s.csatLabels = l }
    s.faces = o.strings("faces")
    s.pmfOptions = o.arr("options") != nil ? parseOptions(o.objects("options")) : nil
    s.input = input
    s.icons = o.str("icons")
    return s
}

package func parseFeedbackContent(_ o: JSONObject) -> FeedbackContent? {
    guard o.str("kind") == "feedback" else { return nil }
    let b = o.obj("brand")
    var c = FeedbackContent(steps: o.objects("steps").compactMap(parseStep), brand: Brand(color: b?.str("color") ?? "#2F9461", logoUrl: b?.str("logoUrl"),
                                                                                           darkMode: b?.obj("dark")?.str("mode"), darkBackground: b?.obj("dark")?.str("background")))
    c.thanks = o.obj("thanks").map { ThanksConfig(enabled: $0.bool("enabled"), title: $0.str("title"), subtitle: $0.str("subtitle"), autoCloseMs: $0.int64("autoCloseMs")) }
    c.submitLabel = o.str("submitLabel"); c.nextLabel = o.str("nextLabel"); c.backLabel = o.str("backLabel")
    c.closable = o.bool("closable") != false
    return c
}

package enum AnswerValue: Equatable {
    /// nps, enps, star, csat, ces, smileys.
    case num(Int)
    /// thumbs ('up' / 'down') and pmf.
    case choice(String)
    /// followup free / email / name.
    case text(type: String, text: String)
    case one(String)
    case many([String])

    /// The wire shape @intunix/core sends.
    package var wire: Any {
        switch self {
        case .num(let v): return v
        case .choice(let v): return v
        case .text(let t, let s): return ["type": t, "text": s]
        case .one(let s): return ["type": "selectOne", "selected": s]
        case .many(let s): return ["type": "selectMultiple", "selected": s]
        }
    }
}

package struct Answer: Equatable {
    package let stepId: String, kind: String
    package let value: AnswerValue
    package init(_ stepId: String, _ kind: String, _ value: AnswerValue) { self.stepId = stepId; self.kind = kind; self.value = value }
    package var wire: JSONObject { ["stepId": stepId, "kind": kind, "value": value.wire] }
}

package struct FeedbackResponse { package let answers: [Answer]; package let completed: Bool; package let durationMs: Int64 }
