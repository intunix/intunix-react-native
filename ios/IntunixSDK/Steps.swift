#if os(iOS)
import SwiftUI

typealias OnAnswer = (Answer?) -> Void

private extension Optional where Wrapped == Answer {
    var num: Int? { if case .num(let v)? = self?.value { return v }; return nil }
    var choice: String? { if case .choice(let v)? = self?.value { return v }; return nil }
}

struct StepView: View {
    let step: Step
    let answer: Answer?
    let onChange: OnAnswer
    var body: some View {
        switch step.kind {
        case "nps", "enps", "ces": ScaleStep(step: step, answer: answer, onChange: onChange)
        case "star": StarStep(step: step, answer: answer, onChange: onChange)
        case "smileys": SmileysStep(step: step, answer: answer, onChange: onChange)
        case "thumbs": ThumbsStep(step: step, answer: answer, onChange: onChange)
        case "csat": CsatStep(step: step, answer: answer, onChange: onChange)
        case "pmf": PmfStep(step: step, answer: answer, onChange: onChange)
        case "followup": FollowUpStep(step: step, answer: answer, onChange: onChange)
        default: EmptyView()
        }
    }
}

private struct Legend: View {
    let low: String, high: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(low).crispFont(12, .medium, Crisp.muted)
            Spacer(minLength: 0)
            Text(high).crispFont(12, .medium, Crisp.muted).multilineTextAlignment(.trailing)
        }.padding(.top, 10)
    }
}

/// NPS / eNPS (0–10; two rows when narrow) and CES (1–5 or 1–7, one row).
struct ScaleStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let ces = step.kind == "ces"
        let values = ces ? Array(1...max(1, step.scale ?? Defaults.cesScale)) : Array(0...10)
        let defaults = step.kind == "ces" ? Defaults.ces : step.kind == "enps" ? Defaults.enps : Defaults.nps
        let perRow = max(1, !ces && width < Crisp.wideAt ? 6 : values.count)
        let rows = stride(from: 0, to: values.count, by: perRow).map { Array(values[$0..<min($0 + perRow, values.count)]) }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { v in cell(v) }
                    ForEach(0..<(perRow - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46) }
                }
            }
            Legend(low: step.low ?? defaults.0, high: step.high ?? defaults.1)
        }
    }

    private func cell(_ v: Int) -> some View {
        let on = answer.num == v
        return Button { onChange(Answer(step.id, step.kind, .num(v))) } label: {
            Text("\(v)").crispFont(15, .semibold, on ? brand.onColor : Crisp.scaleText)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                .box(on, brand.color, radius: 12, fill: on ? brand.color : Crisp.card)
                .ring(on, brand.soft, radius: 12)
        }
        .buttonStyle(TapStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct StarStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let max = Swift.max(1, step.max ?? Defaults.starMax)
        let selected = answer.num ?? 0
        let size: CGFloat = max == 10 ? 42 : 44
        let wide = width >= Crisp.wideAt
        let perRow = max == 10 && !wide ? 5 : Swift.max(1, Swift.min(max, Int((width + 4) / (size + 4))))
        let colors = IconSets.starColors(step.icons, starTone(selected, max), brand: brand.color)
        let path = step.icons == "heart" ? IconPaths.heart : IconPaths.star
        let values = Array(1...max)
        let rows = stride(from: 0, to: values.count, by: perRow).map { Array(values[$0..<Swift.min($0 + perRow, values.count)]) }
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(rows[r], id: \.self) { n in
                            let filled = n <= selected
                            Button { onChange(Answer(step.id, "star", .num(n))) } label: {
                                StarIcon(path: path, fill: filled ? colors.0 : Crisp.border, stroke: filled ? colors.1 : nil)
                                    .frame(width: size, height: size)
                                    .pop(selected == n)
                            }
                            .buttonStyle(TapStyle())
                            .accessibilityLabel("\(n) of \(max)")
                            .accessibilityAddTraits(selected == n ? .isSelected : [])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Group {
                if selected > 0 { Text("\(selected) ").font(.system(size: 13, weight: .semibold)).foregroundColor(Crisp.text) + Text("of \(max)").font(.system(size: 13, weight: .medium)).foregroundColor(Crisp.muted) }
                else { Text(" ").font(.system(size: 13)) }
            }
            .padding(.top, 10)
        }
    }
}

