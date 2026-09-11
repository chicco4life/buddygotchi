import Darwin
import Foundation
import Observation

@Observable
@MainActor
final class BuddyEngine {
    private(set) var state: BuddyState = .initial
    var popoverVisible = false
    private var settingsRevision = 0
    private var retiring = false
    let diagnosticLog: DiagnosticLog
    let extractor = Extractor()
    private var extractionTail: Task<Void, Never>?
    private var store: (any EngineStore)?
    private var storeTail: Task<Void, Never>?
    private var voice: Voice
    private var voiceRuntime: any VoiceRuntime
    private let defaults: UserDefaults
    private var cachedProfile: [ProfileLine] = []
    private var contextLoaded = false
    private var contextLoad: Task<Void, Error>?
    private let transientVoice: BehaviorTasks
    private var workIntents: [String: WorkIntent] = [:]
    private var workContext = WorkContext()
    private var workRevision = 0
    private var previousScope: String?
    private var recentRemarks: [String] = []
    private var voiceStopped = false
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
    init(config: BuddyConfig = .default, clock: (any Clock)? = nil, diagnosticLog: DiagnosticLog? = nil, store: (any EngineStore)? = nil, dayCalendar: any DayCalendar = LocalDayCalendar(), onACPower: @escaping @Sendable () -> Bool = { PowerObserver.onACPower() }, voiceRuntime: (any VoiceRuntime)? = nil, defaults: UserDefaults = .standard, behaviorDebounceMs: UInt64 = 2000) {
        self.transientVoice = BehaviorTasks(debounceMs: behaviorDebounceMs)
        self.store = store
        self.defaults = defaults
        let runtime = voiceRuntime ?? VoiceRuntimes.make(setting: "auto")
        self.voiceRuntime = runtime
        self.voice = Voice(runtime: runtime, guide: .init(overrideURL: URL(fileURLWithPath: config.stateDir).appendingPathComponent("BEHAVIOR.md")), store: store, localDay: { await MainActor.run { dayCalendar.localDay(at: (clock ?? WallClock()).now()) } })
        self.config = config
        self.dayCalendar = dayCalendar
        self.onACPower = onACPower
        self.clock = clock ?? WallClock()
        self.diagnosticLog = diagnosticLog ?? DiagnosticLog()
        self.internalState = .initial(staleMs: config.staleTimeoutMs, celebrateDurationMs: config.celebrateDurationMs, approvalTimeoutMs: config.approvalTimeoutMs)
        let language = defaults.string(forKey: DefaultsKey.language) == "ko" ? "ko" : "en"
        self.internalState.buddy.language = language
        self.internalState.buddy.creature.focus = !(defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true)
        self.state = self.internalState.buddy
        if BuddyConfig.recreatedCorruptConfig {
            self.diagnosticLog.log(category: "engine", source: "system", event: "config", detail: "config.json was unreadable; recreated with defaults")
        }
    }


    // MARK: - Lifecycle

