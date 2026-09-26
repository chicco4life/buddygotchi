import Foundation
import HookWire

/// Everything the app runs, wired together (ARCHITECTURE.md §1): the hook
/// socket feeds the adapters and the core; the core's effects go to the
/// actions, the harness, the memory store and the device link; the device's
/// inputs come back to the core. The menu-bar app and `Boop --headless` both
/// run one of these.
///
/// All state lives on `home`, one serial queue, which is also the harness's.
public final class Runtime: @unchecked Sendable {
    public struct Options {
        public var stateDir: URL
        public var socketPath: String
        public var link: DeviceTransport?
        public var steering: String
        /// Override the mode in `settings.json` for this run only.
        public var mode: Mode?
        /// Override the mode's brain for this run only (HARNESS.md §6):
        /// `Brains.classifiers` and `Brains.writers`.
        public var classifier: String?
        public var writer: String?
        public var time = LocalTime()
        /// Milliseconds for every duration: a steady clock by default.
        public var clock: @Sendable () -> Int64 = Runtime.steadyClock()
        /// Milliseconds since 1970, for days and times of day.
        public var wallClock: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        /// Accept `{"dev":"talk","words":…,"yelled":…}` and `{"dev":"advance","ms":…}`
        /// on the hook socket (headless only).
        public var devLines = false
        /// Moves `clock` forward, for `{"dev":"advance"}`; nil ignores it.
        public var advance: (@Sendable (Int64) -> Void)?
        /// Log every hook and every line sent to the device (the L4 check).
        public var trace = false
        /// §8's JSONL log of every brain call; nil keeps none.
        public var debugLog: URL?
        public var log: @Sendable (String) -> Void = { _ in }

        public init(stateDir: URL, socketPath: String, link: DeviceTransport?, steering: String) {
            self.stateDir = stateDir
            self.socketPath = socketPath
            self.link = link
            self.steering = steering
        }
    }

    /// What the menu bar shows.
    public struct Status: Sendable {
        public var snapshot: StateSnapshot
        /// Every session, for the popover's list.
        public var sessions: [SessionSummary]
        public var connected: Bool
        public var device: DeviceStatus?
        public var mode: Mode
        /// The brain's two stages as they run, e.g. `jev:jev-latest` and `apple:26.4`.
        public var classifier: String
        public var writer: String
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool

        public init(snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool, device: DeviceStatus?,
                    mode: Mode, classifier: String, writer: String, listening: Bool = false) {
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.mode = mode
            self.classifier = classifier
            self.writer = writer
            self.listening = listening
        }
    }

    public enum OpenError: Error, CustomStringConvertible {
        case notSetUp, locked(String)
        public var description: String {
            switch self {
            case .notSetUp: "Boop isn't set up yet: no long-term.md"
            case .locked(let dir): "another Boop is already running on \(dir)"
            }
        }
    }

    /// While this file exists in the state directory, every hook is logged.
    public static let doctorArm = "doctor-armed"

    public let home = DispatchQueue(label: "boop.home", qos: .userInitiated)
    public let options: Options
    public let memory: MemoryStore
    public let link: DeviceLink
    public private(set) var settings: AppSettings
    /// The mode running now, touched only on `home`. Starts as the saved one,
    /// unless this run overrides it.
    public private(set) var mode: Mode
    let core: Core
    let harness: Harness
    let react: ReactAction
    let lock: InstanceLock
    var server: HookServer?
    var timer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let projectNames = Adapter.ProjectNames()
    /// Keeps the brain from cutting anything off (BEHAVIORS.md §3): a
    /// moment an action sends outside the core's effects is the brain's, and
    /// waits its turn in `schedule` behind the rules' moments and the
    /// brain's earlier ones.
    final class Moments {
        /// Above zero while the core's effects are carried out.
        var inRules = 0
        var schedule = MomentSchedule()
        /// A timer is set for the next brain moment's turn.
        var pumpDue = false
        /// True while a brain moment is being sent (for `trace`).
        var brainSending = false
        /// Brain moments sent since the last harness pass ended. Only a
        /// pass's actions send them, so at its end this is what it sent.
        var brainSent = 0
    }
    let moments = Moments()

    /// Push-to-talk: start (true) or stop listening. Called on `home`.
    public var onListen: ((Bool) -> Void)?
    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?

