import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides what the device shows, the rule reactions,
/// quiet, and which inputs reach the brain.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
public final class Core {
    public struct Config: Sendable {
        public var name: String
        public var volume: Int
        /// How much Boop reacts: its chatter and which finishes cheer.
        public var mode: Mode
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
        /// Agent inputs within this window merge into one.
        public var mergeMs: Int64 = 3000
        /// A poke streak is this many taps within `pokeWindowMs`, and it
        /// reaches the brain at most once every `pokedEveryMs`
        /// (BEHAVIORS.md §3.3, proposed).
        public var pokeTaps = 4
        public var pokeWindowMs: Int64 = 3000
        public var pokedEveryMs: Int64 = 60_000

        public init(name: String, volume: Int = 6, mode: Mode = .normal, time: LocalTime = LocalTime(), seed: UInt64 = 1) {
            self.name = name
            self.volume = volume
            self.mode = mode
            self.time = time
            self.seed = seed
        }
    }

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

    // Merging bursts of agent inputs.
    var lastInputAt: Int64 = -1_000_000
    var heldInput: (input: Input, rank: Int, count: Int)?

    // Push-to-talk (UX.md §5).
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// Talk button.
    public enum Talker: Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// While the Mac's mic is on: who turned it on, and when.
    public private(set) var listening: (by: Talker, since: Int64)?
    /// After the Talk button's mic goes off, the device's `listening` face
    /// waits this long for the reply; then the empty moment ends it
    /// (BEHAVIORS.md §3.3). The device's own button has the same cap.
    public static let replyWaitMs: Int64 = 8_000
    /// When that empty moment is due.
    var listeningEndsAt: Int64?

    /// Whether the last thing you said asked for quiet: only then may the
    /// `quiet` action run (BEHAVIORS.md §3.3).
    public private(set) var quietAsked = false

