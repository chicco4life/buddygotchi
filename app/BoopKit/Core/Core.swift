import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides what the device shows, the rule reactions,
/// quiet, and which inputs reach the brain.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
/// The time is a steady clock, so a change to the Mac's clock can't stretch
/// a timer; days and times of day follow the wall clock the app reports
/// with `setWallClock`.
public final class Core {
    public struct Config: Sendable {
        public var name: String
        public var volume: Int
        /// The personality's settings: which finishes cheer, how often
        /// chatter plays and which tool uses wake the brain (BEHAVIORS.md §6).
        public var rules: Personality.Rules
        public var time: LocalTime
        public var seed: UInt64
        /// Codex's grace period before "needs you" shows (ADAPTERS.md §4).
        public var codexGraceMs: Int64 = 2000
        /// "Needs you" clears anyway after this long with no events, and
        /// the session goes idle (ADAPTERS.md §4).
        public var safetyNetMs: Int64 = 10 * 60 * 1000
        /// A working session with no events for this long counts as idle.
        public var staleWorkMs: Int64 = 60 * 60 * 1000
        /// A session with no events for this long is forgotten.
        public var forgetMs: Int64 = 24 * 60 * 60 * 1000
        /// A poke streak is this many taps within `pokeWindowMs`, and it
        /// reaches the brain at most once every `pokedEveryMs`
        /// (BEHAVIORS.md §3.3).
        public var pokeTaps = 4
        public var pokeWindowMs: Int64 = 3000
        public var pokedEveryMs: Int64 = 60_000
        /// Whether there's a brain to wake: false without Jev's key, so no
        /// event wakes it (harness/EVENTS.md §6).
        public var brain = true
        /// While no thread works, a heartbeat after this long with no event,
        /// and again every time as long again passes (harness/EVENTS.md §4).
        public var heartbeatMs: Int64 = 60 * 60 * 1000

        public init(name: String, volume: Int = 6, rules: Personality.Rules = Personality.Rules(), time: LocalTime = LocalTime(),
                    seed: UInt64 = 1) {
            self.name = name
            self.volume = volume
            self.rules = rules
            self.time = time
            self.seed = seed
        }
    }

    public enum ToolUses: String, Sendable { case notable, all }

    enum Status { case idle, working, waiting }

    struct Session {
        var agent: Agent
        var id: String
        var project: String
        var status: Status = .idle
        var turnStartedAt: Int64?
        var lastEventAt: Int64
        var topic: String?
        /// This turn's last test, build or deploy command, and whether it
        /// failed (BEHAVIORS.md §3.1).
        var check: (topic: String, failed: Bool)?
        /// When "needs you" started showing.
        var needsSince: Int64?
        /// Codex: when "needs you" arrived, during the grace period.
        var pendingSince: Int64?
        /// When "needs you" last cleared, to drop a late duplicate.
        var clearedAt: Int64?
        /// Who is asking, while "needs you" waits: `""` for the main agent,
        /// a Claude subagent's id, or `Core.anyone` for a `Notification` with
        /// no request before it. Only an asker's own next event answers it
        /// (ADAPTERS.md §4).
        var askers: Set<String> = []
        let order: Int

        // The thread, for events (harness/EVENTS.md §3–4).
        var workspace: String?
        /// Turns started since Boop first saw the thread.
        var turns = 0
        var lastTurnEndedAt: Int64?
        /// This turn's tool calls, and how many failed.
        var tools = 0
        var toolsFailed = 0
        /// This turn's topics, in the order first seen, with their last state.
        var topicStates: [(topic: String, state: String)] = []
        /// A topic that passed after failing this turn.
        var comeback: String?
        /// Failures in a row of each check topic, across turns.
        var failRuns: [String: Int] = [:]
        /// Each running tool call's start and topic, by `tool_use_id`, and the
        /// last one's, for a result that carries no ID or topic.
        var toolStarts: [String: (at: Int64, topic: String?)] = [:]
        var lastToolStart: (at: Int64, topic: String?)?

