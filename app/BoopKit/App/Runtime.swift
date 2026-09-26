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
        /// Override the brain's two stages in `settings.json` for this run
        /// only (HARNESS.md §6).
        public var classifier: String?
        public var writer: String?
        public var time = LocalTime()
        public var clock: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
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
        /// The brain's two stages as they run, e.g. `rules@2` and `apple:26.4`.
        public var classifier: String
        public var writer: String
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool

        public init(snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool, device: DeviceStatus?,
                    classifier: String, writer: String, listening: Bool = false) {
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
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
    let core: Core
    let harness: Harness
    let react: ReactAction
    let lock: InstanceLock
    var server: HookServer?
    var timer: DispatchSourceTimer?
    var projects: [String: String] = [:]
    /// Keeps the brain from cutting off the rules (BEHAVIORS.md §3): a
    /// moment an action sends outside the core's effects is the brain's, and
    /// waits until the rules' last moment has finished playing.
    final class Moments {
        /// Above zero while the core's effects are carried out.
        var inRules = 0
        /// When the rules' last moment ends on the device.
        var rulesUntil: Int64 = 0
        /// The brain's moments waiting for it, and whether a flush is due.
        var held: [DeviceMoment] = []
        var flushDue = false
        /// True while a brain moment is being sent (for `trace`).
        var brainSending = false
    }
    let moments = Moments()

    /// Push-to-talk: start (true) or stop listening. Called on `home`.
    public var onListen: ((Bool) -> Void)?
    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?

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
        var config = Core.Config(name: longTerm.name, volume: settings.volume, time: options.time,
                                 seed: longTerm.seed ^ UInt64(now))
        config.name = longTerm.name
        core = Core(config: config, lastActiveDay: memory.lastActiveDay)

        // Actions reach the rest through closures that are only ever called
        // on `home`, from the core's effects or the harness.
        var route: ([CoreEffect]) -> Void = { _ in }
        let core = self.core
        let link = self.link
        let time = options.time
        let clock = options.clock
        let context = ActionContext(
            send: { [moments, home] moment in
                let now = clock()
                if moments.inRules > 0 {
                    link.play(moment)
                    // As the device times it.
                    moments.rulesUntil = max(moments.rulesUntil, now + moment.playMs)
                    return
                }
                moments.held.append(moment)
                Runtime.flushHeld(moments, link: link, clock: clock, home: home)
            },
            mumblesAllowed: { core.canMumble(at: clock()) },
            setQuiet: { route(core.setQuiet(minutes: $0, at: clock())) },
            quietAsked: { core.quietAsked },
            today: { time.day(clock()) },
            log: log)
        let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: longTerm.seed)), memory: memory)
        react = actions.compactMap { $0 as? ReactAction }.first!
        let memory = self.memory
        harness = Harness(classifier: Brains.classifier(options.classifier ?? settings.classifier, key: Brains.jevKey, log: log),
                          writer: Brains.writer(options.writer ?? settings.writer, log: log),
                          tools: actions.map(Harness.Tool.init), memory: { memory.promptMemory(for: $0.kind) },
                          home: home, debugLog: options.debugLog, log: log)
        // Tool names only: arguments can carry what you said (HARNESS.md §8).
        harness.onRecord = { record in log(record.logLine) }
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
                    + "brain \(harness.classifier.id) + \(harness.writer.id)")
    }

    /// Stops listening for hooks and the device. Safe to call twice.
    public func stop() {
        timer?.cancel()
        timer = nil
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
        let key = line.agent + "/" + line.session
        guard let event = Adapter.event(from: line, receivedAt: received, knownProject: projects[key]) else { return }
        projects[key] = event.project
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
                onListen?(on)
                listenChanged = true
            }
        }
        if stateChanged || listenChanged { changed() }
    }

    /// Sends the brain's held moments once the rules' moment is over, or
    /// checks again then (a newer rule moment pushes them back). On `home`.
    static func flushHeld(_ moments: Moments, link: DeviceLink, clock: @escaping @Sendable () -> Int64,
                          home: DispatchQueue) {
        let wait = moments.rulesUntil - clock()
        if wait <= 0 {
            let held = moments.held
            moments.held = []
            moments.brainSending = true
            held.forEach(link.play)
            moments.brainSending = false
        } else if !moments.flushDue {
            moments.flushDue = true
            home.asyncAfter(deadline: .now() + .milliseconds(Int(wait))) {
                moments.flushDue = false
                flushHeld(moments, link: link, clock: clock, home: home)
            }
        }
    }

    func changed() {
        let now = options.clock()
        onChange?(Status(snapshot: link.latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                         connected: link.connected, device: link.status, classifier: harness.classifier.id,
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

    /// Takes effect on the next launch.
    public func setClassifier(_ classifier: String) {
        home.async { [self] in saveSettings { $0.classifier = classifier } }
    }

    /// Takes effect on the next launch.
    public func setWriter(_ writer: String) {
        home.async { [self] in saveSettings { $0.writer = writer } }
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
