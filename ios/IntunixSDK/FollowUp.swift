#if os(iOS)
import SwiftUI

struct FollowUpStep: View {
    let step: Step, answer: Answer?, onChange: OnAnswer

    var body: some View {
        if let input = step.input {
            switch input.type {
            case "free", "email", "name": TextAnswer(step: step, input: input, answer: answer, onChange: onChange)
            case "selectOne":
                let selected: String? = { if case .one(let s)? = answer?.value { return s }; return nil }()
                VStack(spacing: 8) {
                    ForEach(input.options, id: \.value) { o in
                        OptionRow(label: o.label, emoji: o.emoji, radio: true, checked: selected == o.value) {
                            onChange(Answer(step.id, "followup", .one(o.value)))
                        }
                    }
                }
            case "selectMultiple":
                let picks: [String] = { if case .many(let s)? = answer?.value { return s }; return [] }()
                let min = input.minPick ?? (step.required == true ? 1 : 0)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(input.options, id: \.value) { o in
                        let on = picks.contains(o.value)
                        let full = input.maxPick.map { picks.count >= $0 } ?? false
                        OptionRow(label: o.label, emoji: o.emoji, radio: false, checked: on, enabled: on || !full) {
                            onChange(Answer(step.id, "followup", .many(on ? picks.filter { $0 != o.value } : picks + [o.value])))
                        }
                    }
                    if min > 1 && picks.count < min { Text("Pick at least \(min).").crispFont(12.5, .regular, Crisp.muted) }
                }
            default: EmptyView()
            }
        }
    }
}

private struct TextAnswer: View {
    let step: Step, input: FollowUpInput, answer: Answer?, onChange: OnAnswer
    @Environment(\.brand) var brand
    @State private var text = ""
    @State private var touched = false
    @FocusState private var focused: Bool

    var body: some View {
        let invalid = input.type == "email" && touched && !text.trimmingCharacters(in: .whitespaces).isEmpty
            && !isEmail(text.trimmingCharacters(in: .whitespaces))
        let placeholder = input.placeholder ?? (input.type == "email" ? "you@example.com" : input.type == "name" ? "Your name" : "Type your answer…")
        let border = invalid ? Crisp.error : focused ? brand.color : Crisp.border
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if input.type == "free" {
                    if text.isEmpty { Text(placeholder).crispFont(16, .regular, Crisp.neutral).padding(.horizontal, 14).padding(.vertical, 13) }
                    TextEditor(text: $text)
                        .font(.system(size: 16)).foregroundColor(Crisp.text)
                        .focused($focused)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .frame(minHeight: 120)
                        .background(Crisp.card)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Crisp.neutral))
                        .font(.system(size: 16)).foregroundColor(Crisp.text)
                        .focused($focused)
                        .keyboardType(input.type == "email" ? .emailAddress : .default)
                        .textInputAutocapitalization(input.type == "email" ? .never : .words)
                        .disableAutocorrection(input.type != "free")
                        .padding(.horizontal, 14).frame(minHeight: 50)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Crisp.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: 1.5))
            .ring(focused, invalid ? Crisp.error.opacity(0.12) : brand.soft)
            .accessibilityLabel(step.title)
            if input.type == "free", let max = input.maxLength {
                Text("\(text.utf16.count)/\(max)").crispFont(12, .regular, Crisp.muted).frame(maxWidth: .infinity, alignment: .trailing)
            }
            if invalid { Text("Enter a valid email address.").crispFont(13, .regular, Crisp.error) }
        }
        .onAppear { if case .text(_, let t)? = answer?.value { text = t } }
        .onChange(of: text) { v in
            var next = v
            // UTF-16 length, as JavaScript counts it.
            if input.type == "free", let max = input.maxLength, next.utf16.count > max {
                while next.utf16.count > max { next.removeLast() }
                text = next
            }
            onChange(Answer(step.id, "followup", .text(type: input.type, text: next)))
        }
        .onChange(of: focused) { f in if !f { touched = true } }
    }
}
#endif
