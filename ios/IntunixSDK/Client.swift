import Foundation

package struct RenderCallbacks {
    package let onImpression: () -> Void
    package let onResponse: (Answer) -> Void
    package let onDismiss: () -> Void
    package let clientResponseId: String
    package let onReviewEvent: (ReviewEvent) -> Void
    package init(onImpression: @escaping () -> Void, onResponse: @escaping (Answer) -> Void, onDismiss: @escaping () -> Void,
                 clientResponseId: String, onReviewEvent: @escaping (ReviewEvent) -> Void) {
        self.onImpression = onImpression; self.onResponse = onResponse; self.onDismiss = onDismiss
        self.clientResponseId = clientResponseId; self.onReviewEvent = onReviewEvent
    }
}

package struct ExperienceResult {
    package let outcome: String
    package let response: FeedbackResponse?
    package init(outcome: String, response: FeedbackResponse?) { self.outcome = outcome; self.response = response }
}

/// Puts a form on screen and returns once the visitor is done with it.
@MainActor
package protocol FormPresenter: AnyObject {
    /// nil when the form could not be put on screen.
    func present(_ exp: Experience, _ content: FeedbackContent, _ callbacks: RenderCallbacks) async -> ExperienceResult?
}

package struct ClientConfig {
    package var apiKey: String, apiHost: String
    package var registerAll: Bool
    package var register: [String]
    package var flushIntervalMs: UInt64
    package var maxQueueSize: Int
    package var screenTriggerDelayMs: UInt64
    package var disableEventApi: Bool
    package var sdkVersion: String
    package init(apiKey: String, apiHost: String, registerAll: Bool, register: [String], flushIntervalMs: UInt64,
                 maxQueueSize: Int, screenTriggerDelayMs: UInt64, disableEventApi: Bool, sdkVersion: String) {
        self.apiKey = apiKey; self.apiHost = apiHost; self.registerAll = registerAll; self.register = register
        self.flushIntervalMs = flushIntervalMs; self.maxQueueSize = maxQueueSize; self.screenTriggerDelayMs = screenTriggerDelayMs
        self.disableEventApi = disableEventApi; self.sdkVersion = sdkVersion
    }
}

