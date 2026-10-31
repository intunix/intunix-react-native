#if os(iOS)
import SwiftUI

/// The same SVG geometry as @intunix/core icons.ts, drawn with SwiftUI so phones match the web.
enum IconSets {
    static let faceSVG: Set<String> = ["mood", "pastel", "line"]
    static let thumbSVG: Set<String> = ["line", "tone", "mark"]
    static let vivid = [0xF87171, 0xFB923C, 0xFACC15, 0xA3E635, 0x4ADE80].map { Color(hex: UInt32($0)) }
    static let pastel = [0xFEE2E2, 0xFFEDD5, 0xFEF9C3, 0xECFCCB, 0xDCFCE7].map { Color(hex: UInt32($0)) }
    static let deep = [0xB91C1C, 0xC2410C, 0xA16207, 0x4D7C0F, 0x15803D].map { Color(hex: UInt32($0)) }
    static let moodInk = Color(hex: 0x3F2A14)
    static let green = Color(hex: 0x16A34A)
    static let red = Color(hex: 0xDC2626)

    private static var cache: [String: Path] = [:]
    static func path(_ d: String) -> Path {
        if let p = cache[d] { return p }
        var p = Path()
        for c in parseSvgPath(d) {
            switch c {
            case .move(let x, let y): p.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y): p.addLine(to: CGPoint(x: x, y: y))
            case .quad(let cx, let cy, let x, let y): p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case .cubic(let ax, let ay, let bx, let by, let x, let y):
                p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
            case .close: p.closeSubpath()
            }
        }
        cache[d] = p
        return p
    }

    static func starColors(_ set: String?, _ tone: String?, brand: Color) -> (Color, Color) {
        switch set {
        case "brand": return (brand, brand)
        case "heart": return (Color(hex: 0xF43F5E), Color(hex: 0xE11D48))
        case "ramp":
            switch tone {
            case "low": return (Color(hex: 0xEF4444), Color(hex: 0xDC2626))
            case "mid": return (Color(hex: 0xF59E0B), Color(hex: 0xD97706))
            default: return (Color(hex: 0x22C55E), Color(hex: 0x16A34A))
            }
        default: return (Color(hex: 0xFBBF24), Color(hex: 0xF59E0B))
        }
    }
}

private func round3(_ w: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }

/// A face for satisfaction level 1–5 in the mood / pastel / line set. `ink` colours the line set.
struct FaceIcon: View {
    let set: String, level: Int, ink: Color
    var body: some View {
        Canvas { ctx, size in
            let i = min(max(level - 1, 0), 4)
            let s = min(size.width, size.height) / 48
            ctx.scaleBy(x: s, y: s)
            let line: Color
            switch set {
            case "mood": line = IconSets.moodInk; ctx.fill(Path(ellipseIn: CGRect(x: 2, y: 2, width: 44, height: 44)), with: .color(IconSets.vivid[i]))
            case "pastel": line = IconSets.deep[i]; ctx.fill(Path(ellipseIn: CGRect(x: 2, y: 2, width: 44, height: 44)), with: .color(IconSets.pastel[i]))
            default: line = ink; ctx.stroke(Path(ellipseIn: CGRect(x: 2.5, y: 2.5, width: 43, height: 43)), with: .color(line), lineWidth: 2.5)
            }
            if i == 0 { ctx.stroke(IconSets.path(IconPaths.brows), with: .color(line), style: round3(3)) }
            if i == 4 { ctx.stroke(IconSets.path(IconPaths.happyEyes), with: .color(line), style: round3(3)) }
            else {
                ctx.fill(Path(ellipseIn: CGRect(x: 14.2, y: 17.2, width: 5.6, height: 5.6)), with: .color(line))
                ctx.fill(Path(ellipseIn: CGRect(x: 28.2, y: 17.2, width: 5.6, height: 5.6)), with: .color(line))
            }
            let mouth = IconSets.path(IconPaths.mouths[i])
            if i == 4 { ctx.fill(mouth, with: .color(line)) }
            ctx.stroke(mouth, with: .color(line), style: round3(3))
        }
    }
}

/// Thumb in the line / tone / mark set.
struct ThumbIcon: View {
    let set: String, up: Bool, selected: Bool, brand: Color
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            ctx.scaleBy(x: s, y: s)
            let tone = up ? IconSets.green : IconSets.red
            if set == "mark" {
                ctx.fill(Path(ellipseIn: CGRect(x: 2, y: 2, width: 20, height: 20)), with: .color(selected ? tone : Crisp.neutral))
                ctx.stroke(IconSets.path(up ? IconPaths.tick : IconPaths.cross), with: .color(.white), style: round3(2.4))
                return
            }
            if !up { ctx.translateBy(x: 0, y: 24); ctx.scaleBy(x: 1, y: -1) }
            let p = IconSets.path(IconPaths.thumb)
            if set == "tone" && selected { ctx.fill(p, with: .color(up ? Color(hex: 0xBBF7D0) : Color(hex: 0xFECACA))) }
            let color = set == "tone" ? tone : (selected ? brand : Crisp.muted)
            ctx.stroke(p, with: .color(color), style: round3(1.8))
        }
    }
}

struct StarIcon: View {
    let path: String, fill: Color
    let stroke: Color?
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            ctx.scaleBy(x: s, y: s)
            let p = IconSets.path(path)
            ctx.fill(p, with: .color(fill))
            if let stroke { ctx.stroke(p, with: .color(stroke), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)) }
        }
    }
}

struct CheckIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            ctx.scaleBy(x: s, y: s)
            ctx.fill(IconSets.path(IconPaths.check), with: .color(color))
        }
    }
}
#endif
