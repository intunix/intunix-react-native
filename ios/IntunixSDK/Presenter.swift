#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class FrameState: ObservableObject {
    @Published var visible = false
}

/// Shows forms over the app's top view controller, once the app is active.
@MainActor
final class OverlayPresenter: FormPresenter {
    private var active = UIApplication.shared.applicationState == .active
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(true) }
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(false) }
        }
    }

    private func setActive(_ on: Bool) {
        active = on
        guard on else { return }
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func present(_ exp: Experience, _ content: FeedbackContent, _ callbacks: RenderCallbacks) async -> ExperienceResult? {
        if !active { await withCheckedContinuation { waiters.append($0) } }
        guard let top = Self.topViewController() else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<ExperienceResult?, Never>) in
            var resumed = false
            let finish: (ExperienceResult?) -> Void = { r in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: r)
            }
            let frame = FrameState()
            weak var weakVC: FormHostingController?
            let host = FormHost(exp: exp, content: content, callbacks: callbacks, openUrl: Self.openUrl) { result in
                withAnimation(.easeIn(duration: 0.18)) { frame.visible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    weakVC?.onGone = nil
                    weakVC?.dismiss(animated: false)
                    finish(result)
                }
            }
            let vc = FormHostingController(rootView: FormFrame(modal: exp.type == "modal", host: host, frame: frame))
            vc.modalPresentationStyle = .overFullScreen
            vc.view.backgroundColor = .clear
            // The app dismissed us (or its whole stack): treat it as closing the form.
            vc.onGone = { [weak host] in host?.close() }
            weakVC = vc
            top.present(vc, animated: false)
            // UIKit refuses silently when `top` is busy presenting; then nothing was shown.
            DispatchQueue.main.async { if vc.presentingViewController == nil { finish(nil) } }
        }
    }

    static func openUrl(_ s: String) -> Bool {
        guard let url = URL(string: s) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

final class FormHostingController: UIHostingController<FormFrame> {
    var onGone: (() -> Void)?
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onGone?(); onGone = nil }
    }
}

/// Centered dialog for modal forms, bottom sheet for popup and banner, over a dimmed backdrop.
struct FormFrame: View {
    let modal: Bool
    @ObservedObject var host: FormHost
    @ObservedObject var frame: FrameState

    var body: some View {
        ZStack(alignment: modal ? .center : .bottom) {
            (modal ? Crisp.backdrop : Crisp.backdrop.opacity(0.5))
                .ignoresSafeArea()
                .opacity(frame.visible ? 1 : 0)
                .onTapGesture { host.close() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close")
            if frame.visible {
                if modal {
                    card(RoundedRectangle(cornerRadius: 16), pad: 24)
                        .frame(maxWidth: 460)
                        .padding(16)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    card(UnevenTop(), pad: 20)
                        .frame(maxWidth: 720)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .modifier(FormTheme(brand: host.content.brand))
        .onAppear { withAnimation(.easeOut(duration: 0.22)) { frame.visible = true } }
    }

    @State private var contentHeight: CGFloat = 0

    private func card<S: Shape>(_ shape: S, pad: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            FeedbackFormView(host: host)
                .padding(pad)
                .background(GeometryReader { g in Color.clear.preference(key: HeightPref.self, value: g.size.height) })
        }
        .frame(height: min(contentHeight, UIScreen.main.bounds.height * 0.85))
        .onPreferenceChange(HeightPref.self) { contentHeight = $0 }
        .background(shape.fill(Crisp.card).shadow(color: .black.opacity(0.14), radius: 20, y: 8).ignoresSafeArea(edges: modal ? [] : .bottom))
        .clipShape(shape)
    }
}

private struct HeightPref: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Top corners rounded, bottom square (the sheet runs into the home indicator).
private struct UnevenTop: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height + 16), cornerRadius: 16)
    }
}
#endif