/// Port of @intunix/core IntunixClient, confined to the main actor.
@MainActor
package final class IntunixClient {
    private let cfg: ClientConfig
    private let store: KeyValueStore
    private weak var presenter: FormPresenter?
    private let log: (String) -> Void
    private let clock: () -> Int64
    private let http: Http
    private let anon: AnonId
    private let session: SessionManager
    private let profile: ProfileStore
    private let shown: ShownStore
    private let offline: OfflineStore
    private var queue: EventQueue!
    private var triggers: TriggerEvaluator!

    private var experiences: [Experience] = []
    private var fetched: [String: Experience] = [:]
    private var batchShown = false
    private var loading: Task<Void, Never>?
    private var user: GateUser?
    private var context: JSONObject = [:]
    private var registeredIds: [String] = []
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    private var showing = false
    private var activeId: String?
    private var showQueue: [String] = []
    private var pendingShowContext: [String: JSONObject] = [:]

    package init(cfg: ClientConfig, store: KeyValueStore, presenter: FormPresenter, log: @escaping (String) -> Void,
                 clock: @escaping () -> Int64 = nowMs) {
        self.cfg = cfg; self.store = store; self.presenter = presenter; self.log = log; self.clock = clock
        http = Http(apiHost: cfg.apiHost, apiKey: cfg.apiKey, sdkHeader: "ios/\(cfg.sdkVersion)")
        anon = AnonId(store)
        session = SessionManager(store, clock: clock)
        profile = ProfileStore(store, clock: clock)
        shown = ShownStore(store)
        offline = OfflineStore(store, clock: clock)
        queue = EventQueue(flushMs: cfg.flushIntervalMs, max: cfg.maxQueueSize, offline: offline) { [weak self] in try await self?.flush($0) }
        triggers = TriggerEvaluator(screenDelayMs: cfg.screenTriggerDelayMs) { [weak self] in self?.enqueueShow($0.id) }
    }

    package func start() {
        // Registered before anything can mint a session, so the first one is counted too.
        session.onNewSession { [weak self] _ in
            guard let self else { return }
            self.profile.onSessionStart()
            self.context.removeAll()
            Task { await self.loadExperiences(); self.rearm() }
        }
        Task { await offline.replay { [weak self] in try await self?.flush($0) } }
        Task {
            _ = session.id()
            await loadExperiences()
            queue.start()
            triggers.attach(experiences)
            registerAutoActivate()
            isReady = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
            if !cfg.registerAll { cfg.register.forEach { register($0) } }
            log("ready, \(experiences.count) forms")
        }
    }

    private func ready() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    /// App came to the foreground: renew (or start) the session.
    package func onForeground() { _ = session.id() }
    /// App went to the background: upload buffered events now.
    package func onBackground() async { await queue.drain(persistFirst: true) }

    // MARK: catalog

    private func formsParam() -> String { cfg.registerAll ? "all" : cfg.register.sorted().joined(separator: ",") }

    private func loadExperiences(force: Bool = false) async {
        if let loading { await loading.value; return }
        let t = Task { await doLoad(force) }
        loading = t
        await t.value
        loading = nil
    }

    private func doLoad(_ force: Bool) async {
        let wanted = formsParam()
        if wanted.isEmpty { experiences = []; batchShown = false; return }
        let cached = parseJSON(store.get(Self.cacheKey)) as? JSONObject
        if let cached {
            experiences = cached.objects("data").compactMap(parseExperience)
            batchShown = cached.obj("caps")?.bool("batchShown") == true
        }
        let sid = session.id()
        if let cached, cached.str("sid") == sid, cached.str("set") == wanted, !force { return }
        do {
            let q = wanted.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? wanted
            let res = try await retry { try await self.http.request("GET", "/sdk/experiences?forms=\(q)", etag: force ? nil : cached?.str("etag")) }
            if res.status == 304 {
                if var c = cached { c["sid"] = sid; c["set"] = wanted; store.set(Self.cacheKey, jsonString(c)) }
                return
            }
            let data = (parseJSON(res.body) as? JSONObject)?.obj("data") ?? [:]
            let raw = data.arr("experiences") ?? []
            let caps = data.obj("capabilities") ?? [:]
            experiences = raw.compactMap { ($0 as? JSONObject).flatMap(parseExperience) }
            batchShown = caps.bool("batchShown") == true
            store.set(Self.cacheKey, jsonString(["etag": res.etag ?? NSNull(), "data": raw, "caps": caps, "sid": sid, "set": wanted] as JSONObject))
            triggers?.attach(experiences)
            registerAutoActivate()
        } catch {
            log("catalog load failed: \(error)")
            if cached == nil { experiences = [] }
        }
    }

    private func find(_ idOrSlug: String) -> Experience? {
        experiences.first { $0.id == idOrSlug || $0.slug == idOrSlug } ?? fetched.values.first { $0.id == idOrSlug || $0.slug == idOrSlug }
    }

    package func resolve(_ idOrSlug: String) async -> Experience? {
        await ready()
        if let e = find(idOrSlug) { return e }
        do {
            let path = idOrSlug.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? idOrSlug
            let res = try await retry { try await self.http.request("GET", "/sdk/forms/\(path)") }
            guard let o = (parseJSON(res.body) as? JSONObject)?.obj("data")?.obj("experience"), let e = parseExperience(o) else { return nil }
            fetched[e.id] = e
            return e
        } catch {
            log("form \(idOrSlug) not found: \(error)")
            return nil
        }
    }

    // MARK: registration

    private func registerAutoActivate() {
        for e in experiences where e.autoActivate && !registeredIds.contains(e.id) {
            registeredIds.append(e.id)
            triggers.register(e)
        }
    }

    private func rearm() { registeredIds.compactMap(find).forEach(triggers.register) }

    package func register(_ idOrSlug: String) {
        Task {
            guard let e = await resolve(idOrSlug) else { return }
            triggers.register(e)
            if !registeredIds.contains(e.id) { registeredIds.append(e.id) }
        }
    }

    package func unregister(_ idOrSlug: String) {
        guard let e = find(idOrSlug) else { return }
        registeredIds.removeAll { $0 == e.id }
        triggers.unregister(e.id)
    }

    // MARK: identity & context

    package func identify(_ userId: String, _ traits: JSONObject) {
        let prev = anon.get()
        let first = user?.id != userId
        user = GateUser(id: userId, traits: traits)
        if first {
            shown.mergeIdentity(from: prev, to: userId)
            profile.mergeIdentity(from: prev, to: userId)
        }
        if isReady { triggers.reevaluateUserTriggers(traits) }
    }

    package func reset() {
        user = nil
        anon.reset()
        session.reset()
        context.removeAll()
    }

    package func setContext(_ patch: JSONObject?) {
        guard let patch else { context.removeAll(); return }
        context.merge(patch) { $1 }
    }

    // MARK: events & screens

    package func track(_ name: String, _ props: JSONObject) {
        var e: JSONObject = ["name": name, "properties": props, "timestamp": clock(), "sessionId": session.id(), "anonymousId": anon.get()]
        if let id = user?.id { e["userId"] = id }
        queue.push(e)
        if isReady { triggers.onEvent(name, props) }
    }

    package func screen(_ name: String) {
        if isReady { triggers.onScreen(name) } else { Task { await ready(); triggers.onScreen(name) } }
    }

    private func flush(_ batch: [JSONObject]) async throws {
        if cfg.disableEventApi { return }
        _ = try await retry { try await self.http.request("POST", "/sdk/events", body: ["batch": batch, "channel": channel] as JSONObject) }
    }

    // MARK: showing

    package func showForm(_ idOrSlug: String, context ctx: JSONObject?) {
        Task {
            guard let e = await resolve(idOrSlug) else { return }
            if let ctx { pendingShowContext[e.id] = ctx }
            enqueueShow(e.id)
        }
    }

    private func enqueueShow(_ id: String) {
        guard activeId != id, !showQueue.contains(id) else { return }
        showQueue.append(id)
        pump()
    }

    package func contextFor(_ perCall: JSONObject?) -> JSONObject { context.merging(perCall ?? [:]) { $1 } }

    private func isEligible(_ e: Experience, _ ctx: JSONObject) -> Bool {
        guard checkPlatform(e), checkTargeting(e, user, ctx, screen: triggers.currentScreen) else { return false }
        let now = clock()
        guard checkEligibility(e, profile.read(), now: now) else { return false }
        let key = identityKey(e, uid: user?.id ?? anon.get(), traits: user?.traits ?? [:], context: ctx)
        return checkCadence(normalizeCadence(e.cadence), shown.get(e.id, key), profile.outcomes(e.id, key), now: now, sessionId: session.id())
    }

    private func pump() {
        guard !showing, !showQueue.isEmpty else { return }
        let id = showQueue.removeFirst()
        let ctx = contextFor(pendingShowContext[id])
        guard let e = find(id), let content = parseFeedbackContent(e.content), isEligible(e, ctx), let presenter else {
            pendingShowContext[id] = nil
            pump()
            return
        }
        showing = true
        activeId = id
        Task {
            let responseId = newId()
            // nil: the form never reached the screen, so it must not count against cadence.
            if let result = await presenter.present(e, content, callbacks(e, ctx, responseId)) {
                settle(e, ctx, result, responseId)
            }
            pendingShowContext[id] = nil
            showing = false
            activeId = nil
            pump()
        }
    }

    package func callbacks(_ e: Experience, _ ctx: JSONObject, _ responseId: String) -> RenderCallbacks {
        RenderCallbacks(
            onImpression: { [weak self] in
                guard let self else { return }
                self.track("$experience_impression", ["id": e.id])
                if self.batchShown { self.track("$form_shown", ["form_id": e.id, "context": ctx]) } else { self.reportShown(e.id) }
            },
            onResponse: { [weak self] a in self?.track("$experience_response", ["id": e.id, "answer": a.wire]) },
            onDismiss: { [weak self] in
                guard let self else { return }
                self.track("$experience_dismissed", ["id": e.id])
                if self.batchShown { self.track("$form_dismissed", ["form_id": e.id, "context": ctx]) }
            },
            clientResponseId: responseId,
            onReviewEvent: { [weak self] ev in
                var p: JSONObject = ["form_id": ev.formId, "client_response_id": ev.clientResponseId, "platform": ev.platform,
                                     "review_url": ev.reviewUrl, "trigger_rule": ev.triggerRule]
                if let t = ev.triggerThreshold { p["trigger_threshold"] = t }
                self?.track(ev.name, p)
            })
    }

    /// Record the show for cadence and upload the answers. Also used by the inline IntunixForm.
    package func settle(_ e: Experience, _ ctx: JSONObject, _ result: ExperienceResult, _ responseId: String) {
        let key = identityKey(e, uid: user?.id ?? anon.get(), traits: user?.traits ?? [:], context: ctx)
        shown.markShown(e.id, key, now: clock(), sessionId: session.id())
        profile.recordOutcome(e.id, key, result.outcome)
        guard let fb = result.response, !fb.answers.isEmpty else { return }
        var response: JSONObject = [:]
        fb.answers.forEach { response[$0.stepId] = ["kind": $0.kind, "value": $0.value.wire] as JSONObject }
        var body: JSONObject = [
            "response": response, "channel": channel, "session_id": session.id(), "user_traits": user?.traits ?? [:],
            "duration_ms": fb.durationMs, "completed": fb.completed, "context": ctx, "anonymous_id": anon.get(),
            "client_response_id": responseId,
        ]
        if let id = user?.id { body["user_id"] = id }
        let path = "/sdk/forms/\(e.id)/response"
        Task {
            do { _ = try await retry { try await self.http.request("POST", path, body: body) } }
            catch { log("response submit failed: \(error)") }
        }
    }

    private func reportShown(_ id: String) {
        Task {
            do { _ = try await retry { try await self.http.request("POST", "/sdk/forms/\(id)/shown", body: ["channel": channel]) } }
            catch { log("shown report failed: \(error)") }
        }
    }

    private static let cacheKey = "intunix:experiences:v2"
}
