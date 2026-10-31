import Foundation

/// Absolute drawing commands, platform-neutral so the parser is testable anywhere.
package enum PathCmd: Equatable {
    case move(Double, Double)
    case line(Double, Double)
    case quad(Double, Double, Double, Double)
    case cubic(Double, Double, Double, Double, Double, Double)
    case close
}

/// Parses SVG path data (M L H V Q C A Z, absolute and relative) into absolute commands.
/// Arcs become cubic Béziers. Enough for the icon paths shared with @intunix/core.
package func parseSvgPath(_ d: String) -> [PathCmd] {
    var tokens: [String] = []
    var cur = ""
    func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
    for ch in d {
        if ch.isLetter && ch != "e" && ch != "E" { flush(); tokens.append(String(ch)) }
        else if ch == "," || ch == " " || ch == "\n" || ch == "\t" { flush() }
        else if ch == "-" && !(cur.hasSuffix("e") || cur.hasSuffix("E")) { flush(); cur = "-" }
        else if ch == "." && cur.contains(".") { flush(); cur = "." }
        else { cur.append(ch) }
    }
    flush()

    var out: [PathCmd] = []
    var i = 0
    var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0
    var cmd: Character = "M"
    func num() -> Double { defer { i += 1 }; return i < tokens.count ? Double(tokens[i]) ?? 0 : 0 }

    while i < tokens.count {
        if let c = tokens[i].first, tokens[i].count == 1, c.isLetter { cmd = c; i += 1 }
        else if cmd == "Z" || cmd == "z" { i += 1; continue } // stray number after Z
        let rel = cmd.isLowercase
        let ox = rel ? x : 0, oy = rel ? y : 0
        switch cmd.uppercased() {
        case "M":
            x = ox + num(); y = oy + num(); sx = x; sy = y
            out.append(.move(x, y))
            cmd = rel ? "l" : "L"
        case "L": x = ox + num(); y = oy + num(); out.append(.line(x, y))
        case "H": x = (rel ? x : 0) + num(); out.append(.line(x, y))
        case "V": y = (rel ? y : 0) + num(); out.append(.line(x, y))
        case "Q":
            let cx = ox + num(), cy = oy + num(); x = ox + num(); y = oy + num()
            out.append(.quad(cx, cy, x, y))
        case "C":
            let c1x = ox + num(), c1y = oy + num(), c2x = ox + num(), c2y = oy + num()
            x = ox + num(); y = oy + num()
            out.append(.cubic(c1x, c1y, c2x, c2y, x, y))
        case "A":
            let rx = num(), ry = num(), rot = num(), large = num() != 0, sweep = num() != 0
            let ex = ox + num(), ey = oy + num()
            out.append(contentsOf: arcToCubics(x, y, rx, ry, rot, large, sweep, ex, ey))
            x = ex; y = ey
        case "Z": out.append(.close); x = sx; y = sy
        default: i += 1
        }
    }
    return out
}

/// SVG endpoint arc to cubic Béziers (one per ≤90° slice).
private func arcToCubics(_ x1: Double, _ y1: Double, _ rxIn: Double, _ ryIn: Double, _ angle: Double,
                         _ large: Bool, _ sweep: Bool, _ x2: Double, _ y2: Double) -> [PathCmd] {
    if rxIn == 0 || ryIn == 0 { return [.line(x2, y2)] }
    var rx = abs(rxIn), ry = abs(ryIn)
    let phi = angle * .pi / 180, cosP = cos(phi), sinP = sin(phi)
    let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
    let x1p = cosP * dx + sinP * dy, y1p = -sinP * dx + cosP * dy
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
    let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    var coef = sqrt(max(0, num / den))
    if large == sweep { coef = -coef }
    let cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx
    let cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2, cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2
    func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    }
    let t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    var dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }
    let segs = max(1, Int(ceil(abs(dt) / (.pi / 2))))
    let delta = dt / Double(segs)
    let k = 4.0 / 3.0 * tan(delta / 4)
    var out: [PathCmd] = []
    var t = t1
    func point(_ a: Double) -> (Double, Double) {
        (cx + rx * cos(a) * cosP - ry * sin(a) * sinP, cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
    }
    func deriv(_ a: Double) -> (Double, Double) {
        (-rx * sin(a) * cosP - ry * cos(a) * sinP, -rx * sin(a) * sinP + ry * cos(a) * cosP)
    }
    for _ in 0..<segs {
        let (p1x, p1y) = point(t), (d1x, d1y) = deriv(t)
        let t2 = t + delta
        let (p2x, p2y) = point(t2), (d2x, d2y) = deriv(t2)
        out.append(.cubic(p1x + k * d1x, p1y + k * d1y, p2x - k * d2x, p2y - k * d2y, p2x, p2y))
        t = t2
    }
    if case .cubic(let a, let b, let c, let d, _, _) = out[out.count - 1] { out[out.count - 1] = .cubic(a, b, c, d, x2, y2) }
    return out
}

/// Icon geometry shared with @intunix/core icons.ts.
package enum IconPaths {
    package static let star = "M12 2.5l2.9 6.3 6.9.7-5.2 4.6 1.5 6.8L12 17.3l-6.1 3.6 1.5-6.8L2.2 9.5l6.9-.7z"
    package static let heart = "M12 20.6l-1.4-1.3C5.4 14.6 2 11.5 2 7.7 2 4.6 4.4 2.2 7.5 2.2c1.7 0 3.4.8 4.5 2.1 1.1-1.3 2.8-2.1 4.5-2.1 3.1 0 5.5 2.4 5.5 5.5 0 3.8-3.4 6.9-8.6 11.6z"
    package static let thumb = "M7 10v12M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"
    package static let check = "M9 16.2l-3.5-3.5L4 14.2l5 5 11-11-1.5-1.5z"
    package static let tick = "M7.5 12.5l3 3 6-6.5"
    package static let cross = "M8.5 8.5l7 7M15.5 8.5l-7 7"
    package static let mouths = ["M15 35q9-9 18 0", "M16 34q8-5 16 0", "M16 32h16", "M16 30q8 6 16 0", "M14 28q10 12 20 0z"]
    package static let happyEyes = "M13 21q4-5 8 0M27 21q4-5 8 0"
    package static let brows = "M12 13l7 3.5M36 13l-7 3.5"
}

/// Colour band for the 'ramp' star set: low ≤40% of max, mid ≤60%, else high.
package func starTone(_ count: Int, _ max: Int) -> String? {
    guard count > 0, max > 0 else { return nil }
    let r = Double(count) / Double(max)
    return r <= 0.4 ? "low" : r <= 0.6 ? "mid" : "high"
}
