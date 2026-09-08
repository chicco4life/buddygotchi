import Darwin
import Foundation
import Observation

@Observable
@MainActor
final class BuddyEngine {
    private(set) var state: BuddyState = .initial
    var popoverVisible = false
    private var settingsRevision = 0
    private var claimedTools: Set<String> = []
    private var mutedTools: Set<String> = []
    private(set) var teachTool: String?
    private var retiring = false
    private var activeRecaps = 0
    private var scheduledFocus: Bool?
    let diagnosticLog: DiagnosticLog
    let extractor = Extractor()
    private var extractionTail: Task<Void, Never>?
    private var store: (any EngineStore)?
    private var storeTail: Task<Void, Never>?
    private var voice: Voice
    private var voiceRuntime: any VoiceRuntime
    private let defaults: UserDefaults
    private var cachedProfile: [ProfileLine] = []
    private var cachedTraits: Traits = [:]
    private var contextLoaded = false
    private var contextLoad: Task<Void, Error>?
    private var stopHourCache: (day: String, hour: Int)?
    private var factsRevision = 0
    private var recapAttempt: (day: String, revision: Int, at: Double)?
    private var recapFactsCache: (day: String, revision: Int, facts: [StoredFact])?
    private var giftVoiceTask: Task<Void, Never>?
    private var bubbleVoiceTask: Task<Void, Never>?
    private var giftVoiceRevision = 0
    private var bubbleVoiceRevision = 0
    private var recapTask: Task<Void, Never>?
    private var recappedDays: Set<String> = []
    private var bootstrap: Task<Void, Never>?
    private var loadingStore = false
    private var deferredEvents: [BuddyEvent] = []
    private var lastSessionActivity: Double?
    var stateDir: String { config.stateDir }

    private var internalState: InternalState
    private var staleTimer: Timer?
    private var config: BuddyConfig
    private let clock: any Clock
    private let dayCalendar: any DayCalendar
    private let onACPower: @Sendable () -> Bool
    private var outputs: [any OutputProvider] = []
    private var processWatchers: [String: DispatchSourceProcess] = [:]
    private var pendingApprovals: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    /// Per-agent floor between expressions (S6). Engine-side, not reducer:
    /// rate limiting is wall-clock policy, not state semantics.
    private var lastExpressAt: [String: Double] = [:]
    /// One drawing per visit (E4): 30-minute floor per agent.
    private var lastDrewAt: [String: Double] = [:]

    init(config: BuddyConfig = .default, clock: (any Clock)? = nil, diagnosticLog: DiagnosticLog? = nil, store: (any EngineStore)? = nil, dayCalendar: any DayCalendar = LocalDayCalendar(), onACPower: @escaping @Sendable () -> Bool = { PowerObserver.onACPower() }, voiceRuntime: (any VoiceRuntime)? = nil, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let runtime = voiceRuntime ?? VoiceRuntimes.make(setting: defaults.string(forKey: DefaultsKey.voiceRuntime) ?? "auto")
        self.voiceRuntime = runtime
        self.voice = Voice(runtime: runtime, store: store, localDay: { await MainActor.run { dayCalendar.localDay(at: (clock ?? WallClock()).now()) } })
        self.config = config
        self.dayCalendar = dayCalendar
        self.onACPower = onACPower
        self.clock = clock ?? WallClock()
        self.diagnosticLog = diagnosticLog ?? DiagnosticLog()
        self.internalState = .initial(staleMs: config.staleTimeoutMs, celebrateDurationMs: config.celebrateDurationMs, workStallTimeoutMs: config.workStallTimeoutMs, approvalTimeoutMs: config.approvalTimeoutMs)
        let language = defaults.string(forKey: DefaultsKey.language) == "ko" ? "ko" : "en"
        self.internalState.buddy.language = language
        self.state = self.internalState.buddy
        if BuddyConfig.recreatedCorruptConfig {
            self.diagnosticLog.log(category: "engine", source: "system", event: "config", detail: "config.json was unreadable; recreated with defaults")
        }
    }

    // MARK: - Lifecycle