    func start() {
        voiceStopped = false
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
                if let memory = try await self.store?.loadMemory() {
                    self.apply(.memoryLoaded(at: self.clock.now(), memory: memory), persistenceResult: true)
                }
                let calendar = self.dayCalendar, clock = self.clock
                self.voice = Voice(runtime: self.voiceRuntime, guide: .init(overrideURL: URL(fileURLWithPath: self.config.stateDir).appendingPathComponent("BEHAVIOR.md")), store: self.store, localDay: { await MainActor.run { calendar.localDay(at: clock.now()) } })
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

    /// Tick only while session or transient presentation timers need it.
    private func needsStaleTicks() -> Bool {
        !internalState.sessions.isEmpty
            || state.celebrateUntil != nil
            || state.affectionUntil != nil
            || state.greetUntil != nil
            || internalState.bubbleUntil != nil
    }

    func stop() {
        voiceStopped = true
        cancelVoiceGeneration()
        workIntents.removeAll(); workContext = WorkContext(); previousScope = nil; recentRemarks = []
        apply(.workScopeChanged(at: clock.now(), text: nil))
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
        // A watched idle session can outlive the reducer's last visual change.
        updateWorkContext()
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
        guard !retiring, !voiceStopped else { return }
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
        guard !retiring, !voiceStopped else { await extractor.drop(sessionId: payload.sessionId); return }
        if let project = extraction.workProject {
            var intent = workIntents[payload.sessionId] ?? WorkIntent(project: project)
            intent.project = project
            if payload.kind == .turnStart { intent.receive(payload.promptText) }
            workIntents[payload.sessionId] = intent
        }
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
        updateWorkContext()
        let facts = extraction.facts
        let project = internalState.sessions[payload.sessionId]?.project ?? ThemeReader.project(cwd: payload.cwd)
        let day = localDay(at: payload.timestamp)
        enqueue { store in
            try await store.appendFacts(facts.map { StoredFact(fact: $0, sessionId: payload.sessionId, project: project, at: payload.timestamp, day: day) })

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
        case .decision: break // Retired wire command; never decides an editor request.
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
        apply(.onboardingCheer(at: clock.now()))
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
        cancelVoiceGeneration()
        try await store?.retire()
        resolveAllPendingApprovals(decision: .passthrough)
        sendToDevice()
        let previous = state
        for id in Array(internalState.sessions.keys) { cancelWatcher(sessionId: id); await extractor.drop(sessionId: id) }
        internalState = .initial(staleMs: config.staleTimeoutMs, celebrateDurationMs: config.celebrateDurationMs, approvalTimeoutMs: config.approvalTimeoutMs)
        internalState.buddy.language = previous.language
        state = internalState.buddy
        workIntents = [:]; workContext = WorkContext(); previousScope = nil; recentRemarks = []
        cachedProfile = []; contextLoaded = false; contextLoad = nil
        defaults.removeObject(forKey: DefaultsKey.buddyName)
        defaults.removeObject(forKey: DefaultsKey.buddyNameLocked)
        defaults.removeObject(forKey: DefaultsKey.firstCheerShown)
        defaults.set(false, forKey: DefaultsKey.setupCompleted)
        defaults.removeObject(forKey: DefaultsKey.onboardingStep)
        refreshSettings()
        for output in outputs { output.stateDidChange(prev: previous, next: state) }
    }
    var preferences: UserDefaults { defaults }
    var quietMode: Bool { !boolSetting(DefaultsKey.soundsEnabled, fallback: true) }
    func setQuietMode(_ on: Bool) {
        defaults.set(!on, forKey: DefaultsKey.soundsEnabled)
        settingsRevision += 1
        // Keep the v2 event/field name for existing device firmware and hooks.
        apply(.focusToggled(at: clock.now(), on: on))
    }
    func boolSetting(_ key: String, fallback: Bool = false) -> Bool { _ = settingsRevision; return defaults.object(forKey: key) as? Bool ?? fallback }
    func setBoolSetting(_ key: String, _ value: Bool) {
        if key == DefaultsKey.soundsEnabled { setQuietMode(!value); return }
        defaults.set(value, forKey: key); settingsRevision += 1
    }
    var displayName: String { let name = buddyName.trimmingCharacters(in: .whitespacesAndNewlines); return name.isEmpty ? "Boop" : name }
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
    // Retired preferences cannot re-enable interception, including stale callers.
    func acceptsBuddyApprovals(source: String) -> Bool { false }

    func focusToggled(on: Bool) { setQuietMode(on) }

    func nudgeDismissed(requestId: String? = nil) {
        if let requestId, state.creature.card?.id != requestId { return }
        apply(.nudgeDismissed(at: clock.now()))
    }

    func activitySignal(sessionId: String, source: String, signal: ActivitySignalKind, tool: String? = nil, hint: String? = nil) {
        apply(.activitySignal(at: clock.now(), sessionId: sessionId, source: source, signal: signal, tool: tool, hint: hint))
    }

    func dismissReview() {
        apply(.reviewDismissed(at: clock.now()))
    }

    func refreshSettings() {
        settingsRevision += 1
        if state.creature.focus != quietMode { apply(.focusToggled(at: clock.now(), on: quietMode)) }
    }

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

    // MARK: - Persisted memory

    var petMemory: PetMemory { internalState.memory }

    // Compatibility with old callers. No approval state, waiters or decisions.
    func submitApproval(sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?, stakes: Stakes? = nil, gloss: String? = nil) async -> ApprovalDecision { .passthrough }
    @discardableResult
    func resolveApproval(requestId: String, decision: ApprovalDecision) -> Bool { false }
    func abandonApproval(sessionId: String, requestId: String) {}
    func resolveAllPendingApprovals(decision: ApprovalDecision) {}

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
        let prev = state
        var next = reduce(internalState, event, localHour: dayCalendar.localHour(at: event.at))
        let awards = next.pendingAwards, facts = next.pendingFacts
        next.pendingAwards = []; next.pendingFacts = []
        if !persistenceResult { persist(awards: awards, facts: facts) }
        guard next != internalState else { return }
        let removedIds = Set(internalState.sessions.keys).subtracting(next.sessions.keys)
        let memoryChanged = next.memory != internalState.memory
        internalState = next
        state = next.buddy
        if memoryChanged {
            if !persistenceResult {
                // SQLite is the sole persistence path; an unstarted engine without a store is memory-only.
                enqueue { try await $0.saveMemory(next.memory) }
            }
        }
        for id in removedIds {
            Task { await extractor.drop(sessionId: id) }
            cancelWatcher(sessionId: id)
        }

        for output in outputs {
            output.stateDidChange(prev: prev, next: state)
        }
        if case .workScopeChanged = event {} else { updateWorkContext() }
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
    func finishPendingWork() async { await extractionTail?.value; await flushStore(); await transientVoice.finish() }
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
        let storedFacts = facts.map { StoredFact(fact: $0.fact, sessionId: $0.sessionId, project: $0.project, at: $0.at, day: localDay(at: $0.at)) }
        for award in awards where award.active && !award.sessionId.isEmpty { lastSessionActivity = award.at }
        enqueue { store in
            if !storedFacts.isEmpty { try await store.appendFacts(storedFacts) }
            for award in awards {
                let day = self.localDay(at: award.at)
                if let cheer = award.cheer { try await store.recordCheer(cheer) }
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
        let now = clock.now(), day = localDay(at: clock.now())

        if maintenanceDay != day {
            maintenanceDay = day
            enqueue { try await $0.prune(now: now, localDay: day) }
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
    func dailyActivity() async throws -> [DailyActivity] { await flushStore(); return try await store?.dailyActivity() ?? [] }
    func recentXPActivity() async throws -> [XPActivity] { await flushStore(); return try await store?.recentXPActivity() ?? [] }
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
        // UI localization is independent of the English-only companion pipeline.
        apply(.languageChanged(at: clock.now(), language: language))
        await store?.configureVoice(voice, language: language)
    }
    func setVoiceRuntime(_ setting: String) async {
        guard ["auto", "off"].contains(setting) else { return }
        await flushStore()
        defaults.set(setting, forKey: DefaultsKey.voiceRuntime)
        cancelVoiceGeneration()
        voiceRuntime = VoiceRuntimes.make(setting: setting)
        let calendar = dayCalendar, clock = clock
        voice = Voice(runtime: voiceRuntime, guide: .init(overrideURL: URL(fileURLWithPath: config.stateDir).appendingPathComponent("BEHAVIOR.md")), store: store, localDay: { await MainActor.run { calendar.localDay(at: clock.now()) } })
        updateWorkContext(force: true)
        await store?.configureVoice(voice, language: state.language)
    }
    /// Called by the edit action, never during startup or test construction.
    func editableBehaviorGuide() throws -> URL {
        let url = URL(fileURLWithPath: stateDir).appendingPathComponent("BEHAVIOR.md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(BuddyBehaviorGuide().read().utf8).write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    private func voiceRequest(_ occasion: Occasion, cap: Int) async -> VoiceRequest {
        let event: [String: String]? = switch occasion {
        case .greet: ["kind": "returned", "new_intent_since_return": "unknown"]
        case .completed: ["kind": "turn_ended"]
        case .uhoh: ["kind": "error", "evidence": "explicit_error"]
        default: nil
        }
        return VoiceRequest(occasion: occasion,
            context: BehaviorContext(desk: workContext.bounded(), event: event, previous_scope: previousScope,
                                     recent_remarks: Array(recentRemarks.suffix(5))),
            language: "en", byteCap: cap)
    }

    private func updateWorkContext(force: Bool = false) {
        guard !voiceStopped, !retiring else { return }
        let now = clock.now()
        workIntents = workIntents.filter { id, _ in
            internalState.sessions[id].map { WorkContext.eligible($0, now: now) } ?? false
        }
        let next = WorkContext.make(sessions: internalState.sessions, intents: workIntents, now: now)
        guard force || next != workContext else { return }
        workContext = next
        workRevision += 1
        transientVoice.cancel(.scope)
        transientVoice.cancel(.bubble)
        if let scope = state.workScope { previousScope = scope }
        apply(.workScopeChanged(at: now, text: nil))
        guard !next.projects.isEmpty else { previousScope = nil; return }
        let revision = workRevision
        transientVoice.replace(.scope, produce: { [weak self] in
            guard let self, !self.voiceStopped else { return nil }
            let request = await self.voiceRequest(.workContextChanged, cap: 120)
            return await self.voice.line(for: request).text
        }, deliver: { [weak self] text in
            guard let self, !self.voiceStopped, self.workRevision == revision else { return }
            self.previousScope = text.isEmpty ? nil : text
            self.apply(.workScopeChanged(at: self.clock.now(), text: text.isEmpty ? nil : text))
        })
    }
    private func scheduleVoice(previous: BuddyState, event: BuddyEvent) {
        guard !voiceStopped else { return }
        switch event { case .workScopeChanged, .onboardingCheer, .voiceLine, .growthUpdated, .languageChanged: return; default: break }
        // Invalidate transient text on a new interaction; an old model reply must not cover a card.
        if previous.creature.state != state.creature.state || previous.creature.card?.id != state.creature.card?.id {
            transientVoice.cancel(.bubble)
        }
        guard state.creature.card == nil, state.prompt == nil else { return }
        if let kind = state.creature.uhoh, kind != previous.creature.uhoh {
            requestVoice(.uhoh(kind), kind: .bubble)
        } else if previous.creature.state == .done, state.creature.state == .idle, state.lastCompletionAt != nil {
            requestVoice(.completed, kind: .bubble)
        } else if state.greetUntil != previous.greetUntil, state.greetUntil != nil, state.creature.card == nil {
            requestVoice(.greet(state.greetLevel ?? 1), kind: .bubble)
        }
    }
    private func cancelVoiceGeneration() {
        transientVoice.cancelAll()
    }

    private func requestVoice(_ occasion: Occasion, kind: VoiceLineKind) {
        transientVoice.replace(kind, produce: { [weak self] in
            guard let self else { return nil }
            let request = await self.voiceRequest(occasion, cap: VoiceCap.bubble.rawValue)
            guard !Task.isCancelled else { return nil }
            return await self.voice.line(for: request).text
        }, deliver: { [weak self] text in
            guard let self, !text.isEmpty, !self.voiceStopped, self.state.creature.card == nil else { return }
            self.recentRemarks.append(text)
            self.recentRemarks = Array(self.recentRemarks.suffix(5))
            self.apply(.voiceLine(at: self.clock.now(), kind: kind, text: text))
        })
    }
    private static func promptIds(in state: InternalState) -> Set<String> {
        Set(state.sessions.values.compactMap { $0.prompt?.id })
    }
}
