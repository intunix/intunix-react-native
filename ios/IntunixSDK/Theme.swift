#if os(iOS)
import SwiftUI

/// Colours and sizes from FEEDBACK_CSS in @intunix/core (the Crisp style).
enum Crisp {
    static let text = Color(hex: 0x18181B)
    static let muted = Color(hex: 0x71717A)
    static let border = Color(hex: 0xE4E4E7)
    static let scaleText = Color(hex: 0x3F3F46)
    static let track = Color(hex: 0xECECEE)
    static let markBorder = Color(hex: 0xD4D4D8)
    static let neutral = Color(hex: 0xA1A1AA)
    static let error = Color(hex: 0xDC2626)
    static let card = Color.white
    static let backdrop = Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255).opacity(0.5)
    /// Form width at which layouts switch to their wide form (the web container query).
    static let wideAt: CGFloat = 440
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
    init(_ hex: String?) {
        let c = rgb(hex) ?? (47 / 255, 148 / 255, 97 / 255)
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