    // Poke streaks (BEHAVIORS.md §3.3).
    var taps: [Int64] = []
    var pokedAt: Int64?

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
        if event.project != "unknown" { s.project = event.project }
        let waiting = s.needsSince != nil || s.pendingSince != nil

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
                    fx.append(.aside(needsYouLine(s, now)))
                }
            }
            s.lastEventAt = now
            sessions[key] = s
            publish(now, &fx)
            return fx
        }

        // The asker's next event means it moved on, and so does any
        // turn-level event. A sibling subagent's tool calls don't answer
        // another agent's request, and Claude's idle notice (`turn_stopped`
        // with no tool) isn't the session acting (ADAPTERS.md §3–4).
        let idleNotice = event.event == .turnStopped && event.detail.tool == nil
        if waiting && !idleNotice {
            if event.event != .activity || s.askers.contains(Core.anyone) {
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
            s.status = .working
            s.turnStartedAt = now
            s.topic = nil
            s.check = nil
            sessions[key] = s
            agentInput(.agentStarted, s, rules: nil, rank: 1, now, &fx)
        case .activity:
            s.status = .working
            if s.turnStartedAt == nil { s.turnStartedAt = now }
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
            if let check, check.failed {
                // It left its tests, build or deploy failing: a failure, not
                // a finish.
                s.topic = check.topic
                sessions[key] = s
                failed(s, durationMs: ms, error: nil, now, &fx)
            } else {
                sessions[key] = s
                finished(s, durationMs: ms, now, &fx)
            }
        case .turnFailed:
            let ms = s.turnStartedAt.map { now - $0 } ?? 0
            s.status = .idle
            s.turnStartedAt = nil
            s.check = nil
            sessions[key] = s
            failed(s, durationMs: ms, error: event.detail.error, now, &fx)
        case .sessionEnd:
            sessions[key] = nil
        case .turnStopped:
            // Over without finishing (ADAPTERS.md §3): a working session goes
            // idle, with no reaction and nothing for the brain.
            if s.status == .working {
                s.status = .idle
                s.turnStartedAt = nil
                s.check = nil
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

    /// What the person said on push-to-talk, and whether they yelled it
    /// (BEHAVIORS.md §3.3). Always reaches the brain.
    @discardableResult
    public func talk(_ words: String, yelled: Bool = false, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        let input = Input(.said, words: words, yelled: yelled, clock: config.time.clock(now),
                          weekday: config.time.weekday(now), rules: "listening", ts: now)
        quietAsked = input.asksForQuiet
        fx.append(.input(input))
        publish(now, &fx)
        return fx
    }

    /// The app's Talk button: start or stop listening. The device shows
    /// `listening` from the mic turning on until the reply, or until the
    /// empty moment `replyWaitMs` after the mic goes off, as it does for its
    /// own button (BEHAVIORS.md §3.3).
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

    /// The Mac's mic or speech recognition couldn't start. After the Talk
    /// button, the empty moment ends the device's `listening` face at once;
    /// the device's own button ends it by itself.
    @discardableResult
    public func micFailed(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        let byApp = listening?.by == .app
        stopListening(now, &fx)
        if byApp {
            listeningEndsAt = nil
            fx.append(.endListening)
        }
        return fx
    }

    /// The `quiet` action: no mumbles for `minutes` (0 ends it). The strip's
    /// quiet icon is its only sign; the `zip` animation is parked.
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

    /// A new mode (BEHAVIORS.md §6), from the next event on. Working chatter
    /// starts its wait again at the new mode's pace.
    public func setMode(_ mode: Mode) {
        config.mode = mode
        nextChatterAt = nil
    }

    /// Timers: the Codex grace period, the safety net, quiet running out,
    /// merged inputs, chatter, the push-to-talk limit and the Talk button's
    /// wait for the reply.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        if let l = listening, now - l.since >= Self.listenLimitMs {
            // What was heard still goes to Boop. The device's own button
            // hits the same limit; the Talk button waits for the reply as
            // after Send.
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
            StateSnapshot.Attention(agent: $0.agent.short, project: StateSnapshot.clip($0.project), more: waiting.count - 1)
        }
        return StateSnapshot(
            time: now / 1000, name: StateSnapshot.clip(config.name), base: base, attn: attn,
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

    /// False in quiet mode, or while something needs you.
    public func canMumble(at now: Int64) -> Bool { mumblesAllowed(now) }

    // MARK: - Rules

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

    /// Nobody is waiting on the session any more.
    func clearRequest(_ s: inout Session, _ now: Int64) {
        s.needsSince = nil
        s.pendingSince = nil
        s.askers.removeAll()
        s.clearedAt = now
    }

    /// The first activity of a new day: short-term memory starts fresh.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = config.time.day(now)
        guard today != lastActiveDay else { return }
        lastActiveDay = today
        fx.append(.newDay(date: today, firstSeen: config.time.clock(now)))
    }

    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening == nil else { return }
        listening = (talker, now)
        // A new `listening` face mustn't be ended by the last one's stop.
        listeningEndsAt = nil
        fx.append(.listen(true))
    }

    /// Turns the mic off, if it's on. After the Talk button, the empty
    /// moment follows `replyWaitMs` later; it's harmless if the reply
    /// already came.
    func stopListening(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let l = listening else { return }
        listening = nil
        fx.append(.listen(false))
        if l.by == .app { listeningEndsAt = now + Self.replyWaitMs }
    }

    /// Plays a rule moment now. The device replaces one that's playing.
    func play(_ anim: String, _ fx: inout [CoreEffect]) {
        fx.append(.moment(anim: anim))
    }

    /// A finished turn: a cheer, even while other sessions are still
    /// working, when it's long enough for the mode (BEHAVIORS.md §3.1).
    func finished(_ s: Session, durationMs ms: Int64, _ now: Int64, _ fx: inout [CoreEffect]) {
        let cheer = config.mode.cheers(Input.Length(ms: ms))
        if cheer { play("cheer", &fx) }
        if ms >= 30_000 {
            fx.append(.happened("\(config.time.clock(now)) \(s.agent.short) · \(s.project) · finished (\(took(ms)))"))
        }
        agentInput(.agentFinished, s, outcome: .done, tookMs: ms, rules: cheer ? "cheer" : nil,
                   rank: Input.Length(ms: ms) == .short ? 2 : 3, now, &fx)
    }

    /// A tap is the rules' alone: the device wiggles, and the brain's
    /// transcript only hears of it. The fourth tap within 3 s is a poke
    /// streak (BEHAVIORS.md §3.3): an input for the brain, at most once a
    /// minute, which may grumble back with a mumble. The rules add no
    /// animation of their own: the device has already wiggled. While
    /// something needs you a tap means "I saw it", so it isn't counted.
    func tapped(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard !needsYouShowing else {
            taps.removeAll()
            fx.append(.aside("tapped while something needs you · \(timeLine(now))"))
            return
        }
        taps = taps.filter { now - $0 < config.pokeWindowMs } + [now]
        guard taps.count >= config.pokeTaps else {
            fx.append(.aside("tapped · \(timeLine(now)): Boop wiggled"))
            return
        }
        taps.removeAll()
        if let last = pokedAt, now - last < config.pokedEveryMs {
            fx.append(.aside("poked again and again · \(timeLine(now)): Boop wiggled"))
            return
        }
        pokedAt = now
        fx.append(.input(Input(.poked, clock: config.time.clock(now), weekday: config.time.weekday(now),
                               rules: "wiggle", ts: now)))
    }

    /// A failed turn: no moment of its own; the session just goes idle
    /// (BEHAVIORS.md §3.1). The brain still hears of it.
    func failed(_ s: Session, durationMs ms: Int64, error: String?, _ now: Int64, _ fx: inout [CoreEffect]) {
        let topic = s.topic.map { " · \($0)" } ?? ""
        fx.append(.happened("\(config.time.clock(now)) \(s.agent.short) · \(s.project)\(topic) · failed"))
        agentInput(.agentFinished, s, outcome: .failed, tookMs: ms, error: error, rules: nil, rank: 4, now, &fx)
    }

    func took(_ ms: Int64) -> String {
        ms < 60_000 ? "\(ms / 1000) s" : "\(ms / 60_000) min"
    }

    func timeLine(_ now: Int64) -> String {
        "\(config.time.clock(now)) \(config.time.weekday(now))"
    }

    /// "claude needs you · jetpack · 14:07 Tuesday", for the brain's transcript.
    func needsYouLine(_ s: Session, _ now: Int64) -> String {
        "\(s.agent.short) needs you · \(s.project) · \(timeLine(now))"
    }

    func agentInput(_ kind: Input.Kind, _ s: Session, outcome: Input.Outcome? = nil, tookMs: Int64? = nil,
                    error: String? = nil, rules: String?, rank: Int, _ now: Int64, _ fx: inout [CoreEffect]) {
        let input = Input(kind, agent: s.agent.short, project: s.project, outcome: outcome,
                          topic: kind == .agentFinished ? s.topic : nil, tookMs: tookMs, error: error,
                          clock: config.time.clock(now), weekday: config.time.weekday(now), rules: rules,
                          ts: now)
        offer(input, rank: rank, now, &fx)
    }

    /// While something needs you, and in quiet mode, only what you said
    /// reaches the brain.
    func inputsAllowed(_ now: Int64) -> Bool {
        !needsYouShowing && quietLeft(now) == 0
    }

    /// Sends an agent input now, or holds it to merge with the burst it's
    /// part of: failed beats a finish of 15 seconds or more, which beats a
    /// shorter finish, which beats a start. The held one goes out when the
    /// window ends, with how many others it stands for.
    func offer(_ input: Input, rank: Int, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard inputsAllowed(now) else { return }
        if now - lastInputAt >= config.mergeMs && heldInput == nil {
            lastInputAt = now
            fx.append(.input(input))
            return
        }
        if let held = heldInput {
            heldInput = rank >= held.rank ? (input, rank, held.count + 1) : (held.input, held.rank, held.count + 1)
        } else {
            heldInput = (input, rank, 1)
        }
    }

    /// Runs every timer due by `now`, in order.
    func advance(to now: Int64, _ fx: inout [CoreEffect]) {
        for (key, var s) in sessions {
            if let pending = s.pendingSince {
                if now - s.lastEventAt >= config.safetyNetMs {
                    s.pendingSince = nil
                    s.askers.removeAll()
                } else if now - pending >= config.codexGraceMs {
                    s.pendingSince = nil
                    s.needsSince = pending + config.codexGraceMs
                    s.status = .waiting
                    fx.append(.aside(needsYouLine(s, now)))
                }
            }
            if s.needsSince != nil && now - s.lastEventAt >= config.safetyNetMs {
                // Ten silent minutes: the agent is still waiting on its
                // prompt, or gone. Either way it isn't working, so no
                // sweat drop and no chatter. Its turn, if it goes on,
                // still counts from its start.
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
        if let due = listeningEndsAt, now >= due {
            listeningEndsAt = nil
            fx.append(.endListening)
        }

        // Merged bursts.
        if let held = heldInput, now - lastInputAt >= config.mergeMs {
            heldInput = nil
            lastInputAt = now
            if inputsAllowed(now) {
                var input = held.input
                input.more = held.count - 1
                fx.append(.input(input))
            }
        }

        chatter(now, &fx)
    }

    /// Working chatter (BEHAVIORS.md §2): while agents work, a mumble every
    /// so often, as the mode sets (none in calm). About half the time it asks
    /// about a working session's latest topic (`curious`); otherwise it's
    /// `happy`, with no word.
    func chatter(_ now: Int64, _ fx: inout [CoreEffect]) {
        let working = sessions.values.filter { isWorking($0, now) && $0.needsSince == nil }
        guard !working.isEmpty, let gap = config.mode.chatterMs else {
            nextChatterAt = nil
            return
        }
        guard let due = nextChatterAt else {
            nextChatterAt = now + Int64(rng.int(in: gap))
            return
        }
        guard now >= due else { return }
        nextChatterAt = now + Int64(rng.int(in: gap))
        guard mumblesAllowed(now) else { return }
        let topics = working.sorted { $0.order < $1.order }.compactMap(\.topic)
        let word = !topics.isEmpty && rng.chance(50) ? topics[rng.int(in: 0...(topics.count - 1))] : nil
        fx.append(.mumble(feeling: word == nil ? "happy" : "curious", word: word))
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
