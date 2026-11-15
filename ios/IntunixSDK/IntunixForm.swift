#if os(iOS)
import SwiftUI

@MainActor
final class InlineFormModel: ObservableObject {
    @Published var host: FormHost?
    @Published var done = false
}

/// A form placed in your own layout (the web SDK's inline form). Shows nothing until the
/// form loads, and nothing again once the visitor is done.
public struct IntunixForm: View {
    private let form: String
    private let context: [String: Any]?
    private let onFinished: (() -> Void)?
    private let onHeightChange: ((CGFloat) -> Void)?
    private let theme: IntunixTheme?
    private let locale: String?
    // Lives as long as this view's identity, so re-appearing (navigation, tabs) keeps answers.
    @StateObject private var model = InlineFormModel()

    /// - Parameters:
    ///   - form: form id or slug
    ///   - context: values sent with the response, on top of ``Intunix/setContext(_:)``
    ///   - onFinished: called once the visitor submits or closes the form
    ///   - onHeightChange: the form's height whenever it changes (0 once done), for hosts that size it
    ///   - theme: light/dark for this form; nil = ``Intunix/setTheme(_:)``, the console lock, then the app
    ///   - locale: language code for this form (`"bn"`, `"pt-BR"`); nil = ``Intunix/setLocale(_:)``, the respondent's choice, then the device
    public init(form: String, context: [String: Any]? = nil, theme: IntunixTheme? = nil, locale: String? = nil, onFinished: (() -> Void)? = nil,
                onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.form = form; self.context = context; self.theme = theme; self.locale = locale; self.onFinished = onFinished; self.onHeightChange = onHeightChange
    }

    /// The 1.6.x initializer, kept so existing call sites and binaries keep working.
    @_disfavoredOverload
    public init(form: String, context: [String: Any]? = nil, theme: IntunixTheme? = nil, onFinished: (() -> Void)? = nil,
                onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.init(form: form, context: context, theme: theme, locale: nil, onFinished: onFinished, onHeightChange: onHeightChange)
    }

    public var body: some View {
        // The ZStack always exists, so its task runs even while nothing is drawn yet.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if let host = model.host, !model.done {
                Group { if host.chat != nil { ChatForm(host: host) } else { FeedbackFormView(host: host) } }
                    .modifier(FormTheme(brand: host.content.brand, explicit: theme))
            }
        }
        .background(GeometryReader { g in Color.clear.preference(key: FormHeightPref.self, value: g.size.height) })
        .onPreferenceChange(FormHeightPref.self) { h in onHeightChange?(h) }
        .task(id: form) { await load() }
    }

    @MainActor private func load() async {
        guard model.host == nil, !model.done else { return }
        guard let client = await Intunix.readyClient(), let exp = await client.resolve(form),
              parseFeedbackContent(exp.content) != nil else { return }
        let ctx = client.contextFor(context)
        let responseId = newId()
        let finished = onFinished
        let model = self.model
        model.host = FormHost(exp: exp, callbacks: client.callbacks(exp, ctx, responseId, formLocale: locale),
                              openUrl: OverlayPresenter.openUrl) { result in
            client.settle(exp, ctx, result, responseId)
            model.done = true
            finished?()
        }
    }
}
private struct FormHeightPref: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// ``IntunixForm`` as a UIKit view, for UIKit screens and the React Native / Flutter wrappers.
public final class IntunixFormUIView: UIView {
    /// Called once the visitor submits or closes the form.
    public var onFinished: (() -> Void)?
    /// The form's height in points whenever it changes (0 once done).
    public var onHeightChanged: ((CGFloat) -> Void)?
    private var hosting: UIHostingController<IntunixForm>?
    private var current: (form: String, context: [String: Any]?)?

    /// Language code for this form; nil = ``Intunix/setLocale(_:)``, the respondent's choice, then the device.
    public var locale: String? {
        didSet { if let c = current, let h = hosting { h.rootView = makeView(c.form, c.context) } }
    }

    /// Light/dark for this form; nil = ``Intunix/setTheme(_:)``, the console lock, then the app.
    public var theme: IntunixTheme? {
        didSet { if let c = current, let h = hosting { h.rootView = makeView(c.form, c.context) } }
    }

    private func makeView(_ form: String, _ context: [String: Any]?) -> IntunixForm {
        IntunixForm(form: form, context: context, theme: theme, locale: locale,
                    onFinished: { [weak self] in self?.onFinished?() },
                    onHeightChange: { [weak self] h in self?.onHeightChanged?(h) })
    }

    /// Show a form (id or slug). Calling again with another form replaces it.
    public func setForm(_ form: String, context: [String: Any]? = nil) {
        hosting?.view.removeFromSuperview()
        current = (form, context)
        let h = UIHostingController(rootView: makeView(form, context))
        h.view.backgroundColor = .clear
        // Follow the form's natural height as it changes (pages, follow-up questions).
        if #available(iOS 16.0, *) { h.sizingOptions = .intrinsicContentSize }
        h.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h.view)
        NSLayoutConstraint.activate([
            h.view.topAnchor.constraint(equalTo: topAnchor),
            h.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        hosting = h
    }
}
#endif
