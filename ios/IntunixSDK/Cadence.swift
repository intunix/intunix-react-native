import Foundation

package let DAY_MS: Int64 = 86_400_000

package struct ShownRecord: Equatable {
    package var lastShownAt: Int64
    package var count: Int
    package var sessionId: String?
    package init(lastShownAt: Int64, count: Int, sessionId: String?) { self.lastShownAt = lastShownAt; self.count = count; self.sessionId = sessionId }
}

package struct OutcomeRecord: Equatable {
    /// Set only when the user answered.
    package var respondedAt: Int64? = nil
    package var showCount: Int = 0
    package var lastOutcome: String? = nil
    package var lastOutcomeAt: Int64? = nil
    package init(respondedAt: Int64? = nil, showCount: Int = 0, lastOutcome: String? = nil, lastOutcomeAt: Int64? = nil) {
        self.respondedAt = respondedAt; self.showCount = showCount; self.lastOutcome = lastOutcome; self.lastOutcomeAt = lastOutcomeAt
    }
}

package struct NormalizedCadence: Equatable {
    package var mode: String
    package var answered: Wait, dismissed: Wait, ignored: Wait
    package var giveUpAfterShows: Int?
    package init(_ mode: String, _ answered: Wait, _ dismissed: Wait, _ ignored: Wait, _ giveUp: Int? = nil) {
        self.mode = mode; self.answered = answered; self.dismissed = dismissed; self.ignored = ignored; self.giveUpAfterShows = giveUp
    }
}

/// Same expansion as @intunix/core: every mode becomes one three-outcome wait map.
package func normalizeCadence(_ c: Cadence?) -> NormalizedCadence {
    let zero = Wait.days(0)
    switch c?.mode ?? "every_session" {
    case "once": return NormalizedCadence("once", .never, .never, .never)
    case "always": return NormalizedCadence("always", zero, zero, zero)
    case "cooldown": return NormalizedCadence("cooldown", c?.answered ?? zero, c?.dismissed ?? zero, c?.ignored ?? zero, c?.giveUpAfterShows)
    default: return NormalizedCadence("every_session", .session, .session, .session, c?.giveUpAfterShows)
    }
}

/// Whether a form may show again. Every wait measures from the last show; the outcome picks the wait.
package func checkCadence(_ cadence: NormalizedCadence, _ shown: ShownRecord?, _ outcome: OutcomeRecord?, now: Int64, sessionId: String) -> Bool {
    guard let shown else { return true }
    if cadence.mode != "always", let giveUp = cadence.giveUpAfterShows, outcome?.respondedAt == nil, shown.count >= giveUp { return false }
    let wait: Wait
    switch outcome?.lastOutcome {
    case "responded": wait = cadence.answered
    case "dismissed": wait = cadence.dismissed
    default: wait = cadence.ignored
    }
    switch wait {
    case .never: return false
    case .session: return shown.sessionId != sessionId
    case .days(let d): return Double(now - shown.lastShownAt) >= d * Double(DAY_MS)
    }
}