    func start() {
        lastSessionActivity = clock.now()
        loadingStore = true
        let stateDir = config.stateDir, now = clock.now(), existing = store
        bootstrap = Task { @MainActor in
            do {
                // Detached startup keeps directory, schema, prune and migration I/O off MainActor.
                self.store = try await Task.detached {
                    let store: any EngineStore = try existing ?? Store(stateDir: stateDir, now: now)
                    try await store.migrate()
                    return store
                }.value
                let tools = try await self.store?.toolPreferences() ?? ToolPreferences()
                self.claimedTools.formUnion(tools.claimed)
                self.mutedTools.formUnion(tools.muted)
                if let memory = try await self.store?.loadMemory() {
                    self.apply(.memoryLoaded(at: self.clock.now(), memory: memory), persistenceResult: true)
                }
                let calendar = self.dayCalendar, clock = self.clock
                self.voice = Voice(runtime: self.voiceRuntime, store: self.store, localDay: { await MainActor.run { calendar.localDay(at: clock.now()) } })
                await self.store?.configureVoice(self.voice, language: self.state.language)
                try await self.refreshGrowth()
                try await self.refreshVoiceContext()
            } catch { self.storeFailure(error) }
            self.loadingStore = false
            let pending = self.deferredEvents; self.deferredEvents.removeAll()
            for event in pending { self.apply(event) }
        }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.needsStaleTicks() { self.triggerStaleTick() }
                self.maintenance()
            }
        }
    }

    /// Whether the 2s tick has anything to expire or recompute. Personality
    /// widens this beyond sessions: transient windows (greet, mood, agent
    /// lease) need their expiry tick, and a circadian-ready memory needs
    /// ticks even while asleep so "expectant" can come and go with the hour.
    private func needsStaleTicks() -> Bool {
        !internalState.sessions.isEmpty
            || state.celebrateUntil != nil
            || state.affectionUntil != nil
            || state.greetUntil != nil
            || internalState.bubbleUntil != nil
            || state.moodUntil != nil
            || state.mood != nil
            || state.agentOverlay != nil
            || state.agentDrawingUntil != nil
            || internalState.memory.circadianReady(at: clock.now())
    }

    func stop() {
        giftVoiceRevision += 1; bubbleVoiceRevision += 1
        giftVoiceTask?.cancel(); bubbleVoiceTask?.cancel(); recapTask?.cancel()
        Task { await extractor.reset() }
        staleTimer?.invalidate()
        staleTimer = nil
        for (_, source) in processWatchers { source.cancel() }
        processWatchers.removeAll()
    }

    func triggerStaleTick() {
        // The reducer exempts supervised sessions from the stale reap, so it
        // must see the current watcher truth before every tick.
        let watched = Set(processWatchers.keys)
        if watched != internalState.watchedSessionIds {
            apply(.processWatchChanged(at: clock.now(), watchedSessionIds: watched))
        }
        apply(.staleTick(at: clock.now()))
    }

    // MARK: - Registration

    func register(output: any OutputProvider) {
        outputs.append(output)
    }

    // MARK: - Session API

    func sessionStarted(sessionId: String, source: String, cwd: String?, hookPid: Int32? = nil) {
        apply(.sessionStarted(at: clock.now(), sessionId: sessionId, source: source, cwd: cwd, project: internalState.sessions[sessionId]?.project ?? ThemeReader.project(cwd: cwd)))
        registerWatcher(sessionId: sessionId, source: source, hookPid: hookPid)
    }

    private func registerWatcher(sessionId: String, source: String, hookPid: Int32?) {
        if let hookPid, processWatchers[sessionId] == nil,
           let appPid = Self.resolveAncestor(from: hookPid) {
            let name = Self.processName(of: appPid) ?? "unknown"
            let shouldWatch = Self.isPlausibleAgentHost(name)
            diagnosticLog.log(
                category: "engine",
                source: source,
                event: "watcher",
                detail: "session=\(sessionId) pid=\(appPid) name=\(name) decision=\(shouldWatch ? "watch" : "skip")"
            )
            if shouldWatch {
                watchProcess(pid: appPid, sessionId: sessionId)
            }
        }
    }

    func sessionEnded(sessionId: String) {
        Task { await extractor.drop(sessionId: sessionId) }
        apply(.sessionEnded(at: clock.now(), sessionId: sessionId))
    }

    func submitRequest(sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?) {
        apply(.requestArrived(at: clock.now(), sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel))
    }

    func clearRequest(sessionId: String) {
        apply(.requestCleared(at: clock.now(), sessionId: sessionId))
    }

    func ingest(_ input: RawHookPayload, hookPid: Int32? = nil) async {
        guard !retiring else { return }
        // Awaiting the extractor yields the main actor. Chain handoffs so an
        // overlapping HTTP result cannot reach the reducer before its call.
        let previous = extractionTail
        let task = Task { @MainActor in
            await previous?.value
            await self.ingestSerial(input, hookPid: hookPid)
        }
        extractionTail = task
        await task.value
    }

    private func ingestSerial(_ input: RawHookPayload, hookPid: Int32?) async {
        await bootstrap?.value
        var payload = input
        payload.timestamp = clock.now()
        lastSessionActivity = payload.timestamp
        let hour = dayCalendar.localHour(at: payload.timestamp)
        let extraction = await extractor.ingest(payload, localHour: hour)
        guard !retiring else { await extractor.drop(sessionId: payload.sessionId); return }
        for event in extraction.events {
            if case .adapterDegraded(_, let source) = event { diagnosticLog.log(category: "hook", source: source, event: "adapterDegraded", detail: "lifecycle-only") }
            if case .sessionEnded = event { sessionEnded(sessionId: payload.sessionId) }
            else {
                apply(event)
                if case .sessionStarted = event, let hookPid {
                    // Identity has already been resolved by the extractor.
                    registerWatcher(sessionId: payload.sessionId, source: payload.source, hookPid: hookPid)
                }
            }
        }
        let facts = extraction.facts
        if !facts.isEmpty { factsRevision += 1 }
        let project = internalState.sessions[payload.sessionId]?.project ?? ThemeReader.project(cwd: payload.cwd)
        let day = localDay(at: payload.timestamp)
        enqueue { store in
            try await store.appendFacts(facts.map { StoredFact(fact: $0, sessionId: payload.sessionId, project: project, at: payload.timestamp, day: day) })
            let tokens = facts.compactMap { fact -> LedgerRow? in
                if case .tokens(let output) = fact { return LedgerRow(at: payload.timestamp, source: .tokens, amount: output, sessionId: payload.sessionId, day: day) }
                return nil
            }
            if !tokens.isEmpty { let snapshot = try await store.award(tokens, active: false, at: payload.timestamp, localDay: day); if let snapshot { try await self.refreshGrowth(snapshot: snapshot) }; try await self.refreshVoiceContext() }
        }
        let runner = extraction.goalRunner ?? ""
        diagnosticLog.log(category: "hook", source: payload.source, event: payload.eventName.isEmpty ? payload.kind.rawValue : payload.eventName, detail: payload.toolName + (runner.isEmpty ? "" : " " + runner))
    }

    func turnStarted(sessionId: String, source: String) {
        apply(.turnStarted(at: clock.now(), sessionId: sessionId, source: source))
    }

    func toolCalled(sessionId: String, source: String, tool: String, hint: String, goal: String? = nil) {
        apply(.toolCalled(at: clock.now(), sessionId: sessionId, source: source, tool: tool, hint: hint, goal: goal))
    }

    func toolResulted(sessionId: String, source: String, tool: String, ok: Bool?, durationMs: Double? = nil) {
        apply(.toolResulted(at: clock.now(), sessionId: sessionId, source: source, tool: tool, ok: ok, durationMs: durationMs))
    }

    func turnEnded(sessionId: String, source: String, outcome: TurnOutcome) {
        apply(.turnEnded(at: clock.now(), sessionId: sessionId, source: source, outcome: outcome))
    }

    var deviceFrameTime: Double { clock.now() }

    func devicePostureArrived(_ posture: DevicePosture) {
        apply(.devicePostureChanged(at: clock.now(), posture: posture))
    }

    func deviceBatteryArrived(_ battery: DeviceBattery) {
        apply(.deviceBatteryChanged(at: clock.now(), battery: battery))
    }

    func deviceMotionArrived(_ motion: DeviceMotion) {
        diagnosticLog.log(category: "device", source: "esp32", event: "motion", detail: motion.rawValue)
    }

    func handleDeviceCommand(_ command: DeviceCommand) {
        switch command {
        case let .decision(id, decision):
            // Match the capped wire ID back to its full request ID. Refuse
            // ambiguous prefixes rather than resolving a different approval.
            let matches = Set(internalState.sessions.values.compactMap { $0.prompt?.id }
                .filter { $0 == id || $0.prefix(utf8Bytes: 23) == id })
            guard matches.count == 1, let requestId = matches.first else {
                diagnosticLog.log(category: "device", source: "esp32", event: "unknownDecision", detail: id)
                return
            }
            if !resolveApproval(requestId: requestId, decision: decision) {
                diagnosticLog.log(category: "device", source: "esp32", event: "unknownDecision", detail: id)
            }
        case .quick: NotificationManager.shared.postQuickCommand(quickCommand, language: state.language)
        case .collect: collectArrived()
        case .boop: boop()
        case .posture(let posture): devicePostureArrived(posture)
        case .battery(let battery): deviceBatteryArrived(battery)
        case .motion(let motion): deviceMotionArrived(motion)
        case .focus(let on): focusToggled(on: on)
        case .ack, .status: break
        }
    }

    func firstCheer() {
        guard !defaults.bool(forKey: DefaultsKey.firstCheerShown) else { return }
        defaults.set(true, forKey: DefaultsKey.firstCheerShown)
        apply(.onboardingCheer(at: clock.now(), line: BuddyCopy.phase7("firstOne", language: state.language)))
    }
    var quickCommand: String { defaults.string(forKey: DefaultsKey.quickCommand) ?? "continue" }
    func setQuickCommand(_ text: String) { defaults.set(String(text.prefix(1000)), forKey: DefaultsKey.quickCommand) }
    func dismissTeach(tool: String) async {
        do { try await store?.muteTool(tool); mutedTools.insert(tool); if teachTool == tool { teachTool = nil } }
        catch { storeFailure(error) }
    }
    static func preview(state: BuddyState, defaults: UserDefaults) -> BuddyEngine {
        let engine = BuddyEngine(defaults: defaults)
        engine.internalState.buddy = state; engine.state = state
        return engine
    }
    func retire(sendToDevice: () -> Void = {}) async throws {
        guard !retiring else { return }
        retiring = true
        await finishPendingWork()
        defer { retiring = false }
        giftVoiceTask?.cancel(); bubbleVoiceTask?.cancel(); recapTask?.cancel()
        await recapTask?.value
        while activeRecaps > 0 { try? await Task.sleep(for: .milliseconds(10)) }
        giftVoiceRevision += 1; bubbleVoiceRevision += 1
        try await store?.retire()
        resolveAllPendingApprovals(decision: .passthrough)
        sendToDevice()
        let previous = state
        for id in Array(internalState.sessions.keys) { cancelWatcher(sessionId: id); await extractor.drop(sessionId: id) }
        internalState = .initial(staleMs: config.staleTimeoutMs, celebrateDurationMs: config.celebrateDurationMs, workStallTimeoutMs: config.workStallTimeoutMs, approvalTimeoutMs: config.approvalTimeoutMs)
        internalState.buddy.language = previous.language
        state = internalState.buddy
        cachedProfile = []; cachedTraits = [:]; contextLoaded = false; contextLoad = nil
        claimedTools = []; mutedTools = []
        teachTool = nil; recappedDays = []; recapFactsCache = nil; recapAttempt = nil; stopHourCache = nil
        defaults.removeObject(forKey: DefaultsKey.buddyName)
        defaults.removeObject(forKey: DefaultsKey.buddyNameLocked)
        defaults.removeObject(forKey: DefaultsKey.firstCheerShown)
        defaults.set(false, forKey: DefaultsKey.setupCompleted)
        defaults.removeObject(forKey: DefaultsKey.onboardingStep)
        refreshSettings()
        for output in outputs { output.stateDidChange(prev: previous, next: state) }
    }
    var focusHours: (enabled: Bool, start: Int, end: Int) {
        (defaults.bool(forKey: DefaultsKey.focusHoursEnabled), defaults.object(forKey: DefaultsKey.focusStart) as? Int ?? 9, defaults.object(forKey: DefaultsKey.focusEnd) as? Int ?? 17)
    }
    func setFocusHours(enabled: Bool, start: Int, end: Int) {
        defaults.set(enabled, forKey: DefaultsKey.focusHoursEnabled)
        defaults.set(max(0, min(23, start)), forKey: DefaultsKey.focusStart)
        defaults.set(max(0, min(23, end)), forKey: DefaultsKey.focusEnd)
        updateFocusHours()
    }
    var soundVolume: Int { SoundSettings.volume(defaults: defaults, respectingMute: false) }
    var voiceSetting: String { defaults.string(forKey: DefaultsKey.voiceRuntime) ?? "auto" }
    func setSoundVolume(_ volume: Int) { defaults.set(max(0, min(3, volume)), forKey: DefaultsKey.soundVolume) }
    func boolSetting(_ key: String, fallback: Bool = false) -> Bool { _ = settingsRevision; return defaults.object(forKey: key) as? Bool ?? fallback }
    func setBoolSetting(_ key: String, _ value: Bool) { defaults.set(value, forKey: key); settingsRevision += 1 }
    var buddyName: String { _ = settingsRevision; return defaults.string(forKey: DefaultsKey.buddyName) ?? "" }
    var pairedPeripheral: String? { _ = settingsRevision; return defaults.string(forKey: DefaultsKey.esp32PeripheralUUID) }
    func setPairedPeripheral(_ uuid: UUID?) {
        defaults.set(uuid?.uuidString, forKey: DefaultsKey.esp32PeripheralUUID)
        settingsRevision += 1
    }
    func restartOnboarding() {
        defaults.removeObject(forKey: DefaultsKey.onboardingStep)
        setBoolSetting(DefaultsKey.setupCompleted, false)
    }
    func setApprovalMode(_ enabled: Bool) {
        setBoolSetting(DefaultsKey.approvalMode, enabled)
        BuddyConfig.setApprovalMode(enabled)
        if !enabled { resolveAllPendingApprovals(decision: .passthrough) }
    }
    func updateFocusHours() {
        guard defaults.bool(forKey: DefaultsKey.focusHoursEnabled) else {
            if scheduledFocus == true { focusToggled(on: false) }; scheduledFocus = nil; return
        }
        let hour = dayCalendar.localHour(at: clock.now())
        let start = (defaults.object(forKey: DefaultsKey.focusStart) as? Int ?? 9), end = (defaults.object(forKey: DefaultsKey.focusEnd) as? Int ?? 17)
        let active = start == end || (start < end ? hour >= start && hour < end : hour >= start || hour < end)
        if scheduledFocus != active { scheduledFocus = active; focusToggled(on: active) }
    }

    func focusToggled(on: Bool) {
        apply(.focusToggled(at: clock.now(), on: on))
    }

    func collectArrived() {
        apply(.collectArrived(at: clock.now()))
    }

    func nudgeDismissed() {
        apply(.nudgeDismissed(at: clock.now()))
    }

    func activitySignal(sessionId: String, source: String, signal: ActivitySignalKind, tool: String? = nil, hint: String? = nil) {
        apply(.activitySignal(at: clock.now(), sessionId: sessionId, source: source, signal: signal, tool: tool, hint: hint))
    }

    func dismissReview() {
        apply(.reviewDismissed(at: clock.now()))
    }

    func refreshSettings() { settingsRevision += 1 }

    func setSpecies(_ species: String) {
        apply(.speciesChanged(at: clock.now(), species: species))
    }

    /// Physical affection from the device (button boop or a petting stroke).
    /// The follow-up tick is what flips the pet back out of heart-eyes right
    /// when the affection window lapses — the 2s stale timer alone would let
    /// the heart linger up to 2s past it.
    func boop() {
        apply(.boopArrived(at: clock.now()))
        Timer.scheduledTimer(withTimeInterval: boopAffectionMs / 1000 + 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerStaleTick() }
        }
    }

    // MARK: - Agent Expression API (System E)

    /// What happened to an agent's expression attempt — also the source of the
    /// tool-result feedback strings, which teach pacing better than any
    /// upfront instruction.
    enum AgentExpressOutcome: Equatable {
        case shown
        /// An approval/prompt is pending somewhere (S1). Deferred, not queued.
        case suppressed
        case rateLimited(retryAfterMs: Double)
    }

    var petMemory: PetMemory { internalState.memory }

    /// Resolve which session an MCP call belongs to: the most recently active
    /// session from that agent. Static per-agent MCP configs can't carry a
    /// per-session id, and a self-reported session parameter would be
    /// spoofable (S7) — so identity comes from the connection and the mapping
    /// stays server-side.
    private func mostRecentSession(source: String) -> String? {
        internalState.sessions
            .filter { $0.value.source == source }
            .max(by: { $0.value.lastActivityAt < $1.value.lastActivityAt })?
            .key
    }

    /// Agent difficulty self-report. Returns false when the agent has no live
    /// session to attach it to.
    @discardableResult
    func reportEffort(agentId: String, level: EffortTier) -> Bool {
        guard let sessionId = mostRecentSession(source: agentId) else { return false }
        apply(.effortReported(at: clock.now(), sessionId: sessionId, level: level))
        return true
    }

    func agentIntroduce(agentId: String, color: String?, signatureEmote: String?, greeting: String?) {
        apply(.agentIntroduced(at: clock.now(), agentId: agentId, color: color, signatureEmote: signatureEmote, greeting: greeting))
    }

    /// Validation of enums/caps happened at the MCP layer (S4/S5); this
    /// enforces suppression (S1) and the per-agent rate floor (S6). The
    /// reducer re-checks S1 — a prompt can land between check and apply.
    func agentExpress(agentId: String, emotion: String, intensity: String, motion: String?, say: String?, delivery: String?) -> AgentExpressOutcome {
        let now = clock.now()
        if internalState.sessions.values.contains(where: { $0.prompt != nil }) {
            return .suppressed
        }
        if let last = lastExpressAt[agentId], now - last < PetTuning.agentExpressMinGapMs {
            return .rateLimited(retryAfterMs: PetTuning.agentExpressMinGapMs - (now - last))
        }
        lastExpressAt[agentId] = now
        apply(.agentExpressed(at: now, agentId: agentId, emotion: emotion, intensity: intensity, motion: motion, say: say, delivery: delivery))
        return .shown
    }

    enum AgentDrawOutcome: Equatable {
        /// The pet is holding the drawing up now.
        case shown
        /// Kept as a keepsake but not displayed — an approval is pending
        /// (S1). A parting gift is never lost to timing.
        case kept
        case rateLimited(retryAfterMs: Double)
    }

    /// Row shape and palette digits were validated at the MCP layer; this
    /// enforces the one-per-visit floor and reports whether the drawing was
    /// displayed or quietly shelved.
    func agentDraw(agentId: String, rows: [String], caption: String?) -> AgentDrawOutcome {
        let now = clock.now()
        if let last = lastDrewAt[agentId], now - last < PetTuning.agentDrawMinGapMs {
            return .rateLimited(retryAfterMs: PetTuning.agentDrawMinGapMs - (now - last))
        }
        lastDrewAt[agentId] = now
        let promptPending = internalState.sessions.values.contains { $0.prompt != nil }
        apply(.agentDrew(at: now, agentId: agentId, rows: rows, caption: caption))
        return promptPending ? .kept : .shown
    }

    // MARK: - Approval API

    func submitApproval(sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?, stakes: Stakes? = nil, gloss: String? = nil) async -> ApprovalDecision {
        apply(.approvalArrived(at: clock.now(), sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source))
        if let stakes, let gloss { apply(.requestDescribed(at: clock.now(), sessionId: sessionId, stakes: stakes, gloss: gloss)) }
        return await withCheckedContinuation { continuation in
            pendingApprovals[requestId] = continuation
        }
    }

    /// Returns false when nothing was waiting on this id, so the caller can
    /// surface the mismatch. A decision for an unknown id used to vanish here
    /// without a trace, which is how a device-truncated id (see makeRequestId
    /// in HookServer) presented as a dead button instead of an id mismatch:
    /// the card sat on "yes!" forever and the hook stayed blocked.
    @discardableResult
    func resolveApproval(requestId: String, decision: ApprovalDecision) -> Bool {
        let continuation = pendingApprovals.removeValue(forKey: requestId)
        // Clear the card even when nobody is waiting on it any more.
        //
        // This used to return early when the continuation was gone, which left
        // the prompt sitting in state with no way to dismiss it: the device
        // showed the card, the crown sent a decision, the decision resolved
        // nothing, and ten seconds later the firmware re-offered the very same
        // request — forever. Answering something must always make it go away,
        // whether or not a hook is still listening. The return value still
        // reports whether a caller was actually unblocked.
        if let sessionId = findSessionForApproval(requestId) {
            apply(.approvalResolved(at: clock.now(), sessionId: sessionId, requestId: requestId, decision: decision))
        }
        continuation?.resume(returning: decision)
        return continuation != nil
    }

    /// The hook blocked on this approval is gone — its HTTP request was
    /// cancelled out from under us (client hung up, task cancelled). Withdraw
    /// the card and unblock the (dead) waiter so the request task can unwind.
    func abandonApproval(sessionId: String, requestId: String) {
        apply(.approvalAbandoned(at: clock.now(), sessionId: sessionId, requestId: requestId))
        // The prompt's disappearance above normally resumes the waiter via the
        // disappeared-prompt sweep in apply(). Belt and braces: a cancelled
        // request must always finish, even if its prompt was already gone.
        if let continuation = pendingApprovals.removeValue(forKey: requestId) {
            continuation.resume(returning: .passthrough)
        }
    }

    func resolveAllPendingApprovals(decision: ApprovalDecision) {
        let approvals = pendingApprovals
        pendingApprovals.removeAll()
        for (requestId, continuation) in approvals {
            if let sessionId = findSessionForApproval(requestId) {
                apply(.approvalResolved(at: clock.now(), sessionId: sessionId, requestId: requestId, decision: decision))
            }
            continuation.resume(returning: decision)
        }
    }

    private func findSessionForApproval(_ requestId: String) -> String? {
        internalState.sessions.first(where: { $0.value.prompt?.id == requestId })?.key
    }

    // MARK: - Process Monitoring

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size > 0 else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        guard ppid > 1 else { return nil }
        return ppid
    }

    private static func processName(of pid: pid_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            let name = stringFromNullTerminatedCString(nameBuffer)
            if !name.isEmpty { return name }
        }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let path = stringFromNullTerminatedCString(pathBuffer)
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }

        return nil
    }

    private static func stringFromNullTerminatedCString(_ buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isPlausibleAgentHost(_ processName: String) -> Bool {
        let lowered = processName.lowercased()
        return ["claude", "node", "cursor", "codex", "bun", "electron"].contains { lowered.contains($0) }
    }

    /// Walk up from hook script PID → intermediate shell → app (grandparent).
    private static func resolveAncestor(from hookPid: pid_t) -> pid_t? {
        guard let shell = parentPID(of: hookPid),
              let app = parentPID(of: shell) else { return nil }
        return app
    }

    private func watchProcess(pid: Int32, sessionId: String) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // `self!` here would trap: the line above already concedes it
                // can be nil, and a resumed DispatchSource outlives us.
                guard let self else { return }
                self.cancelWatcher(sessionId: sessionId)
                self.apply(.sessionEnded(at: self.clock.now(), sessionId: sessionId))
            }
        }
        processWatchers[sessionId] = source
        source.resume()
    }

    private func cancelWatcher(sessionId: String) {
        processWatchers.removeValue(forKey: sessionId)?.cancel()
    }

    // MARK: - Internal

    private func apply(_ event: BuddyEvent, persistenceResult: Bool = false) {
        guard !retiring else { return }
        if loadingStore && !persistenceResult { deferredEvents.append(event); return }
        if case .toolCalled(_, _, _, let tool, _, _) = event, !mutedTools.contains(tool), claimedTools.insert(tool).inserted {
            enqueue { store in
                if try await store.claimTool(tool), !self.mutedTools.contains(tool), TeachCatalog.line(tool: tool, language: self.state.language) != nil {
                    self.teachTool = tool
                }
            }
        }
        let prev = state
        let previousPromptIds = Self.promptIds(in: internalState)
        var next = reduce(internalState, event, localHour: dayCalendar.localHour(at: event.at))
        let awards = next.pendingAwards, facts = next.pendingFacts
        next.pendingAwards = []; next.pendingFacts = []
        if !persistenceResult { persist(awards: awards, facts: facts) }
        guard next != internalState else { return }
        let removedIds = Set(internalState.sessions.keys).subtracting(next.sessions.keys)
        let disappearedPromptIds = previousPromptIds.subtracting(Self.promptIds(in: next))
        let memoryChanged = next.memory != internalState.memory
        internalState = next
        state = next.buddy
        if memoryChanged {
            stopHourCache = nil
            if !persistenceResult {
                // SQLite is the sole persistence path; an unstarted engine without a store is memory-only.
                enqueue { try await $0.saveMemory(next.memory) }
            }
        }
        for id in removedIds {
            Task { await extractor.drop(sessionId: id) }
            cancelWatcher(sessionId: id)
        }
        for requestId in disappearedPromptIds {
            if let continuation = pendingApprovals.removeValue(forKey: requestId) {
                continuation.resume(returning: .passthrough)
            }
        }
        for output in outputs {
            output.stateDidChange(prev: prev, next: state)
        }
        scheduleVoice(previous: prev, event: event)
        diagnosticLog.log(category: "engine", source: "system", event: event.name, detail: "pet=\(state.pet.state.rawValue) sessions=\(state.sessions.total)")
    }


    // All database operations share one queue, including HTTP reads and startup.
    private func enqueue(_ work: @escaping @MainActor @Sendable (any EngineStore) async throws -> Void) {
        guard let store else { return }
        let previous = storeTail
        storeTail = Task { @MainActor in
            await previous?.value
            do { try await work(store) }
            catch { self.storeFailure(error) }
        }
    }
    func finishPendingWork() async { await extractionTail?.value; await flushStore(); await giftVoiceTask?.value; await bubbleVoiceTask?.value }
    func flushStore() async { await bootstrap?.value; await storeTail?.value }
    private func storeFailure(_ error: Error) {
        diagnosticLog.log(category: "store", source: "system", event: "error", detail: String(describing: error))
    }
    private func localDay(at: Double) -> String { dayCalendar.localDay(at: at) }
    private func refreshGrowth(snapshot: GrowthSnapshot? = nil) async throws {
        guard let store else { return }
        let at = clock.now()
        let growth: GrowthSnapshot
        if let snapshot { growth = snapshot }
        else { growth = try await store.growth(localDay: localDay(at: at), at: at) }
        let cosmetic = try await store.cosmetic()
        apply(.growthUpdated(at: at, growth: growth, cosmetic: cosmetic), persistenceResult: true)
    }
    private func persist(awards: [XPAward], facts: [PendingFact]) {
        guard !awards.isEmpty || !facts.isEmpty else { return }
        if !facts.isEmpty { factsRevision += 1 }
        let storedFacts = facts.map { StoredFact(fact: $0.fact, sessionId: $0.sessionId, project: $0.project, at: $0.at, day: localDay(at: $0.at)) }
        for award in awards where award.active && !award.sessionId.isEmpty { lastSessionActivity = award.at }
        enqueue { store in
            if !storedFacts.isEmpty { try await store.appendFacts(storedFacts) }
            for award in awards {
                let day = self.localDay(at: award.at)
                if let cheer = award.cheer { try await store.recordCheer(cheer) }
                if award.collected || award.greet { try await store.bond(collected: award.collected, greetAfterAbsence: award.greet, localDay: day) }
                let rows = award.sources.map { LedgerRow(at: award.at, source: $0, sessionId: award.sessionId, day: day) }
                if award.active || !rows.isEmpty {
                    let snapshot = try await store.award(rows, active: award.active, at: award.at, localDay: day)
                    if let snapshot { try await self.refreshGrowth(snapshot: snapshot) }
                }
            }
            if !awards.isEmpty { try await self.refreshVoiceContext() }
        }
    }
    private var reflectedDays: Set<String> = []
    private var maintenanceDay: String?
    func maintenance() {
        updateFocusHours()
        let now = clock.now(), day = localDay(at: clock.now())
        if maintenanceDay != day {
            maintenanceDay = day
            enqueue { try await $0.prune(now: now, localDay: day) }
        }
        if dayCalendar.localHour(at: now) >= usualStopHour(at: now),
           [.idle, .asleep].contains(state.creature.state), !recappedDays.contains(day), recapTask == nil,
           recapAttempt?.day != day || now - (recapAttempt?.at ?? 0) >= 300_000 {
            recapTask = Task { [weak self] in
                guard let self else { return }
                defer { self.recapTask = nil }
                do { _ = try await self.makeRecap(force: false) } catch { self.storeFailure(error) }
            }
        }
        if now - (lastSessionActivity ?? now) >= 1_200_000 && onACPower() {
            let target = dayCalendar.previousDay(at: now)
            if reflectedDays.insert(target).inserted {
                enqueue {
                    do { await $0.configureVoice(self.voice, language: self.state.language); _ = try await $0.reflect(localDay: target, at: now); try await self.refreshVoiceContext(); await self.extractor.clearClosingLines() }
                    catch { self.reflectedDays.remove(target); throw error }
                }
            }
        }
    }
    func storedFacts() async throws -> [StoredFact] { await flushStore(); return try await store?.facts() ?? [] }
    func inventory() async throws -> [InventoryItem] { await flushStore(); return try await store?.inventory() ?? [] }
    func profileLines() async throws -> [ProfileLine] { await flushStore(); try await ensureVoiceContext(); return cachedProfile }
    func clearProfile(id: Int? = nil) async throws {
        await flushStore()
        if let id { try await store?.deleteProfileLine(id) } else { try await store?.clearProfile() }
        try await refreshVoiceContext()
    }
    func reflect() async throws -> [ProfileLine] {
        await flushStore()
        await store?.configureVoice(voice, language: state.language)
        let lines = try await store?.reflect(localDay: localDay(at: clock.now()), at: clock.now()) ?? []
        try await refreshVoiceContext()
        await extractor.clearClosingLines()
        return lines
    }
    func equip(_ cosmetic: EquippedCosmetic) async throws {
        await flushStore(); try await store?.equip(cosmetic); try await refreshGrowth()
    }

    private func refreshVoiceContext() async throws {
        cachedProfile = try await store?.profile() ?? []
        cachedTraits = try await store?.traits() ?? [:]
        contextLoaded = true
    }
    private func ensureVoiceContext() async throws {
        if contextLoaded { return }
        if let contextLoad { try await contextLoad.value; return }
        let task = Task { try await self.refreshVoiceContext() }
        contextLoad = task
        defer { contextLoad = nil }
        try await task.value
    }
    func setLanguage(_ language: String) async {
        guard ["en", "ko"].contains(language) else { return }
        await flushStore()
        defaults.set(language, forKey: DefaultsKey.language)
        giftVoiceRevision += 1; bubbleVoiceRevision += 1
        giftVoiceTask?.cancel(); bubbleVoiceTask?.cancel(); recapTask?.cancel()
        apply(.languageChanged(at: clock.now(), language: language))
        await store?.configureVoice(voice, language: language)
    }
    func setVoiceRuntime(_ setting: String) async {
        guard ["auto", "off"].contains(setting) else { return }
        await flushStore()
        defaults.set(setting, forKey: DefaultsKey.voiceRuntime)
        giftVoiceRevision += 1; bubbleVoiceRevision += 1
        giftVoiceTask?.cancel(); bubbleVoiceTask?.cancel(); recapTask?.cancel()
        voiceRuntime = VoiceRuntimes.make(setting: setting)
        let calendar = dayCalendar, clock = clock
        voice = Voice(runtime: voiceRuntime, store: store, localDay: { await MainActor.run { calendar.localDay(at: clock.now()) } })
        await store?.configureVoice(voice, language: state.language)
    }
    private func voiceRequest(_ occasion: Occasion, cap: Int) async -> VoiceRequest {
        await flushStore()
        try? await ensureVoiceContext()
        let source = state.lastCompleted?.source
        let agent = source.flatMap { ["codex", "claude-code", "cursor"].contains($0) ? $0 : nil }
        return VoiceRequest(occasion: occasion, profile: Array(cachedProfile.prefix(3).map(\.line)), traits: cachedTraits,
            agent: agent, timeOfDay: TimeOfDay(hour: dayCalendar.localHour(at: clock.now())), language: state.language, byteCap: cap)
    }
    private func scheduleVoice(previous: BuddyState, event: BuddyEvent) {
        switch event { case .onboardingCheer, .voiceLine, .recapReady, .growthUpdated, .languageChanged: return; default: break }
        // Invalidate transient text on a new interaction; an old model reply must not cover a card.
        if previous.creature.state != state.creature.state || previous.creature.card?.id != state.creature.card?.id {
            bubbleVoiceRevision += 1; bubbleVoiceTask?.cancel()
        }
        if previous.creature.gift && !state.creature.gift { giftVoiceRevision += 1; giftVoiceTask?.cancel() }
        if state.lastCompletionAt != previous.lastCompletionAt, state.lastCompletionAt != nil {
            requestVoice(.cheer(state.creature.moment, internalState.doneSize ?? .hop, state.creature.moment?.facts["runner"]), kind: .gift)
        }
        if let kind = state.creature.uhoh, kind != previous.creature.uhoh || state.creature.moment != previous.creature.moment {
            requestVoice(.uhoh(kind, kind == .hungry && state.creature.moment?.kind == .nthRateLimit ? state.creature.moment : nil), kind: .bubble)
        } else if state.greetUntil != previous.greetUntil, state.greetUntil != nil, state.creature.card == nil {
            requestVoice(.greet(state.greetLevel ?? 1), kind: .bubble)
        }
    }
    private func requestVoice(_ occasion: Occasion, kind: VoiceLineKind) {
        if kind == .gift { giftVoiceRevision += 1; giftVoiceTask?.cancel() }
        else { bubbleVoiceRevision += 1; bubbleVoiceTask?.cancel() }
        let revision = kind == .gift ? giftVoiceRevision : bubbleVoiceRevision
        let task = Task { [weak self] in
            guard let self else { return }
            let request = await self.voiceRequest(occasion, cap: kind == .gift ? VoiceCap.gift.rawValue : VoiceCap.bubble.rawValue)
            guard !Task.isCancelled else { return }
            let line = await self.voice.line(for: request)
            guard !Task.isCancelled, !line.text.isEmpty,
                  revision == (kind == .gift ? self.giftVoiceRevision : self.bubbleVoiceRevision),
                  kind == .gift || self.state.creature.card == nil else { return }
            self.apply(.voiceLine(at: self.clock.now(), kind: kind, text: line.text))
        }
        if kind == .gift { giftVoiceTask = task } else { bubbleVoiceTask = task }
    }
    /// The legacy histogram is UTC. Convert bins before finding the end of the
    /// owner's evening activity; sparse/unknown histories use 18:00 local.
    func usualStopHour(at: Double) -> Int {
        let day = localDay(at: at)
        if let cached = stopHourCache, cached.day == day { return cached.hour }
        let hour = computeUsualStopHour(at: at)
        stopHourCache = (day, hour)
        return hour
    }
    private func computeUsualStopHour(at: Double) -> Int {
        let memory = internalState.memory
        guard memory.circadianReady(at: at) else { return 18 }
        let utcHour = PetMemory.utcHour(ofMs: at)
        let offset = dayCalendar.localHour(at: at) - utcHour
        let active = Set((0..<24).filter { memory.isTypicalHour($0) }.map { ($0 + offset + 24) % 24 })
        // Find the end of the longest typical activity block, including one
        // crossing midnight. A histogram has no explicit sign-off event.
        let stops = (0..<24).filter { !active.contains($0) && active.contains(($0 + 23) % 24) }
        func runLength(endingAt hour: Int) -> Int {
            var length = 0
            while length < 24 && active.contains((hour - length - 1 + 48) % 24) { length += 1 }
            return length
        }
        return stops.sorted {
            let a = runLength(endingAt: $0), b = runLength(endingAt: $1)
            return a == b ? abs($0 - 18) < abs($1 - 18) : a > b
        }.first ?? 18
    }
    func makeRecap(force: Bool = true) async throws -> Recap? {
        guard !retiring else { return nil }
        activeRecaps += 1
        defer { activeRecaps -= 1 }
        await flushStore()
        let day = localDay(at: clock.now())
        let revision = factsRevision
        recapAttempt = (day, revision, clock.now())
        let savedDay = try await store?.recapDay()
        if !force, recappedDays.contains(day) || savedDay == day { recappedDays.insert(day); return state.recap }
        let facts: [StoredFact]
        if let cached = recapFactsCache, cached.day == day, cached.revision == revision { facts = cached.facts }
        else {
            facts = try await store?.facts(localDay: day) ?? []
            recapFactsCache = (day, revision, facts)
        }
        guard force || !facts.isEmpty else { return nil }
        let recapFacts = RecapFacts.build(facts)
        let request = await voiceRequest(.recap(recapFacts), cap: VoiceCap.bubble.rawValue)
        var appRequest = request; appRequest.byteCap = VoiceCap.paragraph.rawValue
        async let device = voice.line(for: request)
        async let paragraph = voice.line(for: appRequest)
        let recap = await Recap(line: device.text, paragraph: paragraph.text, turns: recapFacts.turns, tasks: recapFacts.tasks, biggest: recapFacts.biggestMoment?.rawValue ?? "—")
        guard !Task.isCancelled, !retiring else { return nil }
        recappedDays.insert(day); try await store?.markRecapDay(day)
        // A request may arrive during generation: retain the app recap, but do not cover it.
        apply(.recapReady(at: clock.now(), recap: recap))
        return recap
    }

    private static func promptIds(in state: InternalState) -> Set<String> {
        Set(state.sessions.values.compactMap { $0.prompt?.id })
    }
}
