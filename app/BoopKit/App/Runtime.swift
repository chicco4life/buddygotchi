import Foundation
import HookWire

/// Everything the app runs, wired together (ARCHITECTURE.md §1): the hook
/// socket feeds the adapters and the core; the core's events go to the
/// harness, its moments to the device link and the rest to the memory
/// store; the device's inputs come back to the core. The menu-bar app and `Boop --headless` both
/// run one of these.
///
/// All state lives on `home`, one serial queue, which is also the harness's.
public final class Runtime: @unchecked Sendable {
    public struct Options {
        public var stateDir: URL
        public var socketPath: String
        public var link: DeviceTransport?
        /// The static parts of Jev's state: a copy of `plan/steering/`.
        public var steering: Steering
        /// Override the personality in `settings.json` for this run only.
        public var personality: Personality?
        /// Builds the brain from Jev's key; nil for no brain. Tests pass
        /// their own (harness/HARNESS.md §7).
        public var brain: @Sendable (String?) -> (any Brain)? = { key in key.map { JevBrain(key: $0) } }
        public var time = LocalTime()
        /// Milliseconds for every duration: a steady clock by default.
        public var clock: @Sendable () -> Int64 = Runtime.steadyClock()
        /// Milliseconds since 1970, for days and times of day.
        public var wallClock: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        /// Accept `{"dev":"advance","ms":…}` on the hook socket (headless only).
        public var devLines = false
        /// Moves `clock` forward, for `{"dev":"advance"}`; nil ignores it.
        public var advance: (@Sendable (Int64) -> Void)?
        /// Debug mode (harness/HARNESS.md §9): logs every hook with what the
        /// adapter made of it and every line sent to the device, starts
        /// `debug.jsonl` afresh in the state directory with every transcript
        /// entry, and hands those and the core's decisions to `debugPrint`,
        /// readably.
        public var debug = false
        /// Where debug mode prints (the terminal). Never the log file: it
        /// carries Jev's whole state.
        public var debugPrint: @Sendable (String) -> Void = { _ in }
        /// Reads Jev's key, off `home` and the main thread: the Keychain may
        /// stop to ask for access.
        public var readJevKey: @Sendable () -> String? = { JevKey.read() }
        public var log: @Sendable (String) -> Void = { _ in }

