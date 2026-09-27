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
        /// Accept `{"dev":…}` lines on the hook socket: headless, or debug
        /// mode (harness/HARNESS.md §9). Plain `make run` stays deaf to them.
        public var devLines = false
        /// Moves `clock` forward, for `{"dev":"advance"}`; nil ignores it.
        public var advance: (@Sendable (Int64) -> Void)?
        /// Milliseconds the Mac has slept since launch: `clock` counts them,
        /// but a turn's length doesn't (ARCHITECTURE.md §3.2).
        public var asleep: @Sendable () -> Int64 = Runtime.sleepClock()
        /// Debug mode (harness/HARNESS.md §9): logs every hook with what the
        /// adapter made of it and every line sent to the device, starts
        /// `debug.jsonl` afresh in the state directory (keeping the last
        /// launches' copies beside it) with every transcript entry and the
        /// dashboard's lines, and hands the entries and the core's decisions
        /// to `debugPrint`, readably.
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
        /// Boop's name, from `long-term.md`.
        public var name: String
        /// What the device shows, and Boop's mood.
        public var snapshot: StateSnapshot
        /// Every session, for the popover's list.
        public var sessions: [SessionSummary]
        public var connected: Bool
        public var device: DeviceStatus?
        public var personality: Personality
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceStatus?, personality: Personality, brain: String) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.personality = personality
            self.brain = brain
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
    /// Boop's name, from `long-term.md`.
    let name: String
    public private(set) var settings: AppSettings
    /// The personality running now, touched only on `home`. Starts as the
    /// saved one, unless this run overrides it.
    public private(set) var personality: Personality
    let core: Core
    let harness: Harness
    let mood: MoodStore
    let moodAction: MoodAction
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
    /// `schedule` behind them and the brain's earlier ones. Each of the
    /// brain's goes to the device with an id, holds the schedule's line
    /// until the device says how it ended, and ends its handle then, or
    /// when it can't have played (harness/DECISIONS.md §5).
    final class Moments {
        /// How long past a moment's expected end the app waits for the
        /// device's `ended` before giving up on it (PROTOCOL.md §6).
        static let endGraceMs: Int64 = 3000
        /// The largest id a moment goes out with: the device keeps ids in
        /// 32 bits, and JSON readers anywhere take this as a plain int.
        static let maxId = Int(Int32.max)

        var schedule = MomentSchedule()
        /// The timer set for the brain's next turn, and the time it's set
        /// for; nil when none is.
        var pumpTimer: DispatchSourceTimer?
        var pumpAt: Int64?
        /// True while a brain moment is being sent (for debug mode).
        var brainSending = false
        /// The id the last brain moment went out with. Each launch starts
        /// somewhere random and counts up from there, so a moment an
        /// earlier launch left playing on the device can't share an id with
        /// one of this launch's (PROTOCOL.md §3).
        var lastId = Moments.firstId()
        /// The brain's moments on the device, oldest first, each with its
        /// id, its handle and when the app stops waiting for its `ended`.
        var playing: [(id: Int, pending: Pending, deadline: Int64)] = []

        /// Where a launch's ids start: the first goes out as one more.
        static func firstId() -> Int { Int.random(in: 0..<maxId) }

        /// The id after `id`, back to 1 past `maxId`.
        static func nextId(after id: Int) -> Int { id >= maxId ? 1 : id + 1 }

        /// A brain moment going to the device at `now`: it gets the next id,
        /// and its handle, and the schedule's line, wait for the device's
        /// `ended` until its length at most, and the grace, have passed.
        func send(_ moment: inout DeviceMoment, _ pending: Pending, now: Int64) {
            lastId = Self.nextId(after: lastId)
            moment.id = lastId
            let deadline = now + schedule.playMs(moment, now: now) + Self.endGraceMs
            playing.append((lastId, pending, deadline))
            schedule.hold(id: lastId, moment, now: now, until: deadline)
        }

        /// The device's `ended` at `now`: frees the schedule's line if the
        /// moment holds it, and ends its handle. An id the app isn't
        /// waiting on (one it gave up on) is ignored.
        func ended(_ ended: MomentEnded, now: Int64) {
            schedule.ended(id: ended.id, now: now)
            guard let i = playing.firstIndex(where: { $0.id == ended.id }) else { return }
            playing.remove(at: i).pending.finish(Self.end(ended))
        }

        /// How a reaction ended, from the device's `ended`
        /// (harness/DECISIONS.md §5).
        static func end(_ ended: MomentEnded) -> Pending.End {
            switch ended.how {
            case .done: .done
            case .cut: .failed("cut short" + (ended.why.flatMap { cutBy[$0] }.map { ": " + $0 } ?? ""))
            case .skipped: .failed("something needed you")
            }
        }

        /// What cut a moment short, as HISTORY says it; `reset` is a tool's.
        static let cutBy = ["tap": "you tapped Boop", "moment": "something newer played",
                            "needs_you": "something needed you"]

        /// Gives up on each moment whose `ended` hasn't come by its
        /// deadline: the device lost the line, or its firmware doesn't send one.
        func overdue(now: Int64) {
            let late = playing.filter { now >= $0.deadline }
            playing.removeAll { now >= $0.deadline }
            for moment in late { moment.pending.finish(.failed("the device never said it ended")) }
        }

        /// Ends every moment on the device as failed, with why.
        func failAll(_ why: String) {
            let all = playing
            playing = []
            for moment in all { moment.pending.finish(.failed(why)) }
        }
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

    /// How long the Mac has slept since this was made: the steady clock
    /// less one that stops while the Mac sleeps.
    public static func sleepClock() -> @Sendable () -> Int64 {
        let continuous = ContinuousClock.now
        let suspending = SuspendingClock.now
        return { max(0, Int64((ContinuousClock.now - continuous).ms) - Int64((SuspendingClock.now - suspending).ms)) }
    }

    /// The sleep already told to the core, and the headless clock's jumps
    /// that count as sleep (`{"dev":"advance","asleep":true}`).
    var toldAsleep: Int64 = 0
    var devAsleep: Int64 = 0

    /// Tells the core how long the Mac slept since last time, before
    /// anything the core does now. Under a second is the clocks' jitter.
    func noteSleep() {
        let asleep = options.asleep() + devAsleep
        guard asleep - toldAsleep >= 1000 else { return }
        core.slept(asleep - toldAsleep)
        toldAsleep = asleep
    }

    /// Sets up a new Boop: name and sweet-or-cheeky, asked once (UX.md §5).
    /// It hatches `today`, by default the Mac's.
    public static func setUp(stateDir: URL, name: String, nature: LongTerm.Nature,
                             today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) throws {
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
        name = longTerm.name
        settings = AppSettings.load(from: options.stateDir)
        link = DeviceLink(transport: options.link, log: log)
        if options.debug {
            let moments = self.moments
            let debugLog = debugLogURL
            let clock = options.clock
            link.onSend = { line in
                log("link \(moments.brainSending ? "brain" : "rules") → " + line)
                Harness.appendLine(DebugLog.line("sent", line, at: clock()), to: debugLog)
            }
        }

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        mood = MoodStore(stateDir: options.stateDir)
        var config = Core.Config(volume: settings.volume, rules: rules, time: options.time, seed: longTerm.seed ^ UInt64(now))
        config.brain = false  // until Jev's key is read
        config.mood = mood.current
        config.firstAsk = Core.randomFirstAsk()
        core = Core(config: config, lastActiveDay: memory.lastActiveDay)
        core.setWallClock(options.wallClock(), at: now)
        voice = Voice(dialect: Dialect(seed: longTerm.seed))
        for over in options.steering.overBudget() { log("steering: over budget: \(over)") }

        // The actions (harness/DECISIONS.md), in the order they run. Their
        // closures are only ever called on `home`.
        let core = self.core
        let link = self.link
        let clock = options.clock
        let moments = self.moments
        let home = self.home
        var moodSaved: (String) -> Void = { _ in }
        moodAction = MoodAction(store: mood, changed: { moodSaved($0) })
        let react = ReactAction(voice: voice, queue: { moment, pending in
            moments.schedule.brain(moment, pending, now: clock())
            Runtime.pump(moments, link: link, clock: clock, home: home, log: log)
        }, blocked: { core.mumbleBlock }, clock: clock)
        let actions: [any Action] = [moodAction, react]
        let steering = options.steering
        let mood = self.mood
        let time = options.time
        var personalityNow: () -> Personality = { .boop }
        let wallClock = options.wallClock
        harness = Harness(brain: nil, actions: actions, parts: { entry in
            Runtime.stateParts(for: entry, steering: steering, personality: personalityNow(), mood: mood.current,
                               core: core, react: react, time: time, now: clock(), wall: wallClock())
        }, home: home, clock: clock, debugLog: options.debug ? debugLogURL : nil, log: log)
        if options.debug {
            DebugLog.start(debugLogURL)
            let printer = DebugLog.Printer()
            let print = options.debugPrint
            harness.onDebugLine = { line in printer.readable(line).map(print) }
        }
        // No event's pass starts while something needs you, not even one
        // that woke the brain before and waited (harness/EVENTS.md §6).
        harness.mayStart = { !core.needsYouShowing }
        personalityNow = { [weak self] in self?.personality ?? .boop }
        moodSaved = { [weak self] in self?.moodChanged($0) }
        // A pass can change the mood, which the menu bar shows.
        harness.onRecord = { [weak self] record in
            log(record.logLine)
            self?.changed()
        }
    }

    /// Everything Jev's state needs besides the transcript, for the pass on
    /// `entry` (harness/HARNESS.md §6): the steering files, the lines that
    /// close HISTORY (`react`'s last reaction, then the core's status
    /// line), the oldest working turn at steady time `now`, and the
    /// time of day at wall-clock time `wall`. The evals build theirs with
    /// it too.
    public static func stateParts(for entry: Transcript.Entry, steering: Steering, personality: Personality,
                                  mood: String, core: Core, react: ReactAction, time: LocalTime, now: Int64,
                                  wall: Int64) -> StateText.Parts {
        let about: String? = if case .event(let event) = entry.body { event.about } else { nil }
        let status = [react.lastLine(at: now), core.statusLine(excluding: about, at: now)].compactMap { $0 }
        return StateText.Parts(guide: steering.guide, personality: steering.personality(personality).text,
                               mood: steering.mood(mood), status: status.joined(separator: "\n"),
                               workingSince: core.workingSince(at: now), clock: "\(time.clock(wall)), \(time.weekday(wall))")
    }

    // MARK: Running

    public func start() throws {
        let home = self.home
        // The questions line is debug.jsonl's first, before the socket or the
        // link can add one, so a changed first line means a new launch
        // (DASHBOARD.md §3).
        if options.debug {
            home.sync { Harness.appendLine(DebugLog.questions(harness.actions, at: options.clock()), to: debugLogURL) }
        }
        // Hooks are timed on the runtime's clock, which headless mode can move.
        let clock = options.clock
        let onLine: @Sendable (HookLine) -> Void = { [weak self] line in
            let received = clock()
            home.async { self?.hook(line, received: received) }
        }
        let onOther: @Sendable (Data) -> Void = { [weak self] data in home.async { self?.dev(data) } }
        let server = HookServer(path: options.socketPath, onLine: onLine, onOther: options.devLines ? onOther : nil)
        try server.start()
        self.server = server
        options.link?.start(
            onLine: { [weak self] line in self?.home.async { self?.device(line) } },
            onConnection: { [weak self] up in self?.home.async { self?.connection(up) } })
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
            show(core.snapshot(at: options.clock()))
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
        home.async { [moments] in
            moments.pumpTimer?.cancel()
            moments.pumpTimer = nil
            moments.pumpAt = nil
        }
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
        noteSleep()
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

    /// The transport connected or dropped. HISTORY says a moment playing
    /// on a device that dropped didn't happen, since its `ended` may never
    /// come (ARCHITECTURE.md §8). But the device plays on, and the link may
    /// be back a second later, so the schedule keeps its reckoning: the
    /// moment still holds the line until its `ended` comes over the link
    /// again, or the app gives up on it.
    func connection(_ up: Bool) {
        let now = options.clock()
        link.connection(up, now: now)
        if !up {
            moments.failAll("the device disconnected")
            pump()
        }
        changed()
    }

    func device(_ line: String) {
        let now = options.clock()
        switch link.receive(line, now: now) {
        case .input(let input):
            options.log("device: input \(input.rawValue)")
            // The device has already wiggled, cutting whatever played.
            if input == .tap { moments.schedule.tapped(now: now) }
            run(core.input(input, at: now))
            pump()
        case .ended(let ended):
            options.log("device: moment \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            moments.ended(ended, now: now)
            pump()
        default:
            break
        }
        changed()
    }

    /// A `{"dev":…}` line from the socket (VERIFICATION.md §2, DASHBOARD.md
    /// §4): only with `devLines`. Nothing replies; what it did shows in
    /// `debug.jsonl`.
    func dev(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch object["dev"] as? String {
        case "advance":
            guard let ms = (object["ms"] as? NSNumber)?.int64Value, ms > 0, let advance = options.advance else { return }
            advance(ms)
            let asleep = object["asleep"] as? Bool == true
            if asleep { devAsleep += ms }
            options.log("dev: clock advanced \(ms) ms" + (asleep ? ", the Mac asleep" : ""))
            tick()
        case "answer":
            // A forced pass: the actions keep their own rules.
            guard let choices = object["answers"] as? [String: String] else { return }
            options.log("dev: forced pass → " + Transcript.ActionRecord.names(harness.force(choices)))
            changed()
        case "mood":
            // The mood action's own change, which tells the device too
            // (harness/DECISIONS.md §4).
            guard let to = object["mood"] as? String else { return }
            let result = harness.force(moodAction) { moodAction.change(to: to) }
            options.log("dev: mood \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
            changed()
        case "moment":
            // Through the moment schedule, as a rule's: a cheer as long as
            // the rule's.
            guard let anim = object["anim"] as? String, DeviceMoment.anims.contains(anim) else { return }
            playRule(DeviceMoment(anim: anim, loops: anim == "cheer" ? Core.cheerLoops(mood: core.config.mood) : nil))
            options.log("dev: moment \(anim)")
        default:
            break  // such as boopdev replay's probe
        }
    }

    func tick() {
        let now = options.clock()
        noteSleep()
        core.setWallClock(options.wallClock(), at: now)
        run(core.tick(at: now))
        link.tick(now: now)
        moments.overdue(now: now)
        // A reaction that has waited too long is dropped here too, before
        // the harness's ceiling could end it, even when the pump's timer,
        // which runs on uptime, hasn't fired (the clock jumped).
        pump()
        harness.tick(now: now)
    }

    /// The mood action saved a new mood: the device draws it from the next
    /// `state` (PROTOCOL.md §3).
    func moodChanged(_ mood: String) {
        run(core.setMood(mood, at: options.clock()))
    }

    /// Carries out the core's decisions (ARCHITECTURE.md §3.2).
    func run(_ effects: [CoreEffect]) {
        if options.debug {
            // The snapshot shows as the line the link sends, if it sends one,
            // and the sessions in debug.jsonl's `status`.
            for effect in effects {
                if case .state = effect { continue }
                if case .sessions = effect { continue }
                options.debugPrint("core: " + effect.summary)
            }
        }
        var stateChanged = false
        for effect in effects {
            switch effect {
            case .state(let snapshot):
                show(snapshot)
                stateChanged = true
            case .sessions:
                stateChanged = true
            case .moment(let anim, let loops):
                playRule(DeviceMoment(anim: anim, loops: loops))
            case .mumble(let feeling, let word):
                // Working chatter is filler: it never cuts a moment that's
                // playing, such as a brain mumble, or jumps one waiting its
                // turn (BEHAVIORS.md §2).
                guard moments.schedule.idle(now: options.clock()), core.mumbleBlock == nil,
                      let f = Feeling(rawValue: feeling) else { continue }
                chatterSeed += 1
                playRule(DeviceMoment(say: voice.line(f, word: word, seed: chatterSeed)))
            case .event(let event):
                harness.take(event)
            case .newDay(let date):
                memory.startDay(date)
            }
        }
        if stateChanged { changed() }
    }

    /// Seeds working chatter's lines.
    var chatterSeed: UInt64 = 0

    /// A snapshot for the device, whose look and mood time the moments
    /// played over it; "needs you" starting stops them.
    func show(_ snapshot: StateSnapshot) {
        let now = options.clock()
        link.update(snapshot, now: now)
        moments.schedule.show(look: snapshot.base, mood: snapshot.mood, attn: snapshot.attn != nil, now: now)
        pump()
    }

    /// A rule moment: it plays at once. Anything the brain has waiting
    /// waits for its line, or plays over its animation now.
    func playRule(_ moment: DeviceMoment) {
        link.play(moment)
        moments.schedule.rule(moment, now: options.clock())
        pump()
    }

    /// The brain's next moment, if its turn has come. On `home`.
    func pump() {
        Runtime.pump(moments, link: link, clock: options.clock, home: home, log: options.log)
    }

    /// Plays the brain's next moment if its turn has come, and sets a timer
    /// for when to look again, unless one is set for no later that the
    /// clock hasn't passed yet. Whatever frees the line sooner (a rule's
    /// animation, a tap, the device's `ended`, "needs you") pumps again at
    /// once. A moment sent with no device connected ends its handle at
    /// once, as failed, and leaves the line free; one sent to the device
    /// goes with an id, and it and its handle wait for the device's
    /// `ended`. On `home`.
    static func pump(_ moments: Moments, link: DeviceLink, clock: @escaping @Sendable () -> Int64,
                     home: DispatchQueue, log: @escaping @Sendable (String) -> Void) {
        let now = clock()
        let due = moments.schedule.due(now: now)
        for moment in due.dropped {
            log("react: dropped a brain moment that waited over \(MomentSchedule.maxWaitMs / 1000) s: \(moment.jsonLine)")
        }
        if var moment = due.play {
            let alone = !link.connected
            if alone {
                moments.schedule.stop(now: now)
            } else if let pending = due.pending {
                moments.send(&moment, pending, now: now)
            }
            moments.brainSending = true
            link.play(moment)
            moments.brainSending = false
            if alone { due.pending?.finish(.failed("no device connected")) }
        }
        guard let next = moments.schedule.next else { return }
        // One set for no later will do, unless the clock has passed it: a
        // timer counts the Mac's uptime, which stops while it sleeps, and
        // the clock doesn't, so it would come late.
        if let at = moments.pumpAt, at <= next, at >= now { return }
        // A timer source, not asyncAfter, whose leeway grows with the wait
        // (a tenth of it): a turn 3 s away came 0.3 s late.
        moments.pumpTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: home)
        timer.schedule(deadline: .now() + .milliseconds(Int(max(1, next - now))), leeway: .milliseconds(5))
        timer.setEventHandler {
            moments.pumpTimer?.cancel()
            moments.pumpTimer = nil
            moments.pumpAt = nil
            pump(moments, link: link, clock: clock, home: home, log: log)
        }
        moments.pumpTimer = timer
        moments.pumpAt = next
        timer.resume()
    }

    func changed() {
        let now = options.clock()
        let status = Status(name: name, snapshot: link.latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                            connected: link.connected, device: link.status, personality: personality,
                            brain: harness.brain?.id ?? "none")
        if options.debug, let line = DebugLog.status(status, at: now, last: &lastStatus) { Harness.appendLine(line, to: debugLogURL) }
        onChange?(status)
    }

    /// The last `status` line written to `debug.jsonl`, without its time.
    var lastStatus: String?

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
            saveSettings { $0.volume = core.config.volume }
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
