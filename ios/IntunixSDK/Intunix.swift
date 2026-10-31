#if os(iOS)
import Foundation
import UIKit

/// Options for ``Intunix/initialize(apiKey:options:)``. Names follow the web SDK.
public struct IntunixOptions {
    /// API origin. Leave as is unless Intunix gave you another host.
    public var apiHost: String
    /// Forms (ids or slugs) whose triggers should be live. Forms flagged auto-activate are live anyway.
    public var register: [String]
    /// Load the whole SDK-enabled catalog instead of only `register`.
    public var registerAll: Bool
    /// How often buffered events upload, in milliseconds.
    public var flushIntervalMs: UInt64
    public var maxQueueSize: Int
    /// Wait before a screen-triggered form shows, in milliseconds.
    public var screenTriggerDelayMs: UInt64
    /// Keep tracked events on the device (they still fire event triggers).
    public var disableEventApi: Bool
    /// Print SDK logs to the console.
    public var debug: Bool

    public init(apiHost: String = "https://api.intunix.com", register: [String] = [], registerAll: Bool = false,
                flushIntervalMs: UInt64 = 5000, maxQueueSize: Int = 100, screenTriggerDelayMs: UInt64 = 600,
                disableEventApi: Bool = false, debug: Bool = false) {
        self.apiHost = apiHost; self.register = register; self.registerAll = registerAll; self.flushIntervalMs = flushIntervalMs
        self.maxQueueSize = maxQueueSize; self.screenTriggerDelayMs = screenTriggerDelayMs
        self.disableEventApi = disableEventApi; self.debug = debug
    }
}

/// Intunix feedback forms for iOS. Call ``initialize(apiKey:options:)`` once at launch.
/// Every call is safe from any thread.
public enum Intunix {
    public static let version = "1.5.6"

    @MainActor static var client: IntunixClient?
    @MainActor private static var presenter: OverlayPresenter?
    /// Calls made before initialize, replayed in order once the client exists (web queues these too).
    @MainActor private static var early: [@MainActor (IntunixClient) -> Void] = []
    @MainActor private static var clientWaiters: [CheckedContinuation<IntunixClient?, Never>] = []

    /// The client, waiting for ``initialize(apiKey:options:)`` if it has not run yet.
    @MainActor static func readyClient() async -> IntunixClient? {
        if let client { return client }
        return await withCheckedContinuation { clientWaiters.append($0) }
    }

    public static func initialize(apiKey: String, options: IntunixOptions = IntunixOptions()) {
        main {
            guard client == nil else { return }
            let p = OverlayPresenter()
            presenter = p
            let cfg = ClientConfig(apiKey: apiKey, apiHost: options.apiHost.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                                   registerAll: options.registerAll, register: options.register,
                                   flushIntervalMs: options.flushIntervalMs, maxQueueSize: options.maxQueueSize,
                                   screenTriggerDelayMs: options.screenTriggerDelayMs, disableEventApi: options.disableEventApi,
                                   sdkVersion: version)
            let debug = options.debug
            let c = IntunixClient(cfg: cfg, store: DefaultsStore(), presenter: p) { if debug { print("[Intunix] \($0)") } }
            client = c
            let nc = NotificationCenter.default
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { client?.onForeground() }
            }
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // Ask iOS for time to upload before it suspends the app.
                    let app = UIApplication.shared
                    var task = UIBackgroundTaskIdentifier.invalid
                    task = app.beginBackgroundTask { app.endBackgroundTask(task) }
                    Task { @MainActor in
                        await client?.onBackground()
                        app.endBackgroundTask(task)
                    }
                }
            }
            c.start()
            early.forEach { $0(c) }
            early.removeAll()
            clientWaiters.forEach { $0.resume(returning: c) }
            clientWaiters.removeAll()
        }
    }

    /// Identify the signed-in user. Call on every login.
    public static func identify(_ userId: String, traits: [String: Any] = [:]) { withClient { $0.identify(userId, traits) } }

    /// Call on logout: forgets the user, rotates the anonymous id and ends the session.
    public static func reset() { withClient { $0.reset() } }

    public static func track(_ event: String, properties: [String: Any] = [:]) { withClient { $0.track(event, properties) } }

    /// Tell Intunix which screen is showing. Drives "App screen" triggers and screen targeting.
    public static func screen(_ name: String) { withClient { $0.screen(name) } }

    /// Merge values into the session context sent with responses; nil clears it.
    public static func setContext(_ context: [String: Any]?) { withClient { $0.setContext(context) } }

    public static func clearContext() { withClient { $0.setContext(nil) } }

    /// Show a form now (still subject to its cadence and targeting). Accepts the form id or slug.
    public static func showForm(_ idOrSlug: String, context: [String: Any]? = nil) { withClient { $0.showForm(idOrSlug, context: context) } }

    /// Make a form's triggers live.
    public static func register(_ idOrSlug: String) { withClient { $0.register(idOrSlug) } }

    public static func unregister(_ idOrSlug: String) { withClient { $0.unregister(idOrSlug) } }

    private static func withClient(_ block: @escaping @MainActor (IntunixClient) -> Void) {
        main {
            if let c = client { block(c) } else if early.count < 100 { early.append(block) }
        }
    }

    private static func main(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(block) }
        else { DispatchQueue.main.async { MainActor.assumeIsolated(block) } }
    }
}

#endif