        public init(stateDir: URL, socketPath: String, link: DeviceTransport?, steering: Steering) {
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
        public var personality: Personality
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String
        public var mood: String

        public init(snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool, device: DeviceStatus?,
                    personality: Personality, brain: String, mood: String = "cheerful") {
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.personality = personality
            self.brain = brain
            self.mood = mood
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
    /// How long an arm lasts (ADAPTERS.md §6): one the doctor never
    /// confirms is removed, so hooks aren't logged from then on.
    public static let doctorArmSeconds: TimeInterval = 10 * 60
    /// Debug mode's log of every transcript entry, in the state directory.
    public let debugLogURL: URL
    /// The doctor's arm (`doctorArm`), in the state directory.
    let doctorArmPath: String

    public let home = DispatchQueue(label: "boop.home", qos: .userInitiated)
    public let options: Options
    public let memory: MemoryStore
    public let link: DeviceLink
    public private(set) var settings: AppSettings
    /// The personality running now, touched only on `home`. Starts as the
    /// saved one, unless this run overrides it.
    public private(set) var personality: Personality
    let core: Core
    let harness: Harness
    let mood: MoodStore
    let voice: Voice
    let lock: InstanceLock
    var server: HookServer?
    var timer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Adapter.Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then no event wakes the brain.
    var jevKey: String??
    var readingJevKey = false
    /// Keeps the brain from cutting anything off (BEHAVIORS.md §3): the
    /// rules' moments play at once, and the brain's wait their turn in
    /// `schedule` behind them and the brain's earlier ones.
    final class Moments {
        var schedule = MomentSchedule()
        /// A timer is set for the next brain moment's turn.
        var pumpDue = false
        /// True while a brain moment is being sent (for debug mode).
        var brainSending = false
    }
    let moments = Moments()

    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?

    /// A clock that never steps and keeps counting while the Mac sleeps,
    /// starting at the wall clock's time: the keepalive and moments'
    /// turns are measured on it, so setting the Mac's clock back can't stall them
    /// (ARCHITECTURE.md §3.2).
    public static func steadyClock() -> @Sendable () -> Int64 {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let start = ContinuousClock.now
        return { wall + Int64((ContinuousClock.now - start).ms) }
    }

    /// Sets up a new Boop: name and sweet-or-cheeky, asked once (UX.md §5).
    public static func setUp(stateDir: URL, name: String, nature: LongTerm.Nature, today: String) throws {
        let store = try MemoryStore(directory: stateDir)
        try store.setUp(name: name, nature: nature, seed: UInt64.random(in: 1...0xFFFF), today: today)
    }

    public init(_ options: Options) throws {
        self.options = options
        debugLogURL = options.stateDir.appendingPathComponent(DebugLog.fileName)
        doctorArmPath = options.stateDir.appendingPathComponent(Self.doctorArm).path
        guard let lock = InstanceLock(directory: options.stateDir) else { throw OpenError.locked(options.stateDir.path) }
        self.lock = lock
        let log = options.log
        memory = try MemoryStore(directory: options.stateDir, log: log)
        guard let longTerm = memory.longTerm else { throw OpenError.notSetUp }
        settings = AppSettings.load(from: options.stateDir)
        link = DeviceLink(transport: options.link, log: log)
        if options.debug {
            let moments = self.moments
            link.onSend = { line in log("link \(moments.brainSending ? "brain" : "rules") → " + line) }
        }

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        var config = Core.Config(name: longTerm.name, volume: settings.volume, rules: rules, time: options.time,
                                 seed: longTerm.seed ^ UInt64(now))
        config.brain = false  // until Jev's key is read
        core = Core(config: config, lastActiveDay: memory.lastActiveDay)
        core.setWallClock(options.wallClock(), at: now)
        mood = MoodStore(stateDir: options.stateDir)
        voice = Voice(dialect: Dialect(seed: longTerm.seed))
        for over in options.steering.overBudget() { log("steering: over budget: \(over)") }

        // The actions (harness/DECISIONS.md), in the order they run. Their
        // closures are only ever called on `home`.
        let core = self.core
        let link = self.link
        let clock = options.clock
        let moments = self.moments
        let home = self.home
        let actions: [any Action] = [
            MoodAction(store: mood, now: clock),
            ReactAction(voice: voice, queue: { moment in
                moments.schedule.brain(moment, now: clock())
                Runtime.pump(moments, link: link, clock: clock, home: home, log: log)
            }, blocked: { core.mumbleBlock(at: clock()) }),
        ]
        let steering = options.steering
        let mood = self.mood
        let time = options.time
        var personalityNow: () -> Personality = { .boop }
        harness = Harness(brain: nil, actions: actions, parts: { entry in
            let now = clock()
            let wall = options.wallClock()
            guard case .event(let event) = entry.body else { preconditionFailure("a pass is for an event") }
            return StateText.Parts(guide: steering.guide, personality: steering.personality(personalityNow()).text,
                                   mood: steering.mood(mood.current),
                                   status: core.statusLine(excluding: event.about, at: now),
                                   workingSince: core.workingSince(at: now),
                                   clock: "\(time.clock(wall)), \(time.weekday(wall))")
        }, home: home, clock: clock, debugLog: options.debug ? debugLogURL : nil, log: log)
        harness.onRecord = { record in log(record.logLine) }
        if options.debug {
            DebugLog.start(debugLogURL)
            let printer = DebugLog.Printer()
            let print = options.debugPrint
            harness.onDebugLine = { line in print(printer.readable(line)) }
        }
        personalityNow = { [weak self] in self?.personality ?? .boop }
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
        // From here on the harness and the callbacks are touched only on
        // `home`: reading Jev's key sets the brain and calls `onChange`,
        // so it starts now, after the app has set its callbacks.
        home.async { [self] in
            readJevKey()
            run(core.tick(at: options.clock()))
            link.update(core.snapshot(at: options.clock()), now: options.clock())
            changed()
            options.log("boop: running on \(options.stateDir.path), socket \(options.socketPath), "
                        + "link \(options.link?.name ?? "none"), personality \(personality.rawValue), "
                        + "mood \(mood.current), brain \(harness.brain?.id ?? "none (reading Jev's key)")"
                        + (options.debug ? ", debug log \(debugLogURL.path)" : ""))
        }
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
        let event = Adapter.event(from: line, receivedAt: received, place: places.place)
        // Debug mode logs every hook with what it became; the doctor skill
        // arms the plain line to see hooks arrive. Otherwise hooks aren't logged.
        if options.debug {
            options.log("hook: \(line.agent) \(line.hook) \(line.session) → " + (event?.summary ?? "ignored"))
        } else if doctorArmed() {
            options.log("hook: \(line.agent) \(line.hook) \(line.session)")
        }
        guard let event else { return }
        run(core.handle(event))
    }

    /// Whether the doctor armed this app within the last 10 minutes. An
    /// older arm is removed.
    func doctorArmed() -> Bool {
        guard let armed = (try? FileManager.default.attributesOfItem(atPath: doctorArmPath))?[.modificationDate] as? Date
        else { return false }
        if Date().timeIntervalSince(armed) < Self.doctorArmSeconds { return true }
        try? FileManager.default.removeItem(atPath: doctorArmPath)
        options.log("doctor: an arm older than \(Int(Self.doctorArmSeconds / 60)) minutes, removed")
        return false
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
        if object["dev"] as? String == "advance", let ms = (object["ms"] as? NSNumber)?.int64Value,
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
        if options.debug {
            // The snapshot shows as the line the link sends, if it sends one.
            for effect in effects {
                if case .state = effect { continue }
                options.debugPrint("core: " + effect.summary)
            }
        }
        var stateChanged = false
        for effect in effects {
            switch effect {
            case .state(let snapshot):
                link.update(snapshot, now: options.clock())
                stateChanged = true
            case .moment(let anim):
                playRule(DeviceMoment(anim: anim))
            case .mumble(let feeling, let word):
                // Working chatter is filler: it never cuts a moment that's
                // playing, such as a brain mumble, or jumps one waiting its
                // turn (BEHAVIORS.md §2).
                guard moments.schedule.idle(now: options.clock()), core.mumbleBlock(at: options.clock()) == nil,
                      let f = Feeling(rawValue: feeling) else { continue }
                chatterSeed += 1
                playRule(DeviceMoment(say: voice.line(f, word: word, seed: chatterSeed)))
            case .event(let event):
                harness.take(event)
            case .newDay:
                memory.apply(effect)
            }
        }
        if stateChanged { changed() }
    }

    /// Seeds working chatter's lines.
    var chatterSeed: UInt64 = 0

    /// A rule moment: it plays at once, and anything the brain has waiting
    /// waits for it too.
    func playRule(_ moment: DeviceMoment) {
        link.play(moment)
        moments.schedule.rule(moment, now: options.clock())
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
                         connected: link.connected, device: link.status, personality: personality,
                         brain: harness.brain?.id ?? "none", mood: mood.current))
    }

    func saveSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try settings.save(to: options.stateDir) } catch { options.log("settings: can't save: \(error)") }
    }