        /// What lines call the thread: its workspace, or its project.
        var name: String { workspace ?? project }

        var key: String { Core.key(agent, id) }
    }

    public private(set) var config: Config

    var sessions: [String: Session] = [:]
    var nextOrder = 0
    var rng: SplitMix64
    var quietUntil: Int64 = 0
    /// The last day with any activity; a new one starts short-term memory
    /// fresh.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    var nextChatterAt: Int64?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0

    // Push-to-talk (UX.md §5).
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// Talk button.
    public enum Talker: Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// While the Mac's mic is on: who turned it on, and when.
    public private(set) var listening: (by: Talker, since: Int64)?
    // Poke streaks (BEHAVIORS.md §3.3).
    var taps: [Int64] = []
    var pokedAt: Int64?

    // Heartbeats (harness/EVENTS.md §4).
    /// The last hook or device input.
    var lastActivityAt: Int64?
    /// Heartbeats sent since then.
    var heartbeats = 0

    /// `lastActiveDay` is today's date from `short-term.md`, if there is one,
    /// so a restart doesn't start the day again.
    public init(config: Config, lastActiveDay: String? = nil) {
        self.config = config
        self.lastActiveDay = lastActiveDay
        rng = SplitMix64(seed: config.seed)
    }

    static func key(_ agent: Agent, _ id: String) -> String { agent.rawValue + "/" + id }

    /// The topics whose failing command fails a turn (BEHAVIORS.md §3.1).
    static let checks: Set<String> = ["tests", "build", "deploy"]

    /// The asker of a request that came as a `Notification` alone, which
    /// doesn't say who asked: any event from the session answers it.
    static let anyone = "*"

    // MARK: - Inputs

    /// An agent event from an adapter.
    @discardableResult
    public func handle(_ event: BoopEvent) -> [CoreEffect] {
        let now = event.ts
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)

        let key = Core.key(event.agent, event.session)
        var s = sessions[key] ?? Session(agent: event.agent, id: event.session, project: event.project,
                                         lastEventAt: now, order: takeOrder())
        if event.project != "unknown" {
            s.project = event.project
            s.workspace = event.workspace
        }
        let waiting = s.needsSince != nil || s.pendingSince != nil
        noteActivity(now)

        if event.event == .needsYou {
            // A tool-less one while waiting is the same request (PermissionRequest
            // and its Notification), and one just after a clear is the
            // Notification arriving late. A request from another agent in the
            // session (a sibling subagent) joins the one waiting.
            let asker = event.detail.tool == nil ? Core.anyone : event.subagent ?? ""
            let lateDuplicate = event.detail.tool == nil && s.clearedAt.map { now - $0 < 5000 } == true
            if waiting {
                if event.detail.tool != nil { s.askers.insert(asker) }
            } else if !lateDuplicate {
                s.askers = [asker]
                if event.agent == .codex {
                    s.pendingSince = now
                    s.status = .working
                } else {
                    s.needsSince = now
                    s.status = .waiting
                    needsYouEvent(s, now, &fx)
                }
            }
            s.lastEventAt = now
            sessions[key] = s
            publish(now, &fx)
            return fx
        }

        // The asker's next event means it moved on, and so does any
        // turn-level event. A sibling subagent's tool calls don't answer
        // another agent's request. Claude's idle notice (`turn_stopped` with
        // no tool) never comes while the main agent's prompt is up, so it
        // answers the main agent (you pressed Esc on its prompt, which sends
        // no hook), and a request with no tool unless a subagent asked too;
        // a subagent's prompt may still be up (ADAPTERS.md §4).
        if waiting {
            if event.event == .turnStopped && event.detail.tool == nil {
                s.askers.remove("")
                if s.askers == [Core.anyone] { s.askers.removeAll() }
            } else if event.event != .activity || s.askers.contains(Core.anyone) {
                s.askers.removeAll()
            } else {
                s.askers.remove(event.subagent ?? "")
            }
            if s.askers.isEmpty {
                clearRequest(&s, now)
                s.status = .working
            }
        }
        s.lastEventAt = now

