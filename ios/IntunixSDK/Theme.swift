#if os(iOS)
import SwiftUI

/// Colours and sizes from FEEDBACK_CSS in @intunix/core (the Crisp style). Each colour
/// resolves light or dark from the colour scheme ``FormTheme`` sets on the form.
enum Crisp {
    static let text = themed(\.text)
    static let muted = themed(\.muted)
    static let border = themed(\.border)
    static let scaleText = themed(\.scaleText)
    static let track = themed(\.track)
    static let markBorder = themed(\.markBorder)
    static let neutral = themed(\.neutral)
    static let error = themed(\.error)
    static let card = themed(\.card)
    static let surface = themed(\.surface)
    static let posFg = themed(\.posFg)
    static let negFg = themed(\.negFg)
    static let posBg = themed(\.posBg)
    static let negBg = themed(\.negBg)
    static let backdrop = Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255).opacity(0.5)
    /// Form width at which layouts switch to their wide form (the web container query).
    static let wideAt: CGFloat = 440
}

/// Developer preference (``Intunix/setTheme(_:)``) and the dark palette being drawn.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var preference: IntunixTheme = .auto
    /// Dark palette from the author's background. Forms showing at once share it.
    // shortcut: one dark background app-wide at a time; two inline forms with different dark backgrounds on one screen would share the last one.
    static var dark = darkPalette(nil)
}

private func themed(_ k: KeyPath<Palette, RGB>) -> Color {
    Color(UIColor { tc in
        let c = (tc.userInterfaceStyle == .dark ? ThemeStore.dark : Palette.light)[keyPath: k]
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    })
}

private func themed(_ k: KeyPath<Palette, (RGB, Double)>) -> Color {
    Color(UIColor { tc in
        let (c, a) = (tc.userInterfaceStyle == .dark ? ThemeStore.dark : Palette.light)[keyPath: k]
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: a)
    })
}

private struct FormDarkKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Whether the enclosing form resolved to dark (``FormTheme``).
    var formDark: Bool { get { self[FormDarkKey.self] } set { self[FormDarkKey.self] = newValue } }
}

/// Resolves light/dark for a form (developer → console lock → the screen it sits on) and
/// sets the colour scheme the Crisp colours read.
struct FormTheme: ViewModifier {
    let brand: Brand
    var explicit: IntunixTheme? = nil
    @Environment(\.colorScheme) private var hostScheme
    @ObservedObject private var store = ThemeStore.shared

    func body(content: Content) -> some View {
        let dark = resolveDark(explicit ?? store.preference, lock: brand.darkMode, hostDark: hostScheme == .dark)
        if dark { ThemeStore.dark = darkPalette(brand.darkBackground) }
        return content
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.formDark, dark)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static func parse(_ hex: String?) -> Color? { rgb(hex).map { Color(red: $0.0, green: $0.1, blue: $0.2) } }
}

private func rgb(_ hex: String?) -> (Double, Double, Double)? {
    guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
    return (Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
}

struct BrandColors {
    let color: Color, soft: Color, ring: Color, onColor: Color
    /// In dark mode a brand too dark for the card is lightened (see ``accent(_:on:)``).
    init(_ hex: String?, dark: Bool = false) {
        var c = rgb(hex) ?? (47 / 255, 148 / 255, 97 / 255)
        if dark {
            let a = accent(RGB(c.0, c.1, c.2), on: ThemeStore.dark.card)
            c = (a.r, a.g, a.b)
        }
        func ch(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let lum = 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
        color = Color(red: c.0, green: c.1, blue: c.2)
        soft = color.opacity(0.1)
        ring = color.opacity(0.3)
        onColor = (1.05 / (lum + 0.05)) >= 4.5 ? .white : Color(hex: 0x111111)
    }
}

private struct BrandKey: EnvironmentKey { static let defaultValue = BrandColors(nil) }
private struct WidthKey: EnvironmentKey { static let defaultValue: CGFloat = 360 }

extension EnvironmentValues {
    var brand: BrandColors { get { self[BrandKey.self] } set { self[BrandKey.self] = newValue } }
    /// Width of the form's content area; layouts follow it, not the screen.
    var formWidth: CGFloat { get { self[WidthKey.self] } set { self[WidthKey.self] = newValue } }
}

extension View {
    func crispFont(_ size: CGFloat, _ weight: Font.Weight = .regular, _ color: Color = Crisp.text) -> some View {
        font(.system(size: size, weight: weight)).foregroundColor(color)
    }

    /// CSS `box-shadow: 0 0 0 <width> <color>` around a rounded box.
    func ring(_ show: Bool, _ color: Color, width: CGFloat = 4, radius: CGFloat = 14, gap: CGFloat = 0) -> some View {
        background(RoundedRectangle(cornerRadius: radius + width + gap).fill(show ? color : .clear).padding(-(width + gap)))
    }

    func circleRing(_ show: Bool, _ color: Color, width: CGFloat, gap: CGFloat = 0) -> some View {
        background(Circle().fill(show ? color : .clear).padding(-(width + gap)))
    }

    func box(_ selected: Bool, _ accent: Color, radius: CGFloat = 14, fill: Color = Crisp.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? accent : Crisp.border, lineWidth: 1.5))
    }

    /// The pop when an icon becomes the chosen one: from → peak → rest over ~320ms.
    func pop(_ selected: Bool, rest: CGFloat = 1, from: CGFloat = 1, peak: CGFloat = 1.25) -> some View {
        modifier(Pop(selected: selected, rest: rest, from: from, peak: peak))
    }
}

/// Answer controls: a short press-in on touch (scale .94), no highlight.
struct TapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct Pop: ViewModifier {
    let selected: Bool, rest: CGFloat, from: CGFloat, peak: CGFloat
    @State private var scale: CGFloat? = nil
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale ?? (selected ? rest : 1))
            .onChange(of: selected) { on in
                generation += 1
                guard on else { withAnimation(.easeOut(duration: 0.12)) { scale = 1 }; return }
                let g = generation
                scale = from
                withAnimation(.easeOut(duration: 0.15)) { scale = peak }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // Deselected (or reselected) meanwhile: that change owns the scale now.
                    guard g == generation else { return }
                    withAnimation(.easeInOut(duration: 0.17)) { scale = rest }
                }
            }
    }
}
#endif
