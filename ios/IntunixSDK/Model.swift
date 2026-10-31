import Foundation

package enum Trigger {
    case event(name: String, propertyEquals: JSONObject?)
    /// App screens, matched against Intunix.screen(_:).
    case screen(match: String, value: String)
    case user(traitEquals: JSONObject)
    case time(afterMs: Int64)
    case manual
    /// url and exit_intent are web-only; unknown kinds from a newer console land here too.
    case ignored
}

package enum Wait: Equatable {
    case days(Double), session, never
}

package struct Cadence {
    package var mode: String
    package var answered: Wait?
    package var dismissed: Wait?
    package var ignored: Wait?
    package var giveUpAfterShows: Int?
    package init(mode: String, answered: Wait? = nil, dismissed: Wait? = nil, ignored: Wait? = nil, giveUpAfterShows: Int? = nil) {
        self.mode = mode; self.answered = answered; self.dismissed = dismissed; self.ignored = ignored; self.giveUpAfterShows = giveUpAfterShows
    }
}

package struct TargetingRule {
    package let kind: String, key: String?, op: String
    package let value: Any?
    package let hasValue: Bool
}

package struct Targeting {
    package let traitEquals: JSONObject
    package let rules: [TargetingRule]
}

package struct Eligibility {
    package let minDaysSinceFirstSeen: Double?
    package let minSessions: Int?
    package let startAt: String?
    package let endAt: String?
}

package struct ReviewRequestConfig {
    package var enabled: Bool
    package var platform: String
    package var reviewUrl: String?
    package var rule: String?
    package var threshold: Double?
    package var title: String?, description: String?, buttonText: String?, skipText: String?
    package var themeColor: String?, buttonStyle: String?
    package init(enabled: Bool, platform: String, reviewUrl: String?, rule: String?, threshold: Double?,
                 title: String? = nil, description: String? = nil, buttonText: String? = nil, skipText: String? = nil,
                 themeColor: String? = nil, buttonStyle: String? = nil) {
        self.enabled = enabled; self.platform = platform; self.reviewUrl = reviewUrl; self.rule = rule; self.threshold = threshold
        self.title = title; self.description = description; self.buttonText = buttonText; self.skipText = skipText
        self.themeColor = themeColor; self.buttonStyle = buttonStyle
    }
}

package struct Experience {
    package let id: String
    package let slug: String?
    package let name: String?
    package let type: String
    package let platforms: [String]?
    package let content: JSONObject
    package let triggers: [Trigger]
    package let cadence: Cadence?
    package let targeting: Targeting?
    package let eligibility: Eligibility?
    package let frequencyScope: String?
    package let autoActivate: Bool
    package let reviewRequest: ReviewRequestConfig?
}

package func parseWait(_ v: Any?) -> Wait? {
    if let d = jsNumber(v) { return .days(d) }
    switch v as? String { case "session": return .session; case "never": return .never; default: return nil }
}

package func parseTrigger(_ o: JSONObject) -> Trigger {
    switch o.str("kind") {
    case "event": return o.str("eventName").map { .event(name: $0, propertyEquals: o.obj("propertyEquals")) } ?? .ignored
    case "screen": return o.str("value").map { .screen(match: o.str("match") ?? "exact", value: $0) } ?? .ignored
    case "user": return .user(traitEquals: o.obj("traitEquals") ?? [:])
    case "time": return o.int64("afterMs").map { .time(afterMs: $0) } ?? .ignored
    case "manual": return .manual
    default: return .ignored
    }
}

package func parseExperience(_ o: JSONObject) -> Experience? {
    guard let id = o.str("id"), let content = o.obj("content") else { return nil }
    let cadence = o.obj("cadence").map { c -> Cadence in
        let cd = c.obj("cooldown")
        return Cadence(mode: c.str("mode") ?? "every_session",
                       answered: parseWait(cd?["answered"]), dismissed: parseWait(cd?["dismissed"]),
                       ignored: parseWait(cd?["ignored"]), giveUpAfterShows: c.int("giveUpAfterShows"))
    }
    let targeting = o.obj("targeting").map { t in
        Targeting(traitEquals: t.obj("traitEquals") ?? [:], rules: t.objects("rules").compactMap { r in
            guard let kind = r.str("kind"), let op = r.str("op") else { return nil }
            let v = r["value"]
            return TargetingRule(kind: kind, key: r.str("key"), op: op, value: v is NSNull ? nil : v, hasValue: r.has("value"))
        })
    }
    let eligibility = o.obj("eligibility").map {
        Eligibility(minDaysSinceFirstSeen: $0.double("minDaysSinceFirstSeen"), minSessions: $0.int("minSessions"),
                    startAt: $0.str("startAt"), endAt: $0.str("endAt"))
    }
    let review = o.obj("reviewRequest").map { r -> ReviewRequestConfig in
        let t = r.obj("trigger")
        return ReviewRequestConfig(enabled: r.bool("enabled") == true, platform: r.str("platform") ?? "custom",
                                   reviewUrl: r.str("reviewUrl"), rule: t?.str("rule"), threshold: t?.double("threshold"),
                                   title: r.str("title"), description: r.str("description"), buttonText: r.str("buttonText"),
                                   skipText: r.str("skipText"), themeColor: r.str("themeColor"), buttonStyle: r.str("buttonStyle"))
    }
    return Experience(id: id, slug: o.str("slug"), name: o.str("name"), type: o.str("type") ?? "modal",
                      platforms: o.strings("platforms"), content: content,
                      triggers: o.objects("triggers").map(parseTrigger), cadence: cadence, targeting: targeting,
                      eligibility: eligibility, frequencyScope: o.str("frequencyScope"),
                      autoActivate: o.bool("autoActivate") == true, reviewRequest: review)
}