struct SmileysStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let set = step.icons.flatMap { IconSets.faceSVG.contains($0) ? $0 : nil }
        let faces = set != nil ? Array(repeating: "", count: 5) : ((step.faces?.isEmpty == false ? step.faces : nil) ?? Defaults.smileys)
        let selected = answer.num
        let room = width >= Crisp.wideAt ? min(width, 400) : width
        let n = CGFloat(faces.count)
        let cell = min((room - 4 * (n - 1)) / n, 64)
        HStack(spacing: 4) {
            ForEach(faces.indices, id: \.self) { i in
                let level = i + 1
                let on = selected == level
                let dim = set != nil && set != "line" && selected != nil && !on
                Button { onChange(Answer(step.id, "smileys", .num(level))) } label: {
                    Group {
                        if let set {
                            FaceIcon(set: set, level: level, ink: on ? brand.color : Crisp.neutral)
                                .grayscale(dim ? 0.8 : 0).opacity(dim ? 0.55 : 1)
                                .circleRing(on, Crisp.card, width: 3)
                                .circleRing(on, brand.color, width: 2, gap: 3)
                                .circleRing(on, brand.soft, width: 4, gap: 5)
                        } else {
                            Text(faces[i]).font(.system(size: 28)).grayscale(on ? 0 : 0.5)
                                .frame(width: cell, height: cell)
                                .background(Circle().fill(Crisp.card))
                                .overlay(Circle().strokeBorder(on ? brand.color : Crisp.border, lineWidth: 1.5))
                                .circleRing(on, brand.soft, width: 4)
                        }
                    }
                    .frame(width: cell, height: cell)
                    .pop(on, rest: 1.1, from: 0.94, peak: 1.22)
                }
                .buttonStyle(TapStyle())
                .accessibilityLabel("Level \(level) of \(faces.count)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ThumbsStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let set = step.icons.flatMap { IconSets.thumbSVG.contains($0) ? $0 : nil }
        let toned = set == "tone" || set == "mark"
        HStack(spacing: 10) {
            ForEach([("up", "Yes"), ("down", "No")], id: \.0) { value, label in
                let on = answer.choice == value
                let up = value == "up"
                let accent = toned ? (up ? IconSets.green : IconSets.red) : brand.color
                let tint = toned ? accent.opacity(0.15) : brand.soft
                let fill = on && toned ? (up ? Color(hex: 0xF0FDF4) : Color(hex: 0xFEF2F2)) : Crisp.card
                let labelColor = !on ? Crisp.muted : toned ? (up ? Color(hex: 0x15803D) : Color(hex: 0xB91C1C)) : brand.color
                Button { onChange(Answer(step.id, "thumbs", .choice(value))) } label: {
                    VStack(spacing: 4) {
                        Group {
                            if let set { ThumbIcon(set: set, up: up, selected: on, brand: brand.color).frame(width: 32, height: 32) }
                            else { Text(up ? "👍" : "👎").font(.system(size: 30)) }
                        }.pop(on)
                        Text(label).crispFont(12, .semibold, labelColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84)
                    .box(on, accent, radius: 16, fill: fill)
                    .ring(on, tint, radius: 16)
                }
                .buttonStyle(TapStyle())
                .accessibilityLabel(label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: width >= Crisp.wideAt ? 320 : .infinity)
        .frame(maxWidth: .infinity)
    }
}

struct CsatStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @Environment(\.formWidth) var width

    var body: some View {
        let labels = step.csatLabels ?? Defaults.csatLabels
        let wide = width >= Crisp.wideAt
        Group {
            if wide {
                HStack(spacing: 8) { ForEach(labels.indices, id: \.self) { cell($0, labels[$0], wide: true) } }
            } else {
                VStack(spacing: 8) { ForEach(labels.indices, id: \.self) { cell($0, labels[$0], wide: false) } }
            }
        }
    }

    @ViewBuilder private func icon(_ level: Int, _ on: Bool) -> some View {
        let set = step.icons.flatMap { IconSets.faceSVG.contains($0) ? $0 : nil }
        let dim = set != nil && set != "line" && answer.num != nil && !on
        Group {
            if let set {
                FaceIcon(set: set, level: level, ink: on ? brand.color : Crisp.neutral)
                    .frame(width: 28, height: 28).grayscale(dim ? 0.8 : 0).opacity(dim ? 0.55 : 1)
            } else {
                Text(Defaults.csatEmoji[level - 1]).font(.system(size: 22))
            }
        }.pop(on)
    }

    private func cell(_ i: Int, _ label: String, wide: Bool) -> some View {
        let level = i + 1
        let on = answer.num == level
        return Button { onChange(Answer(step.id, "csat", .num(level))) } label: {
            Group {
                if wide {
                    VStack(spacing: 6) {
                        icon(level, on)
                        Text(label).crispFont(12.5, on ? .semibold : .regular).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 92)
                } else {
                    HStack(spacing: 12) {
                        icon(level, on)
                        Text(label).crispFont(15, on ? .semibold : .regular)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
            }
            .box(on, brand.color)
            .ring(on, brand.soft)
        }
        .buttonStyle(TapStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct PmfStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer
    var body: some View {
        VStack(spacing: 8) {
            ForEach(step.pmfOptions ?? Defaults.pmf, id: \.value) { o in
                OptionRow(label: o.label, emoji: o.emoji, radio: true, checked: answer.choice == o.value) {
                    onChange(Answer(step.id, "pmf", .choice(o.value)))
                }
            }
        }
    }
}

/// A choice row: radio or checkbox mark, optional emoji, label.
struct OptionRow: View {
    let label: String, emoji: String?, radio: Bool, checked: Bool
    var enabled = true
    let action: () -> Void
    @Environment(\.brand) var brand

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if radio {
                        Circle().fill(checked ? brand.color : Crisp.card)
                        Circle().strokeBorder(checked ? brand.color : Crisp.markBorder, lineWidth: 2)
                        if checked { Circle().fill(Crisp.card).frame(width: 10, height: 10) }
                    } else {
                        RoundedRectangle(cornerRadius: 7).fill(checked ? brand.color : Crisp.card)
                        RoundedRectangle(cornerRadius: 7).strokeBorder(checked ? brand.color : Crisp.markBorder, lineWidth: 2)
                        if checked { CheckIcon(color: .white).frame(width: 15, height: 15) }
                    }
                }
                .frame(width: 22, height: 22)
                if let emoji { Text(emoji).font(.system(size: 18)) }
                Text(label).crispFont(15).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .box(checked, brand.color)
            .ring(checked, brand.soft)
        }
        .buttonStyle(TapStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
#endif
