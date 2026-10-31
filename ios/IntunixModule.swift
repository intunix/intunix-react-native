import Foundation
import React

/// Bridges `NativeModules.Intunix` to the native Intunix iOS SDK.
@objc(Intunix)
final class IntunixModule: NSObject {
    @objc static func requiresMainQueueSetup() -> Bool { false }

    @objc func initialize(_ apiKey: String, options o: NSDictionary) {
        Intunix.initialize(apiKey: apiKey, options: IntunixOptions(
            apiHost: o["apiHost"] as? String ?? "https://api.intunix.com",
            register: o["register"] as? [String] ?? [],
            registerAll: o["registerAll"] as? Bool ?? false,
            flushIntervalMs: UInt64((o["flushIntervalMs"] as? NSNumber)?.intValue ?? 5000),
            maxQueueSize: (o["maxQueueSize"] as? NSNumber)?.intValue ?? 100,
            screenTriggerDelayMs: UInt64((o["screenTriggerDelayMs"] as? NSNumber)?.intValue ?? 600),
            disableEventApi: o["disableEventApi"] as? Bool ?? false,
            debug: o["debug"] as? Bool ?? false))
    }

    @objc func identify(_ userId: String, traits: NSDictionary) { Intunix.identify(userId, traits: traits as? [String: Any] ?? [:]) }
    @objc func reset() { Intunix.reset() }
    @objc func track(_ event: String, properties: NSDictionary) { Intunix.track(event, properties: properties as? [String: Any] ?? [:]) }
    @objc func screen(_ name: String) { Intunix.screen(name) }
    @objc func setContext(_ context: NSDictionary?) { Intunix.setContext(context as? [String: Any]) }
    @objc func showForm(_ form: String, context: NSDictionary?) { Intunix.showForm(form, context: context as? [String: Any]) }
    @objc func register(_ form: String) { Intunix.register(form) }
    @objc func unregister(_ form: String) { Intunix.unregister(form) }
}

/// The inline form as a React Native view; reports height and completion as events.
final class IntunixFormContainer: UIView {
    @objc var onHeightChange: RCTDirectEventBlock?
    @objc var onFinished: RCTDirectEventBlock?
    @objc var form: NSString? { didSet { reload() } }
    @objc var formContext: NSDictionary? { didSet { reload() } }
    private let inner = IntunixFormUIView()
    private var loaded: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.leadingAnchor.constraint(equalTo: leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        inner.onHeightChanged = { [weak self] h in self?.onHeightChange?(["height": h]) }
        inner.onFinished = { [weak self] in self?.onFinished?([:]) }
    }

    required init?(coder: NSCoder) { nil }

    private func reload() {
        guard let f = form as String?, !f.isEmpty, f != loaded else { return }
        loaded = f
        inner.setForm(f, context: formContext as? [String: Any])
    }
}

@objc(IntunixFormViewManager)
final class IntunixFormViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { IntunixFormContainer() }
}
