import Foundation

package protocol KeyValueStore: AnyObject {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func remove(_ key: String)
}

package final class MemoryStore: KeyValueStore {
    private var map: [String: String] = [:]
    package init() {}
    package func get(_ key: String) -> String? { map[key] }
    package func set(_ key: String, _ value: String) { map[key] = value }
    package func remove(_ key: String) { map[key] = nil }
}

package final class DefaultsStore: KeyValueStore {
    private let d = UserDefaults(suiteName: "com.intunix.sdk") ?? .standard
    package init() {}
    package func get(_ key: String) -> String? { d.string(forKey: key) }
    package func set(_ key: String, _ value: String) { d.set(value, forKey: key) }
    package func remove(_ key: String) { d.removeObject(forKey: key) }
}

package func newId() -> String { UUID().uuidString.lowercased() }

package func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

package final class AnonId {
    private let store: KeyValueStore
    package init(_ store: KeyValueStore) { self.store = store }
    package func get() -> String {
        if let v = store.get("intunix:anon") { return v }
        let id = newId(); store.set("intunix:anon", id); return id
    }
    @discardableResult package func reset() -> String { let id = newId(); store.set("intunix:anon", id); return id }
}

/// A session ends after 30 minutes without activity; minting a new one notifies listeners.
package final class SessionManager {
    package static let ttlMs: Int64 = 30 * 60 * 1000
    private let store: KeyValueStore
    private let clock: () -> Int64
    private var callbacks: [(id: Int, fn: (String) -> Void)] = []
    private var nextId = 0

    package init(_ store: KeyValueStore, clock: @escaping () -> Int64) { self.store = store; self.clock = clock }

    package func id() -> String {
        let now = clock()
        if let o = parseJSON(store.get("intunix:session")) as? JSONObject, let id = o.str("id"), let exp = o.int64("exp"), exp > now {
            write(id, now)
            return id
        }
        let id = newId()
        write(id, now)
        for cb in callbacks { cb.fn(id) }
        return id
    }

    package func reset() { store.remove("intunix:session") }

    @discardableResult package func onNewSession(_ fn: @escaping (String) -> Void) -> () -> Void {
        nextId += 1
        let token = nextId
        callbacks.append((token, fn))
        return { [weak self] in self?.callbacks.removeAll { $0.id == token } }
    }

    private func write(_ id: String, _ now: Int64) { store.set("intunix:session", jsonString(["id": id, "exp": now + Self.ttlMs])) }
}

package struct ProfileData {
    package var firstSeenAt: Int64
    package var sessionCount: Int
    package var lastSeenAt: Int64
    package var outcomes: [String: [String: OutcomeRecord]]
    package init(firstSeenAt: Int64, sessionCount: Int, lastSeenAt: Int64, outcomes: [String: [String: OutcomeRecord]] = [:]) {
        self.firstSeenAt = firstSeenAt; self.sessionCount = sessionCount; self.lastSeenAt = lastSeenAt; self.outcomes = outcomes
    }
}

private func splitUid(_ key: String) -> (String, String) {
    guard let i = key.firstIndex(of: "|") else { return (key, "") }
    return (String(key[..<i]), String(key[i...]))
}

