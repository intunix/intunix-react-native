import Foundation

/// Event, screen, user-trait and time triggers. Forms fire only once registered (or autoActivate).
@MainActor
package final class TriggerEvaluator {
    private var forms: [String: Experience] = [:]
    private var registered = Set<String>()
    private var timeTasks: [String: [Task<Void, Never>]] = [:]
    private var screenTasks: [String: Task<Void, Never>] = [:]
    private let screenDelayMs: UInt64
    private let onMatch: (Experience) -> Void
    package private(set) var currentScreen = ""

    package init(screenDelayMs: UInt64, onMatch: @escaping (Experience) -> Void) {
        self.screenDelayMs = screenDelayMs; self.onMatch = onMatch
    }

    package func attach(_ experiences: [Experience]) { experiences.forEach { forms[$0.id] = $0 } }

    package func register(_ exp: Experience) {
        registered.insert(exp.id)
        forms[exp.id] = exp
        scheduleTime(exp)
        checkScreen(exp)
    }

    package func unregister(_ id: String) {
        registered.remove(id)
        timeTasks.removeValue(forKey: id)?.forEach { $0.cancel() }
        screenTasks.removeValue(forKey: id)?.cancel()
    }

    package func onEvent(_ name: String, _ props: JSONObject) {
        for exp in live() {
            for t in exp.triggers {
                guard case .event(let n, let eq) = t, n == name else { continue }
                if let eq, !eq.allSatisfy({ jsEquals(props[$0.key], $0.value) }) { continue }
                onMatch(exp)
            }
        }
    }

    package func reevaluateUserTriggers(_ traits: JSONObject) {
        for exp in live() {
            for t in exp.triggers {
                if case .user(let te) = t, te.allSatisfy({ jsEquals(traits[$0.key], $0.value) }) { onMatch(exp) }
            }
        }
    }

    package func onScreen(_ name: String) {
        currentScreen = name
        live().forEach(checkScreen)
    }

    private func live() -> [Experience] { forms.values.filter { registered.contains($0.id) }.sorted { $0.id < $1.id } }

    private func checkScreen(_ exp: Experience) {
        guard registered.contains(exp.id), !currentScreen.isEmpty else { return }
        let hit = exp.triggers.contains { if case .screen(let m, let v) = $0 { return screenMatches(m, v, currentScreen) }; return false }
        guard hit else { return }
        screenTasks.removeValue(forKey: exp.id)?.cancel()
        let delay = screenDelayMs
        screenTasks[exp.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.screenTasks[exp.id] = nil
            if self.registered.contains(exp.id) { self.onMatch(exp) }
        }
    }

    private func scheduleTime(_ exp: Experience) {
        timeTasks.removeValue(forKey: exp.id)?.forEach { $0.cancel() }
        var tasks: [Task<Void, Never>] = []
        for t in exp.triggers {
            guard case .time(let ms) = t else { continue }
            tasks.append(Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
                guard !Task.isCancelled, let self, self.registered.contains(exp.id) else { return }
                self.onMatch(exp)
            })
        }
        if !tasks.isEmpty { timeTasks[exp.id] = tasks }
    }
}

package func screenMatches(_ match: String, _ value: String, _ screen: String) -> Bool {
    switch match {
    case "contains": return screen.contains(value)
    case "regex":
        guard let re = try? NSRegularExpression(pattern: value) else { return false }
        return re.firstMatch(in: screen, range: NSRange(screen.startIndex..., in: screen)) != nil
    default: return screen == value
    }
}