    /// A clock that never steps and keeps counting while the Mac sleeps,
    /// starting at the wall clock's time: the keepalive, the mic's 30 s
    /// limit, held inputs, the reply wait and moments' turns are measured on
    /// it, so setting the Mac's clock back can't stall them
    /// (ARCHITECTURE.md §3.2).
    public static func steadyClock() -> @Sendable () -> Int64 {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let start = ContinuousClock.now
        return {
            let (seconds, attoseconds) = (ContinuousClock.now - start).components
            return wall + seconds * 1000 + attoseconds / 1_000_000_000_000_000
        }
    }

    /// Sets up a new Boop: name and sweet-or-cheeky, asked once (UX.md §6).
    public static func setUp(stateDir: URL, name: String, nature: LongTerm.Nature, today: String) throws {
        let store = try MemoryStore(directory: stateDir, steering: "")
        try store.setUp(name: name, nature: nature, seed: UInt64.random(in: 1...0xFFFF), today: today)
    }

    public init(_ options: Options) throws {
        self.options = options
        guard let lock = InstanceLock(directory: options.stateDir) else { throw OpenError.locked(options.stateDir.path) }
        self.lock = lock
        let log = options.log
        memory = try MemoryStore(directory: options.stateDir, steering: options.steering, log: log)
        guard let longTerm = memory.longTerm else { throw OpenError.notSetUp }
        settings = AppSettings.load(from: options.stateDir)
        link = DeviceLink(transport: options.link, log: log)
        if options.trace {
            let moments = self.moments
            link.onSend = { line in log("link \(moments.brainSending ? "brain" : "rules") → " + line) }
        }

        let now = options.clock()
        mode = options.mode ?? settings.mode
        var config = Core.Config(name: longTerm.name, volume: settings.volume, mode: mode, time: options.time,
                                 seed: longTerm.seed ^ UInt64(now))
        config.name = longTerm.name
        core = Core(config: config, lastActiveDay: memory.lastActiveDay)
        core.setWallClock(options.wallClock(), at: now)

        // Actions reach the rest through closures that are only ever called
        // on `home`, from the core's effects or the harness.
        var route: ([CoreEffect]) -> Void = { _ in }
        let core = self.core
        let link = self.link
        let time = options.time
        let clock = options.clock
        let wallClock = options.wallClock
        let context = ActionContext(
            send: { [moments, home] moment in
                let now = clock()
                if moments.inRules > 0 {
                    link.play(moment)
                    moments.schedule.rule(moment, now: now)
                    return
                }
                moments.schedule.brain(moment, now: now)
                moments.brainSent += 1
                Runtime.pump(moments, link: link, clock: clock, home: home, log: log)
            },
            mumblesAllowed: { core.canMumble(at: clock()) },
            setQuiet: { route(core.setQuiet(minutes: $0, at: clock())) },
            quietAsked: { core.quietAsked },
            today: { time.day(wallClock()) },
            log: log)
        let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: longTerm.seed)), memory: memory)
        react = actions.compactMap { $0 as? ReactAction }.first!
        let memory = self.memory
        harness = Harness(classifier: Brains.classifier(for: mode, override: options.classifier, key: Brains.jevKey, log: log),
                          writer: Brains.writer(for: mode, override: options.writer, log: log),
                          tools: actions.map(Harness.Tool.init), memory: { _ in memory.promptMemory() },
                          home: home, debugLog: options.debugLog, log: log)
        // Tool names only: arguments can carry what you said (HARNESS.md §8).
        // A pass for what you said that sent no mumble ends `listening` now.
        let moments = self.moments
        harness.onRecord = { [weak self] record in
            log(record.logLine)
            let mumbled = moments.brainSent > 0
            moments.brainSent = 0
            guard record.input.kind == .said, let self else { return }
            run(core.replied(to: record.input.ts, mumbled: mumbled, at: clock()))
        }
        route = { [weak self] in self?.run($0) }
    }

    // MARK: Running

    public func start() throws {
        let home = self.home
        // Hooks are timed on the runtime's clock, which headless mode can move.
        let clock = options.clock
        let onLine: @Sendable (HookLine, Int64) -> Void = { [weak self] line, _ in
            let received = clock()
            home.async { self?.hook(line, received: received) }
        }
        let onOther: @Sendable (Data) -> Void = { [weak self] data in home.async { self?.dev(data) } }
        let server = HookServer(path: options.socketPath, onLine: onLine, onOther: options.devLines ? onOther : nil)
        try server.start()
        self.server = server
        options.link?.start(
            onLine: { [weak self] line in self?.home.async { self?.device(line) } },
            onConnection: { [weak self] up in
                self?.home.async {
                    guard let self else { return }
                    self.link.connection(up, now: self.options.clock())
                    if !up { self.run(self.core.linkDown(at: self.options.clock())) }
                    self.changed()
                }
            })
        // A menu-bar app with its popover closed is a candidate for App Nap,
        // which coalesces timers; the 10 s keepalive must beat the device's
        // 30 s no-app timeout. This doesn't keep the Mac awake.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Keeps Boop's device in sync")
        let timer = DispatchSource.makeTimerSource(queue: home)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        home.async { [self] in
            run(core.tick(at: options.clock()))
            link.update(core.snapshot(at: options.clock()), now: options.clock())
            changed()
        }
        options.log("boop: running on \(options.stateDir.path), socket \(options.socketPath), link \(options.link?.name ?? "none"), "
                    + "mode \(mode.rawValue), brain \(harness.classifier.id) + \(harness.writer.id)")
    }

    /// Stops listening for hooks and the device. Safe to call twice.
    public func stop() {
        timer?.cancel()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        server?.stop()
        server = nil
        options.link?.stop()
    }

    // MARK: Inputs (on `home`)

    func hook(_ line: HookLine, received: Int64) {
        // The doctor skill arms this to see hooks arrive; otherwise hooks
        // aren't logged.
        if options.trace || FileManager.default.fileExists(atPath: options.stateDir.appendingPathComponent(Self.doctorArm).path) {
            options.log("hook: \(line.agent) \(line.hook) \(line.session)")
        }
        guard let event = Adapter.event(from: line, receivedAt: received, project: projectNames.name) else { return }
        run(core.handle(event))
    }

    func device(_ line: String) {
        let now = options.clock()
        if case .input(let input) = link.receive(line, now: now) {
            options.log("device: input \(input.rawValue)")
            run(core.input(input, at: now))
        }
        changed()
    }

    func dev(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if object["dev"] as? String == "talk", let words = object["words"] as? String {
            let yelled = object["yelled"] as? Bool == true
            options.log("dev: talk \"\(words)\"\(yelled ? " (yelled)" : "")")
            talkNow(words, yelled: yelled)
        } else if object["dev"] as? String == "advance", let ms = (object["ms"] as? NSNumber)?.int64Value,
                  ms > 0, let advance = options.advance {
            advance(ms)
            options.log("dev: clock advanced \(ms) ms")
            tick()
        }
    }

    func tick() {
        let now = options.clock()
        core.setWallClock(options.wallClock(), at: now)
        run(core.tick(at: now))
        link.tick(now: now, current: core.snapshot(at: now))
    }

    /// Carries out the core's decisions (ARCHITECTURE.md §3.2).
    func run(_ effects: [CoreEffect]) {
        moments.inRules += 1
        defer { moments.inRules -= 1 }
        var stateChanged = false
        var listenChanged = false
        for effect in effects {
            switch effect {
            case .state(let snapshot):
                link.update(snapshot, now: options.clock())
                stateChanged = true
            case .moment(let anim):
                react.play(anim)
            case .endListening:
                react.endListening()
            case .mumble(let feeling, let word):
                // Working chatter is filler: it never cuts a moment that's
                // playing, such as the brain's reply, or jumps one waiting
                // its turn (BEHAVIORS.md §2).
                guard moments.schedule.idle(now: options.clock()) else { continue }
                var arguments: [String: ToolValue] = ["feeling": .string(feeling), "voice": .string("mumble")]
                if let word { arguments["word"] = .string(word) }
                react.run(ToolCall("react", arguments))
            case .input(let input):
                harness.submit(input)
            case .aside(let line):
                harness.note(line, at: options.clock())
            case .happened, .newDay:
                memory.apply(effect)
            case .listen(let on):
                // A brain mumble queued before the mic went on would end
                // `listening` before the reply (BEHAVIORS.md §3.3).
                if on {
                    for moment in moments.schedule.dropWaiting() {
                        options.log("react: dropped a brain moment waiting when the mic went on: \(moment.jsonLine)")
                    }
                }
                onListen?(on)
                listenChanged = true
            }
        }
        if stateChanged || listenChanged { changed() }
    }

    /// Plays the brain's next moment if its turn has come, and sets a timer
    /// for the one after (a newer rule moment pushes it back; the timer then
    /// just sets another). On `home`.
    static func pump(_ moments: Moments, link: DeviceLink, clock: @escaping @Sendable () -> Int64,
                     home: DispatchQueue, log: @escaping @Sendable (String) -> Void) {
        let now = clock()
        let due = moments.schedule.due(now: now)
        for moment in due.dropped {
            log("react: dropped a brain moment that waited past its \(moment.ttl) s: \(moment.jsonLine)")
        }
        if let moment = due.play {
            moments.brainSending = true
            link.play(moment)
            moments.brainSending = false
        }
        guard let next = due.next, !moments.pumpDue else { return }
        moments.pumpDue = true
        home.asyncAfter(deadline: .now() + .milliseconds(Int(max(1, next - now)))) {
            moments.pumpDue = false
            pump(moments, link: link, clock: clock, home: home, log: log)
        }
    }

    func changed() {
        let now = options.clock()
        onChange?(Status(snapshot: link.latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                         connected: link.connected, device: link.status, mode: mode, classifier: harness.classifier.id,
                         writer: harness.writer.id, listening: core.listening != nil))
    }

    func talkNow(_ words: String, yelled: Bool = false) {
        run(core.talk(words, yelled: yelled, at: options.clock()))
    }

    func saveSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try settings.save(to: options.stateDir) } catch { options.log("settings: can't save: \(error)") }
    }

    // MARK: From the menu bar (any thread)

    /// The transcript from push-to-talk, and whether you yelled it. It
    /// reaches the harness and is then dropped (ARCHITECTURE.md §3.8).
    public func talk(_ words: String, yelled: Bool = false) {
        home.async { [self] in talkNow(words, yelled: yelled) }
    }

    /// The Talk button: start or stop listening (UX.md §5).
    public func setListening(_ on: Bool) {
        home.async { [self] in run(core.listen(on, at: options.clock())) }
    }

    /// The mic or speech recognition couldn't start.
    public func micFailed() {
        home.async { [self] in run(core.micFailed(at: options.clock())) }
    }

    /// The mic went off and heard nothing, so no words are coming.
    public func heardNothing() {
        home.async { [self] in run(core.heardNothing(at: options.clock())) }
    }

    /// Drops the device link and looks for the device again now.
    public func reconnectDevice() {
        link.transport?.reconnect()
    }

    public func setVolume(_ volume: Int) {
        home.async { [self] in
            run(core.setVolume(volume, at: options.clock()))
            saveSettings { $0.volume = max(0, min(10, volume)) }
        }
    }

    /// A new mode, at once (BEHAVIORS.md §6): the core's rules from the next
    /// event, the brain from the next input. A pass already running
    /// finishes with the brain it started with.
    public func setMode(_ mode: Mode) {
        home.async { [self] in
            self.mode = mode
            saveSettings { $0.mode = mode }
            core.setMode(mode)
            useBrains()
            changed()
        }
    }

    /// Builds the mode's brain again, for a new mode or a new Jev key.
    public func reloadBrains() {
        home.async { [self] in
            useBrains()
            changed()
        }
    }

    func useBrains() {
        let log = options.log
        harness.use(Brains.classifier(for: mode, override: options.classifier, key: Brains.jevKey, log: log),
                    Brains.writer(for: mode, override: options.writer, log: log))
        log("mode \(mode.rawValue), brain \(harness.classifier.id) + \(harness.writer.id)")
    }

    /// What Boop remembers about you, for the settings screen.
    public func remembered(_ done: @escaping @Sendable ([String]) -> Void) {
        home.async { [self] in
            let lt = memory.longTerm
            done((lt?.aboutYou ?? []) + (lt?.preferences ?? []))
        }
    }

    /// Deletes one remembered line, from the settings screen.
    public func forget(_ line: String) {
        home.async { [self] in
            if case .failure(let why) = memory.forget(line) { options.log("settings: can't forget: \(why)") }
        }
    }

    /// A fresh status, on `home`.
    public func refresh() {
        home.async { [self] in changed() }
    }
}
