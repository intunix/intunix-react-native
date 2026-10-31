import Foundation

private let scoredRules: Set<String> = ["nps", "csat", "ces", "star", "smileys"]

/// The URL only if it is absolute http(s); anything else (javascript:, data:, relative) is nil.
package func safeReviewUrl(_ raw: String?) -> String? {
    let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    // Like the web URL parser, accept spaces and non-ASCII by percent-encoding them.
    let parsed = URLComponents(string: s) ?? s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["#", "%"])).flatMap { URLComponents(string: $0) }
    guard !s.isEmpty, s.count <= 2048, let c = parsed,
          let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = c.host, !host.isEmpty else { return nil }
    return s
}

/// Whether this submission earns a review invitation. Unknown config fails closed.
package func reviewQualifies(_ config: ReviewRequestConfig?, _ answers: [Answer]) -> Bool {
    guard let config, config.enabled, safeReviewUrl(config.reviewUrl) != nil, let rule = config.rule else { return false }
    if rule == "always" { return true }
    guard scoredRules.contains(rule), let threshold = config.threshold, !threshold.isNaN,
          let hit = answers.first(where: { $0.kind == rule }), case .num(let v) = hit.value else { return false }
    return Double(v) >= threshold
}

package struct ReviewEvent {
    package let name: String, formId: String, clientResponseId: String, platform: String, reviewUrl: String, triggerRule: String
    package let triggerThreshold: Double?
}

package final class ReviewPresenter {
    package let title: String, description: String, buttonText: String, skipText: String
    package let themeColor: String?
    package let outline: Bool
    package let reviewUrl: String
    private let config: ReviewRequestConfig
    private let formId: String, clientResponseId: String
    private let emit: (ReviewEvent) -> Void
    private let openUrl: (String) -> Bool
    private let onDone: () -> Void
    private var settled = false

    package static func create(_ config: ReviewRequestConfig?, formId: String, clientResponseId: String, brandColor: String?,
                               emit: @escaping (ReviewEvent) -> Void, openUrl: @escaping (String) -> Bool,
                               onDone: @escaping () -> Void) -> ReviewPresenter? {
        guard let config, config.enabled, let url = safeReviewUrl(config.reviewUrl) else { return nil }
        return ReviewPresenter(config, formId, clientResponseId, url, brandColor, emit, openUrl, onDone)
    }

    private init(_ config: ReviewRequestConfig, _ formId: String, _ rid: String, _ url: String, _ brand: String?,
                 _ emit: @escaping (ReviewEvent) -> Void, _ openUrl: @escaping (String) -> Bool, _ onDone: @escaping () -> Void) {
        self.config = config; self.formId = formId; self.clientResponseId = rid; self.reviewUrl = url
        self.emit = emit; self.openUrl = openUrl; self.onDone = onDone
        title = config.title ?? "🎉 Thank you!"
        description = config.description ?? "We're happy you had a great experience. Would you consider leaving a public review?"
        buttonText = config.buttonText ?? "Leave a Review"
        skipText = config.skipText ?? "Maybe later"
        themeColor = config.themeColor ?? brand
        outline = config.buttonStyle == "outline"
    }

    private func fire(_ name: String) {
        emit(ReviewEvent(name: name, formId: formId, clientResponseId: clientResponseId, platform: config.platform,
                         reviewUrl: reviewUrl, triggerRule: config.rule ?? "always",
                         triggerThreshold: config.rule == "always" ? nil : config.threshold))
    }

    package func onShown() { fire("$review_request_shown") }

    package func onClick() {
        guard !settled else { return }
        settled = true
        fire("$review_request_clicked")
        if openUrl(reviewUrl) { fire("$review_request_redirected") }
        onDone()
    }

    package func onSkip() {
        guard !settled else { return }
        settled = true
        fire("$review_request_skipped")
        onDone()
    }
}
