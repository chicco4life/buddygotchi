import AgentHooks
import Foundation

/// Everything the app runs, wired together (ARCHITECTURE.md §1): the hook
/// socket feeds the adapters, and every event goes down the pipeline, into
/// the transcript, the core and the view; the view events that wake the
/// brain go to the harness, the core's snapshots to the device link and a
/// new day to the transcript's pruning; the device's pokes come back as
/// events. The menu-bar app and `Boop --headless` both run one of these.
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
        /// Debug mode (harness/HARNESS.md §9): logs every hook with what the
        /// adapter made of it and every line sent to the device, starts
        /// `debug.jsonl` afresh in the state directory (keeping the last
        /// launches' copies beside it) with every event, view event and
        /// pass and the dashboard's lines, and hands them and the core's
        /// decisions to `debugPrint`, readably.
        public var debug = false
        /// Where debug mode prints (the terminal). Never the log file: it
        /// carries Jev's whole state.
        public var debugPrint: @Sendable (String) -> Void = { _ in }
        /// Jev's key, given the one Boop keeps (`saved`): at start, off
        /// `home` and the main thread, `saved` reads the Keychain, which
        /// may stop to ask for access; after, it's what Settings saved.
        /// Every read of the key goes through here, so tests and headless
        /// runs decide what it is.
        public var readJevKey: @Sendable (_ saved: () -> String?) -> String? = { JevKey.environment() ?? $0() }
        /// The Mac's idle time in ms, read on every tick for the presence
        /// detector (harness/EVENTS.md §2.1): the app's. Nil (headless)
        /// reads none of the Mac's signals: `{"dev":"presence"}` lines
        /// stand in (harness/HARNESS.md §9).
        public var idleMs: (@Sendable () -> Int64)?
        public var log: @Sendable (String) -> Void = { _ in }
        /// Opens a thread on the Mac (`ThreadLink`): a tap while something
        /// needs you, or a click in the popover. Tests pass their own.
        public var open: @Sendable (ThreadLink.Target) -> Bool = ThreadLink.openOnMac

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
        /// Why the link can't look for the device (Bluetooth off), in the
        /// transport's words, for the popover.
        public var linkTrouble: String?
        public var personality: Personality
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String
        /// Jev's key has been read, whether there was one or not. Until
        /// then `brain` is `none` only because it isn't known yet.
        public var keyRead: Bool
        /// The brain failing, for the popover's notice (harness/HARNESS.md §7).
        public var brainTrouble: BrainTrouble?
        /// The Mac's mic is on for push-to-talk (BEHAVIORS.md §3.3).
        public var listening: Bool
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceStatus?, linkTrouble: String? = nil, personality: Personality, brain: String,
                    keyRead: Bool = true, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.linkTrouble = linkTrouble
            self.personality = personality
            self.brain = brain
            self.keyRead = keyRead
            self.brainTrouble = brainTrouble
            self.listening = listening
            self.micTrouble = micTrouble
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

    /// Debug mode's log of every event, view event and pass, in the state directory.
    public let debugLogURL: URL

    /// Each block drains its own autorelease pool: a burst keeps `home`
    /// busy, and what Foundation leaves autoreleased would pile up until
    /// it went idle.
    public let home = DispatchQueue(label: "boop.home", qos: .userInitiated, autoreleaseFrequency: .workItem)
    public let options: Options
    public let link: DeviceLink
    /// Boop's name, from `long-term.md`.
    let name: String
    public private(set) var settings: AppSettings
    /// The personality running now, touched only on `home`. Starts as the
    /// saved one, unless this run overrides it.
    public private(set) var personality: Personality
    let core: Core
    let view: TranscriptView
    let pipeline: Pipeline
    let harness: Harness
    let mood: MoodStore
    let moodAction: MoodAction
    let lock: InstanceLock
    var server: HookServer?
    var timer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then no event wakes the brain.
    var jevKey: String??
    /// Keeps the brain from cutting anything off (BEHAVIORS.md §3): the
    /// tap's poke plays at once, and the brain's moments wait their turn
    /// in it behind the brain's earlier ones, go to the device with an id
    /// and hold its line until the device says how they ended.
    var schedule = MomentSchedule()
    /// The timer set for the brain's next turn, and the time it's set for;
    /// nil when none is.
    var pumpTimer: DispatchSourceTimer?
    var pumpAt: Int64?
    /// The transport's `trouble` as the status last had it. It changes on
    /// the transport's thread, so the tick looks.
    var linkTrouble: String?

    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?

    // Push-to-talk (BEHAVIORS.md §3.3). All on `home`.
    /// Turns the Mac's mic on (true) or off. Once it's off, the app hands
    /// what it heard to `said`, or calls `heardNothing`; with none set
    /// (headless), turning it off hears nothing.
    public var onListen: ((Bool) -> Void)?
    /// Whose button turned the mic on last: what it hears is theirs.
    var talker: Core.Talker = .app
    /// The `seq` of what you said, while its reply may still come: the
    /// first pass on it or anything newer ends `listening` on the device
    /// unless it queued a reaction, which is the reply.
    var replyFor: Int?
    var micTrouble: String?

    // Here and away (harness/EVENTS.md §2.1). All on `home`.
    /// Decides whether you're at the Mac, from where the transcript left it.
    var presence = PresenceDetector()
    /// The idle time `{"dev":"presence","idle_ms":N}` set, read in place of
    /// the Mac's when there's no `idleMs`.
    var devIdleMs: Int64 = 0

    /// A clock that never steps and keeps counting while the Mac sleeps,
    /// starting at the wall clock's time: the keepalive and moments'
    /// turns are measured on it, so setting the Mac's clock back can't stall them
    /// (ARCHITECTURE.md §3.2).
    public static func steadyClock() -> @Sendable () -> Int64 {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let start = ContinuousClock.now
        return { wall + Int64((ContinuousClock.now - start).ms) }
    }

    /// Sets up a new Boop: name and sweet-or-cheeky, asked once.
    /// It hatches `today`, by default the Mac's.
    public static func setUp(stateDir: URL, name: String, nature: LongTerm.Nature,
                             today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) throws {
        let store = try MemoryStore(directory: stateDir)
        try store.setUp(name: name, nature: nature, seed: UInt64.random(in: 1...0xFFFF), today: today)
    }

    public init(_ options: Options) throws {
        self.options = options
        debugLogURL = options.stateDir.appendingPathComponent(DebugLog.fileName)
        guard let lock = InstanceLock(directory: options.stateDir) else { throw OpenError.locked(options.stateDir.path) }
        self.lock = lock
        let log = options.log
        let wall = options.wallClock(), wallAt = options.clock()
        let today = options.time.day(wall)
        guard let longTerm = try MemoryStore(directory: options.stateDir, today: today, log: log).longTerm
        else { throw OpenError.notSetUp }
        name = longTerm.name
        settings = AppSettings.load(from: options.stateDir)
        link = DeviceLink(transport: options.link, log: log)
        let recent = DebugLog.Recent()
        self.recent = recent
        let debugLog = options.debug ? debugLogURL : nil
        if let debugLog { DebugLog.start(debugLog) }
        let printer = DebugLog.Printer()
        let print = options.debugPrint
        let emit = { (line: String) in
            guard let debugLog else { return recent.add(line) }
            LineFile.append(line, to: debugLog)
            printer.readable(line).map(print)
        }
        self.emit = emit
        let clock = options.clock
        // boop.log leaves out a `state` sent again unchanged (the keepalive,
        // a reply to `status`), which debug.jsonl keeps (harness/HARNESS.md §9).
        var lastState: String?
        link.onSend = { line, sender in
            emit(DebugLog.sent(line, by: sender, at: clock()))
            guard debugLog != nil, line != lastState else { return }
            if line.hasPrefix(#"{"t":"state""#) { lastState = line }
            log("link \(sender == .brain ? "brain" : "rules") → " + line)
        }

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        mood = MoodStore(stateDir: options.stateDir, log: log)
        var config = Core.Config(volume: settings.volume, time: options.time, seed: longTerm.seed ^ UInt64(now))
        config.mood = mood.current
        config.firstAsk = Core.randomFirstAsk()
        let places = self.places
        // The launch's read-back prunes the transcript, so today isn't a new day.
        core = Core(config: config, lastActiveDay: today, place: places.place)
        core.setWallClock(wall, at: wallAt)
        view = TranscriptView(rules: rules, seed: longTerm.seed ^ UInt64(now), place: places.place)
        let transcript = Transcript.log(folder: options.stateDir.appendingPathComponent(Transcript.folderName),
                                        time: options.time, note: log)
        pipeline = Pipeline(core: core, transcript: transcript, view: view)
        pipeline.brain = false  // until Jev's key is read
        for over in options.steering.overBudget() { log("steering: over budget: \(over)") }

        // The actions' closures are only ever called on `home`, and reach
        // `self` once it's whole.
        var personalityNow: () -> Personality = { .boop }
        var moodSaved: (String) -> Void = { _ in }
        var queued: (DeviceMoment, Pending) -> Void = { _, _ in }
        let link = self.link
        let home = self.home
        (harness, moodAction) = Runtime.harness(
            brain: nil, pipeline: pipeline, mood: mood, steering: options.steering,
            personality: { personalityNow() }, time: options.time, clock: clock, wall: options.wallClock,
            queue: { queued($0, $1) }, moodChanged: { moodSaved($0) }, speaks: { link.status?.hasTheVoice ?? true },
            home: home, emit: emit, log: log)
        // The questions line is debug.jsonl's first, before the read-back
        // below, the socket or the link can add one, so a changed first
        // line means a new launch.
        emit(DebugLog.questions(harness.actions, at: now))
        // The view and the core pick up where the last launch left them.
        let read = pipeline.readBack(now: now)
        if read > 0 { log("transcript: read back \(read) events, the view has \(view.events.count)") }
        presence = PresenceDetector(away: view.away)
        personalityNow = { [weak self] in self?.personality ?? .boop }
        moodSaved = { [weak self] in self?.moodChanged($0) }
        queued = { [weak self] moment, pending in self?.queue(moment, pending) }
        // A pass can change the mood, which the menu bar shows.
        harness.onRecord = { [weak self] record in
            log(record.logLine)
            self?.replied(record)
            self?.changed()
        }
    }

    /// Boop's actions (harness/DECISIONS.md), in the order they run, and
    /// the harness that asks for them on `pipeline`'s view events: the
    /// app's, and the evals', so the two can't drift apart. `queue` plays
    /// a reaction's moment, `moodChanged` hears a new mood saved, and
    /// `speaks` says whether the device plays Voice's takes. Jev's state
    /// is built at each pass (harness/HARNESS.md §6) from the steering
    /// files, `personality()`, the line that closes HISTORY (the mood's
    /// time in the mood), the oldest working turn at `clock()` and the
    /// time of day at wall-clock time `wall()`. `emit` gets the
    /// `debug.jsonl` lines (harness/HARNESS.md §9): every pass's, and every
    /// event's and view event's as it happens; nil writes none.
    public static func harness(brain: (any Brain)?, pipeline: Pipeline, mood: MoodStore, steering: Steering,
                               personality: @escaping () -> Personality, time: LocalTime,
                               clock: @escaping @Sendable () -> Int64, wall: @escaping () -> Int64,
                               queue: @escaping (DeviceMoment, Pending) -> Void,
                               moodChanged: @escaping (String) -> Void = { _ in }, speaks: @escaping () -> Bool = { true },
                               home: DispatchQueue, emit: ((String) -> Void)? = nil,
                               log: @escaping (String) -> Void = { _ in })
        -> (harness: Harness, mood: MoodAction) {
        let core = pipeline.core
        let view = pipeline.view
        let moodAction = MoodAction(store: mood, clock: clock, changed: moodChanged)
        var acting: () -> ViewEvent? = { nil }
        let react = ReactAction(queue: queue, blocked: { core.reactionBlock }, who: {
            // The thread's name as its agent's app shows it, once an event
            // brought one, else the view's: its workspace, else its project.
            guard let key = acting()?.about, let who = view.who(about: key) else { return nil }
            return DeviceMoment.Who(agent: who.agent, thread: core.name(about: key) ?? who.thread,
                                    opens: core.thread(about: key))
        }, speaks: speaks)
        let harness = Harness(brain: brain, actions: [moodAction, react], pipeline: pipeline, parts: {
            let now = clock()
            let wall = wall()
            return StateText.Parts(guide: steering.guide, personality: steering.personality(personality()).text,
                                   mood: steering.mood(mood.current), closing: moodAction.sinceLine(at: now),
                                   workingSince: view.workingSince(at: now),
                                   clock: "\(time.clock(wall)), \(time.weekday(wall))")
        }, home: home, clock: clock, log: log)
        acting = { [weak harness] in harness?.acting }
        if let emit {
            harness.onDebugLine = emit
            pipeline.onRecord = { emit(DebugLog.event($0)) }
            pipeline.onView = { emit(DebugLog.view($0)) }
        }
        return (harness, moodAction)
    }

    // MARK: Running

    public func start() throws {
        let home = self.home
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
            run(pipeline.tick(at: options.clock()))
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
        home.async { [weak self] in
            self?.pumpTimer?.cancel()
            self?.pumpTimer = nil
            self?.pumpAt = nil
        }
    }

    // MARK: Inputs (on `home`)

    func hook(_ line: HookLine, received: Int64) {
        let event = Adapter.event(from: line, receivedAt: received)
        // Debug mode logs every hook with what it became; the doctor skill
        // arms the plain line to see hooks arrive. Otherwise hooks aren't logged.
        if options.debug {
            options.log("hook: \(line.agent) \(line.hook) \(line.session) → " + (event?.summary ?? "ignored"))
        } else if doctorArmed() {
            options.log("hook: \(line.agent) \(line.hook) \(line.session)")
        }
        guard let event else { return }
        run(pipeline.agent(event))
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
            schedule.failAll("the device disconnected")
            pump()
            run(core.linkDown(at: now))
        }
        changed()
    }

    func device(_ line: String) {
        let now = options.clock()
        switch link.receive(line, now: now) {
        case .tap(let finish):
            options.log("device: input tap" + (finish.map { " on moment \($0)" } ?? ""))
            // A poke (BEHAVIORS.md §3.3). The device has already poked,
            // cutting the animation playing but not a reaction's line or face;
            // on the brain's finish that names whose turn it was it only
            // dipped, and the tap opens that thread.
            run(pipeline.poke(at: now, finish: finish.flatMap { schedule.opens(finish: $0) }))
            pump()
        case .talk(let on):
            options.log("device: input talk_\(on ? "on" : "off")")
            // The device already shows `listening` (BEHAVIORS.md §3.3).
            run(core.listen(on, by: .device, at: now))
            pump()
        case .ended(let ended):
            options.log("device: moment \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            schedule.ended(ended, now: now)
            pump()
        default:
            break
        }
        changed()
    }

    /// A `{"dev":…}` line from the socket (VERIFICATION.md §2):
    /// only with `devLines`. Nothing replies; what it did shows in
    /// `debug.jsonl`.
    func dev(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch object["dev"] as? String {
        case "advance":
            guard let ms = (object["ms"] as? NSNumber)?.int64Value, ms > 0, let advance = options.advance else { return }
            advance(ms)
            options.log("dev: clock advanced \(ms) ms")
            tick()
        case "answer":
            // A forced pass: the actions keep their own rules.
            guard let choices = object["answers"] as? [String: String] else { return }
            options.log("dev: forced pass → " + Harness.ActionRecord.names(harness.force(choices)))
            changed()
        case "mood":
            // The mood action's own change, which tells the device too
            // (harness/DECISIONS.md §4).
            guard let to = object["mood"] as? String else { return }
            let result = harness.force(moodAction) { moodAction.change(to: to) }
            options.log("dev: mood \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
            changed()
        case "said":
            // What push-to-talk heard, without a mic (VERIFICATION.md §2).
            guard let words = object["words"] as? String else { return }
            talker = (object["by"] as? String).flatMap(Core.Talker.init(rawValue:)) ?? .app
            heard(words)
            options.log("dev: said \(words.count) characters")
        case "tap":
            // The device's tap, without a board (VERIFICATION.md §2).
            options.log("dev: tap")
            run(pipeline.poke(at: options.clock()))
            pump()
            changed()
        case "listen":
            // The app's mic button.
            guard let on = object["on"] as? Bool else { return }
            run(core.listen(on, at: options.clock()))
            options.log("dev: listen \(on)")
        case "presence":
            // The Mac's signals and idle time, headless only: the app
            // reads the Mac's own (harness/HARNESS.md §9).
            guard options.idleMs == nil else { return }
            if let ms = (object["idle_ms"] as? NSNumber)?.int64Value {
                devIdleMs = max(0, ms)
                options.log("dev: idle \(devIdleMs) ms")
            }
            if let signal = (object["signal"] as? String).flatMap(PresenceDetector.Signal.init(rawValue:)) {
                options.log("dev: presence \(signal.rawValue)")
                presenceSignal(signal)
            }
        case "report":
            saveReport { _ in }
        default:
            break  // such as boopdev replay's probe
        }
    }

    func tick() {
        let now = options.clock()
        core.setWallClock(options.wallClock(), at: now)
        run(pipeline.tick(at: now))
        if let e = presence.tick(at: now, idleMs: options.idleMs?() ?? devIdleMs) { recordPresence(e) }
        link.tick(now: now)
        schedule.overdue(now: now)
        // A reaction that has waited too long is dropped here too, before
        // the harness's ceiling could end it, even when the pump's timer,
        // which runs on uptime, hasn't fired (the clock jumped).
        pump()
        harness.tick(now: now)
        let trouble = link.transport?.trouble
        if trouble != linkTrouble {
            linkTrouble = trouble
            changed()
        }
    }

    /// You stepped away or came back, as the detector decided: recorded,
    /// and a back wakes the brain (harness/EVENTS.md §2.1).
    func recordPresence(_ e: Event) {
        options.log("presence: \(e.phase == .start ? "away" : "back") (\(e.specificType))")
        run(pipeline.presence(e))
    }

    /// A signal from the Mac for the presence detector.
    func presenceSignal(_ signal: PresenceDetector.Signal) {
        if let e = presence.signal(signal, at: options.clock()) { recordPresence(e) }
    }

    /// The mood action saved a new mood: the device draws it from the next
    /// `state` (PROTOCOL.md §3).
    func moodChanged(_ mood: String) {
        run(core.setMood(mood, at: options.clock()))
    }

    /// Carries out the core's effects from a call outside the pipeline.
    func run(_ effects: [CoreEffect]) {
        var step = Pipeline.Step()
        pipeline.run(effects, &step)
        run(step)
    }

    /// Carries out what an input did (ARCHITECTURE.md §3.2): the core's
    /// effects (its records are in the transcript already), then a pass
    /// for each view event that wakes the brain.
    func run(_ step: Pipeline.Step) {
        var stateChanged = false
        for effect in step.effects {
            switch effect {
            case .state(let snapshot):
                show(snapshot)
                stateChanged = true
            case .sessions:
                stateChanged = true
            case .record:
                break
            case .newDay:
                pipeline.transcript.prune(now: options.clock())
            case .listen(let on, let by):
                listen(on, by: by)
                stateChanged = true
            case .moment(let moment):
                playRule(moment)
            case .open(let thread):
                open(thread, by: "tap")
            }
        }
        harness.take(step.views)
        if stateChanged { changed() }
    }

    /// The core turned the mic on or off (BEHAVIORS.md §3.3). On: the
    /// brain's moments waiting are dropped, since one would end
    /// `listening`, and after the app's button the device is told to show
    /// it (the device's own button already does). Off: what the mic heard
    /// comes back to `said` or `heardNothing`.
    func listen(_ on: Bool, by: Core.Talker) {
        options.log("talk: mic \(on ? "on" : "off") (\(by.rawValue))")
        guard on else {
            if onListen != nil { onListen?(false) } else { heardNothing() }
            return
        }
        talker = by
        micTrouble = nil
        replyFor = nil
        for moment in schedule.dropWaiting() {
            options.log("react: dropped a brain moment waiting when the mic went on: \(moment.jsonLine)")
        }
        if by == .app { link.play(DeviceMoment(anim: DeviceMoment.listening)) }
        onListen?(true)
    }

    /// What the mic heard: an event that wakes the brain, whose pass
    /// replies or ends `listening` (`replied`). With no brain to wake, no
    /// reply is coming, so `listening` ends at once.
    func heard(_ words: String) {
        let step = pipeline.said(words, by: talker, at: options.clock())
        run(step)
        if let v = step.waking.first {
            replyFor = v.seq
        } else {
            endListening()
        }
    }

    /// The first pass on what you said, or on anything newer, is over: if
    /// it queued no reaction, none is coming, so `listening` ends now
    /// (BEHAVIORS.md §3.3).
    func replied(_ record: Harness.Record) {
        guard let seq = replyFor, record.now.seq >= seq else { return }
        replyFor = nil
        if !record.actions.contains(where: { $0.name == "react" && $0.result.ok }) { endListening() }
    }

    /// Ends `listening` on the device with the empty moment, which ends
    /// nothing else (PROTOCOL.md §3).
    func endListening() {
        core.listeningEnded()
        link.play(DeviceMoment())
    }

    /// A snapshot for the device, whose look and mood time the moments
    /// played over it; "needs you" starting stops them.
    func show(_ snapshot: StateSnapshot) {
        let now = options.clock()
        link.update(snapshot, now: now)
        schedule.show(look: snapshot.look, mood: snapshot.mood, attn: snapshot.attn != nil, now: now)
        pump()
    }

    /// A rule's one-shot (BEHAVIORS.md §3.1): it plays at once, after the
    /// `state` of the same input, unless a brain moment's line is playing,
    /// which it would cut: then it's dropped, since a late one-shot is
    /// worse than none. The core has already left it out while something
    /// needs you or `listening` shows.
    func playRule(_ moment: DeviceMoment) {
        let now = options.clock()
        guard schedule.rulePlays(now: now) else {
            options.log("rule: dropped \(moment.anim ?? "a moment") while a brain moment plays")
            return
        }
        link.play(moment)
    }

    /// A reaction's moment from the brain, to play when its turn comes,
    /// and its handle to end once it's known how it went. On `home`.
    func queue(_ moment: DeviceMoment, _ pending: Pending) {
        core.listeningEnded()  // a reaction ends `listening`: it's the reply (BEHAVIORS.md §3.3)
        schedule.brain(moment, pending, now: options.clock())
        pump()
    }

    /// Plays the brain's next moment if its turn has come, and sets a timer
    /// for when to look again, unless one is set for no later that the
    /// clock hasn't passed yet. Whatever frees the line sooner (the
    /// device's `ended`, "needs you") pumps again at once. The schedule ends a moment's handle when no device is
    /// connected, and gives one sent to the device its id. On `home`.
    func pump() {
        let now = options.clock()
        let due = schedule.due(now: now, connected: link.connected)
        for moment in due.dropped {
            options.log("react: dropped a brain moment that waited over \(MomentSchedule.maxWaitMs / 1000) s: \(moment.jsonLine)")
        }
        if let moment = due.play { link.play(moment, by: .brain) }
        guard let next = schedule.next else { return }
        // One set for no later will do, unless the clock has passed it: a
        // timer counts the Mac's uptime, which stops while it sleeps, and
        // the clock doesn't, so it would come late.
        if let at = pumpAt, at <= next, at >= now { return }
        // A timer source, not asyncAfter, whose leeway grows with the wait
        // (a tenth of it): a turn 3 s away came 0.3 s late.
        pumpTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: home)
        timer.schedule(deadline: .now() + .milliseconds(Int(max(1, next - now))), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            pumpTimer?.cancel()
            pumpTimer = nil
            pumpAt = nil
            pump()
        }
        pumpTimer = timer
        pumpAt = next
        timer.resume()
    }

    func changed() {
        let now = options.clock()
        let status = Status(name: name, snapshot: link.latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                            connected: link.connected, device: link.status, linkTrouble: linkTrouble, personality: personality,
                            brain: harness.brain?.id ?? "none", keyRead: jevKey != nil, brainTrouble: harness.trouble,
                            listening: core.listening != nil, micTrouble: micTrouble)
        if let line = DebugLog.status(status, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }

    /// The last `status` line written to `debug.jsonl`, without its time.
    var lastStatus: String?
    /// This launch's debug lines outside debug mode, for `saveReport`: in
    /// debug mode the file has them.
    let recent: DebugLog.Recent
    /// Every `debug.jsonl` line goes through this: in debug mode written to
    /// the file and printed readably, and otherwise kept in `recent`.
    let emit: (String) -> Void

    func saveSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try settings.save(to: options.stateDir) } catch { options.log("settings: can't save: \(error)") }
    }

    // MARK: From the menu bar (any thread)

    /// Opens `thread` where it runs: a session clicked in the popover.
    public func openThread(_ thread: ThreadRef) {
        home.async { [self] in open(thread, by: "click") }
    }

    /// Opens a thread on the Mac, after a tap or a click (BEHAVIORS.md
    /// §3.2). What opened is a log line: only the tap's is Boop's doing,
    /// and the core records it.
    func open(_ thread: ThreadRef, by: String) {
        guard let target = ThreadLink.target(thread) else {
            options.log("open: nowhere to open \(thread.agent) \(thread.session) (\(by)): no app named")
            return
        }
        let opened = options.open(target)
        options.log("open: \(target.arguments.joined(separator: " ")) (\(by))" + (opened ? "" : ": open failed"))
    }

    /// The app's mic button: start or stop listening (BEHAVIORS.md §3.3).
    public func setListening(_ on: Bool) {
        home.async { [self] in run(core.listen(on, at: options.clock())) }
    }

    /// What push-to-talk heard, once the mic is off.
    public func said(_ words: String) {
        home.async { [self] in heard(words) }
    }

    /// The mic went off and heard nothing: no reply is coming.
    public func heardNothing() {
        home.async { [self] in
            options.log("talk: heard nothing")
            endListening()
        }
    }

    /// The mic or speech recognition couldn't start, and why, for the
    /// popover: `listening` ends at once, after either button.
    public func micFailed(_ why: String) {
        home.async { [self] in
            options.log("talk: \(why)")
            micTrouble = why
            endListening()
            changed()
        }
    }

    /// A lock, unlock, sleep or wake from the Mac, for the presence
    /// detector (harness/EVENTS.md §2.1).
    public func presence(_ signal: PresenceDetector.Signal) {
        home.async { [self] in presenceSignal(signal) }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() {
        home.async { [self] in
            micTrouble = nil
            changed()
        }
    }

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

    /// A new personality (BEHAVIORS.md §6): the view's rules and Jev's
    /// state from the next event.
    public func setPersonality(_ personality: Personality) {
        home.async { [self] in
            self.personality = personality
            saveSettings { $0.personality = personality }
            view.setRules(options.steering.personality(personality).rules)
            options.log("personality \(personality.rawValue)")
            changed()
        }
    }

    /// Jev's key as Settings just saved it (nil when it was cleared);
    /// `BOOP_JEV_KEY` still wins. Used from the next event.
    public func reloadBrain(jevKey key: String?) {
        home.async { [self] in
            jevKey = .some(options.readJevKey { key })
            useBrain()
            changed()
        }
    }

    /// The brain for Jev's key as far as it's been read. On `home`.
    func useBrain() {
        let brain = options.brain(jevKey ?? nil)
        harness.use(brain)
        pipeline.brain = brain != nil
        options.log("brain \(brain?.id ?? "none")" + (brain == nil ? ": no Jev key, so Boop does only its rule reactions" : ""))
    }

    /// Reads Jev's key off `home` (harness/HARNESS.md §7): a Keychain prompt
    /// there would stall every hook, tick and device line until it's
    /// answered. Then the brain is built with it. On `home`.
    func readJevKey() {
        guard jevKey == nil else { return }
        let read = options.readJevKey
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let key = read { Keychain.jevKey() }
            self?.home.async { [weak self] in
                guard let self else { return }
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
