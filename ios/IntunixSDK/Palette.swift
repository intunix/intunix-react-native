import Foundation

/// Light or dark forms. `.auto` follows the console lock, else the screen the form sits on.
public enum IntunixTheme: String, Sendable {
    case auto, light, dark
}

package let defaultDarkBackground = "#18181b"

/// An sRGB colour, 0...1 per channel. Platform-free so the palette maths tests on Linux.
package struct RGB: Equatable {
    package var r: Double, g: Double, b: Double
    package init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    package init(_ hex: UInt32) { self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255) }
    package init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let n = UInt32(s, radix: 16) else { return nil }
        self.init(n)
    }
}

/// Neutral colours of one theme. Light values are FEEDBACK_CSS's; dark ones come from ``darkPalette(_:)``.
package struct Palette: Equatable {
    package var text, muted, border, scaleText, track, markBorder, neutral, error, card, surface, posFg, negFg: RGB
    package var posBg, negBg: (RGB, Double)
    package var dark: Bool
    package static func == (a: Palette, b: Palette) -> Bool { a.card == b.card && a.text == b.text && a.dark == b.dark }

    package static let light = Palette(
        text: RGB(0x18181B), muted: RGB(0x71717A), border: RGB(0xE4E4E7), scaleText: RGB(0x3F3F46), track: RGB(0xECECEE),
        markBorder: RGB(0xD4D4D8), neutral: RGB(0xA1A1AA), error: RGB(0xDC2626), card: RGB(1, 1, 1), surface: RGB(0xF4F4F5),
        posFg: RGB(0x15803D), negFg: RGB(0xB91C1C), posBg: (RGB(0xF0FDF4), 1), negBg: (RGB(0xFEF2F2), 1), dark: false)
}

/// Developer light/dark → console lock → what the host shows.
package func resolveDark(_ pref: IntunixTheme, lock: String?, hostDark: Bool) -> Bool {
    switch pref {
    case .light: return false
    case .dark: return true
    case .auto: return lock == "light" ? false : lock == "dark" ? true : hostDark
    }
}

/// Port of darkPalette in @intunix/core: neutrals stepped from the background toward the text colour.
package func darkPalette(_ background: String?) -> Palette {
    let valid = background.flatMap { $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? $0 : nil }
    let bg = RGB(hex: valid) ?? RGB(hex: defaultDarkBackground)!
    let lightBg = !whiteReads(bg)
    let ink = lightBg ? RGB(0, 0, 0) : RGB(1, 1, 1)
    func step(_ t: Double) -> RGB { mix(bg, ink, t) }
    return Palette(
        text: lightBg ? RGB(0x18181B) : RGB(0xFAFAFA), muted: step(0.62), border: step(0.16), scaleText: step(0.82),
        track: step(0.13), markBorder: step(0.28), neutral: step(0.45), error: lightBg ? RGB(0xB91C1C) : RGB(0xF87171),
        card: bg, surface: step(0.07), posFg: lightBg ? RGB(0x15803D) : RGB(0x4ADE80), negFg: lightBg ? RGB(0xB91C1C) : RGB(0xF87171),
        posBg: (RGB(0x16A34A), 0.18), negBg: (RGB(0xDC2626), 0.18), dark: true)
}

/// Brand as-is unless it would vanish on the card (< 3:1); then nudged toward the text colour.
package func accent(_ brand: RGB, on card: RGB) -> RGB {
    if contrast(brand, card) >= 3 { return brand }
    let ink = whiteReads(card) ? RGB(1, 1, 1) : RGB(0, 0, 0)
    var t = 0.1
    while t < 1 { let c = mix(brand, ink, t); if contrast(c, card) >= 3 { return c }; t += 0.1 }
    return ink
}

package func luminance(_ c: RGB) -> Double {
    func ch(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
}

package func contrast(_ a: RGB, _ b: RGB) -> Double {
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

package func whiteReads(_ c: RGB) -> Bool { 1.05 / (luminance(c) + 0.05) >= 4.5 }

private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    func ch(_ x: Double, _ y: Double) -> Double { ((x + (y - x) * t) * 255).rounded() / 255 }
    return RGB(ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b))
}
