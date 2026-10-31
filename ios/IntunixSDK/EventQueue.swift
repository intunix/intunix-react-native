import Foundation

/// Events that failed to upload, kept on disk and replayed (if under a day old) on the next start.
package final class OfflineStore {
    private let store: KeyValueStore
    private let clock: () -> Int64
    package init(_ store: KeyValueStore, clock: @escaping () -> Int64) { self.store = store; self.clock = clock }

    package func save(_ batch: [JSONObject]) {
        let all = readAll() + batch
        store.set("intunix:offline", jsonString(Array(all.suffix(1000))))
    }

    /// Drop entries that were uploaded after being saved defensively.
    package func remove(_ batch: [JSONObject]) {
        let sent = Set(batch.map { jsonString($0) })
        let left = readAll().filter { !sent.contains(jsonString($0)) }
        if left.isEmpty { store.remove("intunix:offline") } else { store.set("intunix:offline", jsonString(left)) }
    }

    package func readAll() -> [JSONObject] { (parseJSON(store.get("intunix:offline")) as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }

    package func replay(_ flush: ([JSONObject]) async throws -> Void) async {
        let pending = readAll()
        guard !pending.isEmpty else { return }
        store.remove("intunix:offline")
        let cutoff = clock() - DAY_MS
        let fresh = pending.filter { ($0.int64("timestamp") ?? 0) >= cutoff }
        guard !fresh.isEmpty else { return }
        do { try await flush(fresh) } catch { save(fresh) }
    }
}

@MainActor
package final class EventQueue {
    private var buf: [JSONObject] = []
    private var task: Task<Void, Never>?
    private let flushMs: UInt64, max: Int
    private let offline: OfflineStore
    private let flush: ([JSONObject]) async throws -> Void

    package init(flushMs: UInt64, max: Int, offline: OfflineStore, flush: @escaping ([JSONObject]) async throws -> Void) {
        self.flushMs = flushMs; self.max = max; self.offline = offline; self.flush = flush
    }

    package func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: (self?.flushMs ?? 5000) * 1_000_000)
                await self?.drain()
            }
        }
    }

    package func push(_ e: JSONObject) {
        buf.append(e)
        if buf.count >= max { Task { await drain() } }
    }

    /// Upload what is buffered; on failure the batch goes to disk. When the app backgrounds
    /// (`persistFirst`) the batch is written to disk first, so a suspend-then-kill loses nothing.
    package func drain(persistFirst: Bool = false) async {
        guard !buf.isEmpty else { return }
        let batch = buf
        buf.removeAll()
        if persistFirst { offline.save(batch) }
        do {
            try await flush(batch)
            if persistFirst { offline.remove(batch) }
        } catch {
            if !persistFirst { offline.save(batch) }
        }
    }
}