package final class ProfileStore {
    private let store: KeyValueStore
    private let clock: () -> Int64
    package init(_ store: KeyValueStore, clock: @escaping () -> Int64) { self.store = store; self.clock = clock }

    package func read() -> ProfileData { load() }

    package func onSessionStart() {
        var p = load(); p.sessionCount += 1; p.lastSeenAt = clock(); save(p)
    }

    package func recordOutcome(_ formId: String, _ key: String, _ outcome: String) {
        var p = load()
        var rec = p.outcomes[formId]?[key] ?? OutcomeRecord()
        let now = clock()
        rec.showCount += 1
        rec.lastOutcome = outcome
        rec.lastOutcomeAt = now
        if outcome == "responded" { rec.respondedAt = now }
        p.outcomes[formId, default: [:]][key] = rec
        save(p)
    }

    package func outcomes(_ formId: String, _ key: String) -> OutcomeRecord? { load().outcomes[formId]?[key] }

    package func mergeIdentity(from: String, to: String) {
        var p = load()
        for (form, var m) in p.outcomes {
            for (key, rec) in m {
                let (uid, suffix) = splitUid(key)
                guard uid == from else { continue }
                let newKey = to + suffix
                m[key] = nil
                if let t = m[newKey] {
                    let newer = (rec.lastOutcomeAt ?? 0) > (t.lastOutcomeAt ?? 0) ? rec : t
                    m[newKey] = OutcomeRecord(respondedAt: [t.respondedAt, rec.respondedAt].compactMap { $0 }.max(),
                                              showCount: max(t.showCount, rec.showCount),
                                              lastOutcome: newer.lastOutcome, lastOutcomeAt: newer.lastOutcomeAt)
                } else { m[newKey] = rec }
            }
            p.outcomes[form] = m
        }
        save(p)
    }

    private func fresh() -> ProfileData { let n = clock(); return ProfileData(firstSeenAt: n, sessionCount: 0, lastSeenAt: n) }

    private func load() -> ProfileData {
        guard let o = parseJSON(store.get("intunix:profile")) as? JSONObject,
              let first = o.int64("firstSeenAt"), let count = o.int("sessionCount"), let last = o.int64("lastSeenAt"),
              let all = o.obj("outcomes") else { return fresh() }
        var outcomes: [String: [String: OutcomeRecord]] = [:]
        for (form, v) in all {
            guard let f = v as? JSONObject else { continue }
            var m: [String: OutcomeRecord] = [:]
            for (k, rv) in f {
                guard let r = rv as? JSONObject else { continue }
                m[k] = OutcomeRecord(respondedAt: r.int64("respondedAt"), showCount: r.int("showCount") ?? 0,
                                     lastOutcome: r.str("lastOutcome"), lastOutcomeAt: r.int64("lastOutcomeAt"))
            }
            outcomes[form] = m
        }
        return ProfileData(firstSeenAt: first, sessionCount: count, lastSeenAt: last, outcomes: outcomes)
    }

    private func save(_ p: ProfileData) {
        var all: JSONObject = [:]
        for (form, m) in p.outcomes {
            var f: JSONObject = [:]
            for (k, r) in m {
                var o: JSONObject = ["showCount": r.showCount]
                if let v = r.respondedAt { o["respondedAt"] = v }
                if let v = r.lastOutcome { o["lastOutcome"] = v }
                if let v = r.lastOutcomeAt { o["lastOutcomeAt"] = v }
                f[k] = o
            }
            all[form] = f
        }
        store.set("intunix:profile", jsonString(["firstSeenAt": p.firstSeenAt, "sessionCount": p.sessionCount, "lastSeenAt": p.lastSeenAt, "outcomes": all]))
    }
}

/// Per form, per identity key: when it was last shown and how often.
package final class ShownStore {
    private let store: KeyValueStore
    package init(_ store: KeyValueStore) { self.store = store }

    package func get(_ formId: String, _ key: String) -> ShownRecord? { read()[formId]?[key] }

    package func markShown(_ formId: String, _ key: String, now: Int64, sessionId: String) {
        var all = read()
        let prev = all[formId]?[key]?.count ?? 0
        all[formId, default: [:]][key] = ShownRecord(lastShownAt: now, count: prev + 1, sessionId: sessionId)
        write(all)
    }

    package func mergeIdentity(from: String, to: String) {
        var all = read()
        for (form, var m) in all {
            for (key, rec) in m {
                let (uid, suffix) = splitUid(key)
                guard uid == from else { continue }
                let newKey = to + suffix
                m[key] = nil
                if let t = m[newKey] {
                    m[newKey] = ShownRecord(lastShownAt: max(t.lastShownAt, rec.lastShownAt), count: max(t.count, rec.count),
                                            sessionId: rec.lastShownAt > t.lastShownAt ? rec.sessionId : t.sessionId)
                } else { m[newKey] = rec }
            }
            all[form] = m
        }
        write(all)
    }

    private func read() -> [String: [String: ShownRecord]] {
        guard let o = parseJSON(store.get("intunix:shown")) as? JSONObject else { return [:] }
        var out: [String: [String: ShownRecord]] = [:]
        for (form, v) in o {
            guard let f = v as? JSONObject else { continue }
            var m: [String: ShownRecord] = [:]
            for (k, rv) in f {
                guard let r = rv as? JSONObject, let at = r.int64("lastShownAt"), let c = r.int("count") else { continue }
                m[k] = ShownRecord(lastShownAt: at, count: c, sessionId: r.str("sessionId"))
            }
            out[form] = m
        }
        return out
    }

    private func write(_ all: [String: [String: ShownRecord]]) {
        var o: JSONObject = [:]
        for (form, m) in all {
            var f: JSONObject = [:]
            for (k, r) in m {
                var x: JSONObject = ["lastShownAt": r.lastShownAt, "count": r.count]
                if let s = r.sessionId { x["sessionId"] = s }
                f[k] = x
            }
            o[form] = f
        }
        store.set("intunix:shown", jsonString(o))
    }
}