    // MARK: From the menu bar (any thread)

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

    /// A new personality (BEHAVIORS.md §6): the core's rules and Jev's
    /// state from the next event.
    public func setPersonality(_ personality: Personality) {
        home.async { [self] in
            self.personality = personality
            saveSettings { $0.personality = personality }
            core.setRules(options.steering.personality(personality).rules)
            options.log("personality \(personality.rawValue)")
            changed()
        }
    }

    /// Jev's key as Settings just saved it (nil when it was cleared);
    /// `BOOP_JEV_KEY` still wins. Used from the next event.
    public func reloadBrain(jevKey key: String?) {
        home.async { [self] in
            jevKey = .some(JevKey.read(else: key))
            useBrain()
            changed()
        }
    }

    /// The brain for Jev's key as far as it's been read. On `home`.
    func useBrain() {
        let brain = options.brain(jevKey ?? nil)
        harness.use(brain)
        core.setBrain(brain != nil)
        options.log("brain \(brain?.id ?? "none")" + (brain == nil ? ": no Jev key, so Boop does only its rule reactions" : ""))
    }

    /// Reads Jev's key off `home` (harness/HARNESS.md §7): a Keychain prompt
    /// there would stall every hook, tick and device line until it's
    /// answered. Then the brain is built with it. On `home`.
    func readJevKey() {
        guard jevKey == nil, !readingJevKey else { return }
        readingJevKey = true
        let read = options.readJevKey
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let key = read()
            self?.home.async { [weak self] in
                guard let self else { return }
                readingJevKey = false
                // A key Settings saved meanwhile wins.
                if jevKey == nil { jevKey = .some(key) }
                useBrain()
                changed()
            }
        }
    }

    /// A fresh status, on `home`.
    public func refresh() {
        home.async { [self] in changed() }
    }
}