        switch event.event {
        case .sessionStart:
            sessions[key] = s
        case .turnStart:
            let gap = s.lastTurnEndedAt.map { Band.gap(ms: now - $0) }
            s.status = .working
            s.turnStartedAt = now
            s.topic = nil
            s.check = nil
            s.turns += 1
            s.tools = 0
            s.toolsFailed = 0
            s.topicStates = []
            s.comeback = nil
            sessions[key] = s
            turnStartEvent(s, gap: gap, now, &fx)
        case .activity:
            s.status = .working
            if s.turnStartedAt == nil { s.turnStartedAt = now }
            var event = event
            if event.detail.done {
                // A result may come without its call's topic: it's the
                // `PreToolUse`'s, by ID or else the last one.
                let started = event.detail.toolUseID.flatMap { s.toolStarts.removeValue(forKey: $0) } ?? s.lastToolStart
                if event.detail.topic == nil { event.detail.topic = started?.topic }
                toolDone(&s, event, started: started?.at, now, &fx)
            } else if event.detail.tool != nil {
                let start = (at: now, topic: event.detail.topic)
                if let id = event.detail.toolUseID { s.toolStarts[id] = start }
                s.lastToolStart = start
            }
            if let topic = event.detail.topic { s.topic = topic }
            if let topic = event.detail.topic, let failed = event.detail.failed, Core.checks.contains(topic) {
                s.check = (topic, failed)
            }
            sessions[key] = s
        case .turnEnd:
            let ms = s.turnStartedAt.map { now - $0 } ?? 0
            let check = s.check
            s.status = .idle
            s.turnStartedAt = nil
            s.check = nil
            s.lastTurnEndedAt = now
            if let check, check.failed {
                // It left its tests, build or deploy failing: a failure, not
                // a finish.
                s.topic = check.topic
                sessions[key] = s
                failed(s, durationMs: ms, error: nil, now, &fx)
                turnEndEvent(s, outcome: "failed", error: nil, lengthMs: ms, reaction: nil, now, &fx)
            } else {
                sessions[key] = s
                let cheered = finished(s, durationMs: ms, now, &fx)
                turnEndEvent(s, outcome: "done", error: nil, lengthMs: ms,
                             reaction: cheered ? EventLine.cheered : nil, now, &fx)
            }
        case .turnFailed:
            let ms = s.turnStartedAt.map { now - $0 } ?? 0
            s.status = .idle
            s.turnStartedAt = nil
            s.check = nil
            s.lastTurnEndedAt = now
            sessions[key] = s
            failed(s, durationMs: ms, error: event.detail.error, now, &fx)
            turnEndEvent(s, outcome: "failed", error: event.detail.error, lengthMs: ms, reaction: nil, now, &fx)
        case .sessionEnd:
            sessions[key] = nil
        case .turnStopped:
            // Over without finishing (ADAPTERS.md §3): a working session goes
            // idle, with no reaction and nothing for the brain.
            if s.status == .working {
                let ms = s.turnStartedAt.map { now - $0 } ?? 0
                s.status = .idle
                s.turnStartedAt = nil
                s.check = nil
                s.lastTurnEndedAt = now
                if s.turns > 0 {
                    turnEndEvent(s, outcome: "stopped", error: nil, lengthMs: ms, reaction: nil, now, &fx)
                }
            }
            sessions[key] = s
        case .needsYou:
            break
        }
        publish(now, &fx)
        return fx
    }

    /// An `input` message's `k` (PROTOCOL.md §4).
    public enum DeviceInput: String, Sendable {
        case tap, talkOn = "talk_on", talkOff = "talk_off"
    }

    /// An `input` message from the device. The device has already reacted.
    @discardableResult
    public func input(_ input: DeviceInput, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        noteActivity(now)
        switch input {
        case .tap:
            tapped(now, &fx)
        case .talkOn:
            // The device already shows `listening`, and holds it after the
            // release until the reply, or for at most 8 s.
            startListening(by: .device, now, &fx)
        case .talkOff:
            stopListening(now, &fx)
        }
        publish(now, &fx)
        return fx
    }

    /// What the person said on push-to-talk. Talk is inert for now
    /// (BEHAVIORS.md §3.3): the words go nowhere.
    @discardableResult
    public func talk(_ words: String, yelled: Bool = false, at now: Int64) -> [CoreEffect] { [] }

    /// The app's Talk button: start or stop listening. The device shows
    /// `listening` while the mic is on; the Mac ends it when the mic goes
    /// off, since no reply is coming (BEHAVIORS.md §3.3).
    @discardableResult
    public func listen(_ on: Bool, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        if on {
            if listening == nil {
                startListening(by: .app, now, &fx)
                play("listening", &fx)
            }
        } else {
            stopListening(now, &fx)
        }
        publish(now, &fx)
        return fx
    }

    /// The link to the device dropped, so its button's release can't arrive:
    /// stop listening now. The app's Talk button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        if listening?.by == .device { stopListening(now, &fx) }
        return fx
    }

    /// The Mac's mic or speech recognition couldn't start: the device's
    /// `listening` face ends at once, after either button.
    @discardableResult
    public func micFailed(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        if listening == nil { fx.append(.endListening) } else { stopListening(now, &fx) }
        return fx
    }

    /// Quiet mode: no mumbles for `minutes` (0 ends it). Nothing turns it on
    /// while talk is inert (BEHAVIORS.md §4).
    @discardableResult
    public func setQuiet(minutes: Int, at now: Int64) -> [CoreEffect] {
        quietUntil = minutes > 0 ? now + Int64(minutes) * 60_000 : 0
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    @discardableResult
    public func setVolume(_ volume: Int, at now: Int64) -> [CoreEffect] {
        config.volume = max(0, min(10, volume))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The wall clock's time at the steady time `now`: days and times of
    /// day follow it, and timers don't (ARCHITECTURE.md §3.2).
    public func setWallClock(_ wallMs: Int64, at now: Int64) {
        wallOffsetMs = wallMs - now
    }

    /// A new personality's settings (BEHAVIORS.md §6), from the next event
    /// on. Working chatter starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        config.rules = rules
        nextChatterAt = nil
    }

    /// Whether there's a brain to wake: Jev's key saved or removed.
    public func setBrain(_ available: Bool) { config.brain = available }

    /// Timers: the Codex grace period, the safety net, quiet running out,
    /// chatter, heartbeats and the push-to-talk limit.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        if let l = listening, now - l.since >= Self.listenLimitMs {
            // The device's own button hits the same limit.
            stopListening(now, &fx)
        }
        publish(now, &fx)
        return fx
    }

    // MARK: - Reading

    /// The sessions in the order the popover lists them: those that need
    /// you (oldest first), then working, then idle.
    func grouped(at now: Int64) -> (waiting: [Session], working: [Session], idle: [Session]) {
        let waiting = sessions.values.filter { $0.needsSince != nil }.sorted { ($0.needsSince!, $0.order) < ($1.needsSince!, $1.order) }
        let working = sessions.values.filter { $0.needsSince == nil && isWorking($0, now) }.sorted { $0.order < $1.order }
        let idle = sessions.values.filter { $0.needsSince == nil && !isWorking($0, now) }.sorted { $0.order < $1.order }
        return (waiting, working, idle)
    }

    public func snapshot(at now: Int64) -> StateSnapshot {
        let (waiting, working, idle) = grouped(at: now)
        let base = !working.isEmpty ? "working" : sessions.isEmpty ? "asleep" : "idle"
        let attn = waiting.first.map {
            StateSnapshot.Attention(
                agent: $0.agent.short, project: StateSnapshot.clip($0.project, marked: true), more: waiting.count - 1)
        }
        return StateSnapshot(
            time: wall(now) / 1000, name: StateSnapshot.clip(config.name), base: base, attn: attn,
            busy: working.count, idle: idle.count, wait: waiting.count,
            quiet: quietLeft(now), vol: config.volume)
    }

    /// Every session, for the popover's list (UX.md §7). The device doesn't
    /// get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (waiting, working, idle) = grouped(at: now)
        return waiting.map { SessionSummary($0, .waiting) } + working.map { SessionSummary($0, .working) }
            + idle.map { SessionSummary($0, .idle) }
    }

    /// Why a mumble can't play now, or nil: quiet mode, something needs
    /// you, or the mic is on, since a mumble would end `listening`
    /// (BEHAVIORS.md §3.3).
    public func mumbleBlock(at now: Int64) -> String? {
        if needsYouShowing { return "something needs you" }
        if quietLeft(now) > 0 { return "quiet mode" }
        if listening != nil { return "the mic is on" }
        return nil
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

    /// The time of day, weekday and date at steady time `now`, on the wall
    /// clock: the calendar never sees steady time.
    private func clock(_ now: Int64) -> String { config.time.clock(wall(now)) }
    private func weekday(_ now: Int64) -> String { config.time.weekday(wall(now)) }
    private func day(_ now: Int64) -> String { config.time.day(wall(now)) }

    func takeOrder() -> Int {
        nextOrder += 1
        return nextOrder
    }

    func isWorking(_ s: Session, _ now: Int64) -> Bool {
        s.status == .working && now - s.lastEventAt < config.staleWorkMs
    }

    var needsYouShowing: Bool { sessions.values.contains { $0.needsSince != nil } }

    func quietLeft(_ now: Int64) -> Int {
        quietUntil > now ? Int((quietUntil - now + 59_999) / 60_000) : 0
    }

    /// Mumbles never play in quiet mode, or while something needs you.
    func mumblesAllowed(_ now: Int64) -> Bool {
        quietLeft(now) == 0 && !needsYouShowing
    }

    /// The mic is on.
    func talking(_ now: Int64) -> Bool { listening != nil }

    /// Nobody is waiting on the session any more.
    func clearRequest(_ s: inout Session, _ now: Int64) {
        s.needsSince = nil
        s.pendingSince = nil
        s.askers.removeAll()
        s.clearedAt = now
    }

    /// The first activity of a new day: short-term memory starts fresh.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = day(now)
        guard today != lastActiveDay else { return }
        lastActiveDay = today
        fx.append(.newDay(date: today, firstSeen: clock(now)))
    }

    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening == nil else { return }
        listening = (talker, now)
        fx.append(.listen(true))
    }

    /// Turns the mic off, if it's on, and ends `listening` at once: no
    /// reply is coming while talk is inert.
    func stopListening(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening != nil else { return }
        listening = nil
        fx.append(.listen(false))
        fx.append(.endListening)
    }

    /// Plays a rule moment now. The device replaces one that's playing.
    func play(_ anim: String, _ fx: inout [CoreEffect]) {
        fx.append(.moment(anim: anim))
    }

    /// A finished turn: a cheer, even while other sessions are still
    /// working, as the personality allows (BEHAVIORS.md §3.1).
    /// None while you talk to Boop (BEHAVIORS.md §3.3).
    @discardableResult
    func finished(_ s: Session, durationMs ms: Int64, _ now: Int64, _ fx: inout [CoreEffect]) -> Bool {
        let cheer = config.rules.cheers(lengthMs: ms) && !talking(now)
        if cheer { play("cheer", &fx) }
        if ms >= 30_000 {
            fx.append(.happened("\(clock(now)) \(s.agent.short) · \(s.project) · finished (\(Band.took(ms)))"))
        }
        return cheer
    }

    /// A tap is the rules' alone: the device wiggles, and the brain only
    /// hears of it. The fourth tap within 3 s is a poke streak
    /// (BEHAVIORS.md §3.3): an event that wakes the brain, at most once a
    /// minute, which may grumble back with a mumble. The rules add no
    /// animation of their own: the device has already wiggled. While
    /// something needs you a tap means "I saw it", so it isn't counted.
    func tapped(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard !needsYouShowing else {
            taps.removeAll()
            fx.append(.event(Event(.tap, at: now, line: EventLine.tap, wakesBrain: false)))
            return
        }
        taps = taps.filter { now - $0 < config.pokeWindowMs } + [now]
        guard taps.count >= config.pokeTaps else {
            fx.append(.event(Event(.tap, at: now, line: EventLine.tap, reaction: EventLine.wiggled, wakesBrain: false)))
            return
        }
        let count = taps.count
        let seconds = max(1, Int((now - taps[0] + 999) / 1000))
        taps.removeAll()
        let sinceLast = pokedAt.map { Band.gap(ms: now - $0) }
        let tooSoon = pokedAt.map { now - $0 < config.pokedEveryMs } == true
        let line = EventLine.pokes(count: count, seconds: seconds, sinceLast: sinceLast)
        let facts: [String: JSONValue] = ["count": .int(Int64(count)), "seconds": .int(Int64(seconds)),
                                          "since_last": .of(sinceLast)]
        if tooSoon {
            fx.append(.event(Event(.pokes, at: now, line: line, reaction: EventLine.wiggled, wakesBrain: false, facts: facts)))
            return
        }
        pokedAt = now
        fx.append(.event(Event(.pokes, at: now, line: line, reaction: EventLine.wiggled,
                               wakesBrain: wakes(now), facts: facts)))
    }

    /// A failed turn: no moment of its own; the session just goes idle
    /// (BEHAVIORS.md §3.1). The brain still hears of it.
    func failed(_ s: Session, durationMs ms: Int64, error: String?, _ now: Int64, _ fx: inout [CoreEffect]) {
        let topic = s.topic.map { " · \($0)" } ?? ""
        fx.append(.happened("\(clock(now)) \(s.agent.short) · \(s.project)\(topic) · failed"))
    }

    /// Nothing wakes the brain while something needs you, or in quiet mode.
    func inputsAllowed(_ now: Int64) -> Bool {
        !needsYouShowing && quietLeft(now) == 0
    }

    /// Runs every timer due by `now`, in order.
    func advance(to now: Int64, _ fx: inout [CoreEffect]) {
        for (key, var s) in sessions {
            let silent = now - s.lastEventAt >= config.safetyNetMs
            if let pending = s.pendingSince, !silent, now - pending >= config.codexGraceMs {
                s.pendingSince = nil
                s.needsSince = pending + config.codexGraceMs
                s.status = .waiting
                needsYouEvent(s, now, &fx)
            }
            if silent && (s.needsSince != nil || s.pendingSince != nil) {
                // Ten silent minutes, even for a Codex request no tick saw
                // through its grace (the Mac slept): the agent is still
                // waiting on its prompt, or gone. Either way it isn't
                // working, so no sweat drop and no chatter. Its turn, if it
                // goes on, still counts from its start.
                clearRequest(&s, now)
                s.status = .idle
            }
            if now - s.lastEventAt >= config.forgetMs {
                sessions[key] = nil
            } else {
                sessions[key] = s
            }
        }
        if quietUntil != 0 && quietUntil <= now { quietUntil = 0 }

        chatter(now, &fx)
        heartbeat(now, &fx)
    }

    /// Working chatter (BEHAVIORS.md §2): while agents work, a mumble every
    /// so often, as the personality sets. About half the time it asks
    /// about a working session's latest topic (`curious`); otherwise it's
    /// `happy`, with no word. None while you talk to Boop: it would end the
    /// `listening` face before the reply.
    func chatter(_ now: Int64, _ fx: inout [CoreEffect]) {
        let working = sessions.values.filter { isWorking($0, now) && $0.needsSince == nil }
        guard !working.isEmpty, let gap = config.rules.chatterMs else {
            nextChatterAt = nil
            return
        }
        guard let due = nextChatterAt else {
            nextChatterAt = now + Int64(rng.int(in: gap))
            return
        }
        guard now >= due else { return }
        nextChatterAt = now + Int64(rng.int(in: gap))
        guard mumblesAllowed(now), !talking(now) else { return }
        let topics = working.sorted { $0.order < $1.order }.compactMap(\.topic)
        let word = !topics.isEmpty && rng.chance(50) ? topics[rng.int(in: 0...(topics.count - 1))] : nil
        fx.append(.mumble(feeling: word == nil ? "happy" : "curious", word: word))
    }

    // MARK: - Events (harness/EVENTS.md)

    /// Whether an event whose kind wakes the brain does: never while
    /// something needs you, in quiet mode, or with no brain (EVENTS.md §6).
    func wakes(_ now: Int64) -> Bool {
        config.brain && inputsAllowed(now)
    }

    func noteActivity(_ now: Int64) {
        lastActivityAt = now
        heartbeats = 0
    }

    /// The thread's facts (EVENTS.md §3).
    func threadFacts(_ s: Session) -> JSONValue {
        [
            "name": .string(s.name), "agent": .string(s.agent.short), "turn": .int(Int64(s.turns)),
            "project": .string(s.project), "workspace": .of(s.workspace), "session": .string(s.id),
        ]
    }

    func threadLine(_ s: Session) -> String { EventLine.thread(name: s.name, project: s.project) }

    func turnStartEvent(_ s: Session, gap: String?, _ now: Int64, _ fx: inout [CoreEffect]) {
        let line = EventLine.turnStart(agent: s.agent.short, turn: s.turns, thread: threadLine(s), gap: gap)
        fx.append(.event(Event(.turnStart, at: now, line: line, wakesBrain: wakes(now), about: s.key,
                               facts: ["thread": threadFacts(s), "gap": .of(gap)])))
    }

    func turnEndEvent(_ s: Session, outcome: String, error: String?, lengthMs: Int64, reaction: String?,
                      _ now: Int64, _ fx: inout [CoreEffect]) {
        let topics = s.topicStates.map { ($0.topic, $0.state) }
        let line = EventLine.turnEnd(agent: s.agent.short, turn: s.turns, thread: threadLine(s), outcome: outcome,
                                     error: error, lengthMs: lengthMs, tools: s.tools, toolsFailed: s.toolsFailed,
                                     topics: topics, comeback: s.comeback)
        var topicFacts: [String: JSONValue] = [:]
        for (topic, state) in topics { topicFacts[topic] = .string(state) }
        fx.append(.event(Event(.turnEnd, at: now, line: line, reaction: reaction, wakesBrain: wakes(now), about: s.key,
                               facts: ["thread": threadFacts(s), "outcome": .string(outcome), "error": .of(error),
                                       "length": .string(Band.length(ms: lengthMs)), "length_ms": .int(lengthMs),
                                       "tools": .int(Int64(s.tools)), "tools_failed": .int(Int64(s.toolsFailed)),
                                       "topics": .object(topicFacts), "comeback": .of(s.comeback)])))
    }

    /// A finished tool call: counted for the turn, and an event when it's
    /// notable, or for every one with `tool_uses: all` (EVENTS.md §4).
    func toolDone(_ s: inout Session, _ event: BoopEvent, started: Int64?, _ now: Int64, _ fx: inout [CoreEffect]) {
        let d = event.detail
        let tookMs = started.map { max(0, now - $0) }
        s.tools += 1
        if d.failed == true { s.toolsFailed += 1 }

        var failedBefore = 0
        var notable = false
        if let topic = d.topic {
            if Core.checks.contains(topic), let failed = d.failed {
                failedBefore = s.failRuns[topic] ?? 0
                if failed {
                    s.failRuns[topic] = failedBefore + 1
                    notable = true
                } else {
                    s.failRuns[topic] = 0
                    if failedBefore > 0 {
                        notable = true
                        s.comeback = topic
                    }
                }
                setTopic(&s, topic, failed ? "failing" : "passing")
            } else if topic == "docs" {
                setTopic(&s, topic, "edited")
            }
        }
        guard notable || config.rules.toolUses == .all else { return }

        let category = EventLine.category(tool: d.tool)
        let result = d.failed.map { $0 ? "failed" : "ok" } ?? "unknown"
        let line = notable
            ? EventLine.check(agent: s.agent.short, topic: d.topic!, thread: threadLine(s), failed: d.failed!,
                              failedBefore: failedBefore, error: d.toolError)
            : EventLine.routine(agent: s.agent.short, category: category, thread: threadLine(s), failed: d.failed)
        var facts: [String: JSONValue] = [
            "thread": threadFacts(s), "tool": .string(category), "tool_name": .of(d.tool), "tool_use_id": .of(d.toolUseID),
            "topic": .of(d.topic), "result": .string(result), "error": .of(d.toolError),
            "failed_before": .int(Int64(failedBefore)),
        ]
        if let tookMs {
            facts["took"] = .string(Band.length(ms: tookMs))
            facts["took_ms"] = .int(tookMs)
        }
        if let type = event.subagentType { facts["subagent"] = .string(type) }
        fx.append(.event(Event(.toolUse, at: now, line: line, wakesBrain: wakes(now), about: s.key, facts: facts)))
    }

    func setTopic(_ s: inout Session, _ topic: String, _ state: String) {
        if let i = s.topicStates.firstIndex(where: { $0.topic == topic }) {
            s.topicStates[i].state = state
        } else {
            s.topicStates.append((topic, state))
        }
    }

    func needsYouEvent(_ s: Session, _ now: Int64, _ fx: inout [CoreEffect]) {
        fx.append(.event(Event(.needsYou, at: now, line: EventLine.needsYou(agent: s.agent.short, thread: threadLine(s)),
                               wakesBrain: false, about: s.key, facts: ["thread": threadFacts(s)])))
    }

    /// While no thread works, an hour with no event brings a heartbeat, and
    /// so does every hour after that until one arrives (EVENTS.md §4).
    func heartbeat(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let last = lastActivityAt, !sessions.values.contains(where: { isWorking($0, now) }) else { return }
        let hours = (now - last) / config.heartbeatMs
        guard hours > Int64(heartbeats) else { return }
        heartbeats = Int(hours)
        fx.append(.event(Event(.heartbeat, at: now, line: EventLine.heartbeat(hours: Int(hours)),
                               wakesBrain: wakes(now), facts: ["idle_hours": .int(hours)])))
    }

    /// When the oldest turn still working began, or nil: HISTORY reaches
    /// back at least that far (harness/HARNESS.md §5.3).
    public func workingSince(at now: Int64) -> Int64? {
        sessions.values.filter { isWorking($0, now) }.compactMap(\.turnStartedAt).min()
    }

    /// The status line that closes HISTORY: every thread working now but
    /// the one `about` names (EVENTS.md §8).
    public func statusLine(excluding about: String?, at now: Int64) -> String {
        let others = sessions.values.filter { isWorking($0, now) && $0.key != about }.sorted { $0.order < $1.order }
        guard !others.isEmpty else { return "Working now: nothing else." }
        let parts = others.map { s in
            "\"\(s.name)\" (\(s.agent.short)\(s.name == s.project ? "" : ", \(s.project)")), for \(Band.took(now - (s.turnStartedAt ?? now)))"
        }
        return "Working now: " + parts.joined(separator: "; ") + "."
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        let snapshot = snapshot(at: now)
        guard !snapshot.sameContent(as: lastPublished) else { return }
        lastPublished = snapshot
        // The picture changes before any moment plays on top of it.
        fx.insert(.state(snapshot), at: 0)
    }
}

/// One session as the popover lists it.
public struct SessionSummary: Equatable, Sendable {
    public enum Status: String, Sendable { case waiting, working, idle }

    /// `claude` or `codex`.
    public var agent: String
    public var project: String
    public var status: Status

    public init(agent: String, project: String, status: Status) {
        self.agent = agent
        self.project = project
        self.status = status
    }

    init(_ s: Core.Session, _ status: Status) {
        self.init(agent: s.agent.short, project: s.project, status: status)
    }
}
