import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides what the device shows, the rule reactions,
/// quiet, and which triggers reach the harness.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
public final class Core {
    public struct Config: Sendable {
        public var name: String
        public var volume: Int
        public var time: LocalTime
        public var seed: UInt64
        /// Codex's grace period before "needs you" shows (ADAPTERS.md §4).
        public var codexGraceMs: Int64 = 2000
        /// "Needs you" clears anyway after this long with no events.
        public var safetyNetMs: Int64 = 10 * 60 * 1000
        /// A working session with no events for this long counts as idle.
        public var staleWorkMs: Int64 = 60 * 60 * 1000
        /// A session with no events for this long is forgotten.
        public var forgetMs: Int64 = 24 * 60 * 60 * 1000
        /// Triggers within this window merge into one.
        public var mergeMs: Int64 = 3000
        /// Working chatter comes every 2–4 minutes (BEHAVIORS.md §2, proposed).
        public var chatterMs: ClosedRange<Int> = 120_000...240_000

        public init(name: String, volume: Int = 6, time: LocalTime = LocalTime(), seed: UInt64 = 1) {
            self.name = name
            self.volume = volume
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
        /// When "needs you" started showing.
        var needsSince: Int64?
        /// Codex: when "needs you" arrived, during the grace period.
        var pendingSince: Int64?
        /// When "needs you" last cleared, to drop a late duplicate.
        var clearedAt: Int64?
        let order: Int

        var key: String { Core.key(agent, id) }
    }

    public private(set) var config: Config

    var sessions: [String: Session] = [:]
    var nextOrder = 0
    var rng: SplitMix64
    var quietUntil: Int64 = 0
    /// The last day with any activity; a new one starts the reflection on
    /// the day before.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    var nextChatterAt: Int64?

    // Trigger merging.
    var lastTriggerAt: Int64 = -1_000_000
    var heldTrigger: (trigger: Trigger, rank: Int, count: Int)?

    // Push-to-talk (UX.md §5).
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// Talk button.
    public enum Talker: Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// While the Mac's mic is on: who turned it on, and when.
    public private(set) var listening: (by: Talker, since: Int64)?

    /// `lastActiveDay` is today's date from `short-term.md`, if there is one,
    /// so a restart doesn't start the day again.
    public init(config: Config, lastActiveDay: String? = nil) {
        self.config = config
        self.lastActiveDay = lastActiveDay
        rng = SplitMix64(seed: config.seed)
    }

    static func key(_ agent: Agent, _ id: String) -> String { agent.rawValue + "/" + id }

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
            // A second one while waiting is the same request (PermissionRequest
            // and its Notification). A tool-less one just after a clear is the
            // Notification arriving late.
            let lateDuplicate = event.detail.tool == nil && s.clearedAt.map { now - $0 < 5000 } == true
            if !waiting && !lateDuplicate {
                if event.agent == .codex {
                    s.pendingSince = now
                    s.status = .working
                } else {
                    s.needsSince = now
                    s.status = .waiting
                }
            }
            s.lastEventAt = now
            sessions[key] = s
            publish(now, &fx)
            return fx
        }

        // Any other event from the session means it moved on.
        if waiting {
            s.needsSince = nil
            s.pendingSince = nil
            s.clearedAt = now
            s.status = .working
        }
        s.lastEventAt = now

        switch event.event {
        case .sessionStart:
            sessions[key] = s
        case .turnStart:
            s.status = .working
            s.turnStartedAt = now
            s.topic = nil
            sessions[key] = s
            eventTrigger("turn started", s, extra: [], rank: 1, now, &fx)
        case .activity:
            s.status = .working
            if s.turnStartedAt == nil { s.turnStartedAt = now }
            if let topic = event.detail.topic { s.topic = topic }
            sessions[key] = s
        case .turnEnd:
            let ms = s.turnStartedAt.map { now - $0 } ?? 0
            s.status = .idle
            s.turnStartedAt = nil
            sessions[key] = s
            finished(s, durationMs: ms, now, &fx)
        case .turnFailed:
            let ms = s.turnStartedAt.map { now - $0 } ?? 0
            s.status = .idle
            s.turnStartedAt = nil
            sessions[key] = s
            failed(s, durationMs: ms, error: event.detail.error, now, &fx)
        case .sessionEnd:
            sessions[key] = nil
        case .needsYou:
            break
        }
        publish(now, &fx)
        return fx
    }

    public enum Input: String, Sendable {
        case tap, talkOn = "talk_on", talkOff = "talk_off"
    }

    /// An `input` message from the device. The device has already reacted.
    @discardableResult
    public func input(_ input: Input, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        switch input {
        case .tap:
            let line = "tapped · " + timeLine(now)
            offer(Trigger(kind: .tap, line: line, ts: now), rank: 2, now, &fx)
        case .talkOn:
            // The device already shows `listening`, and `thinking` on release.
            startListening(by: .device, now, &fx)
        case .talkOff:
            stopListening(now, face: nil, &fx)
        }
        publish(now, &fx)
        return fx
    }

    /// What the person said on push-to-talk. Always reaches the harness.
    @discardableResult
    public func talk(_ words: String, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        fx.append(.trigger(Trigger(kind: .talk, line: "talk · " + timeLine(now), words: words, ts: now)))
        publish(now, &fx)
        return fx
    }

    /// The app's Talk button: start or stop listening. The device shows
    /// `listening`, then `thinking`, as it does for its own button.
    @discardableResult
    public func listen(_ on: Bool, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        if on {
            if listening == nil {
                startListening(by: .app, now, &fx)
                play("listening", &fx)
            }
        } else {
            stopListening(now, face: listening?.by == .app ? "thinking" : nil, &fx)
        }
        publish(now, &fx)
        return fx
    }

    /// The link to the device dropped, so its button's release can't arrive:
    /// stop listening now. The app's Talk button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        if listening?.by == .device { stopListening(now, face: nil, &fx) }
        return fx
    }

    /// The Mac's mic or speech recognition couldn't start.
    @discardableResult
    public func micFailed(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        stopListening(now, face: listening?.by == .app ? "shrug" : nil, &fx)
        return fx
    }

    /// The `quiet` action: no mumbles for `minutes` (0 ends it).
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

    /// Timers: the Codex grace period, the safety net, quiet running out,
    /// merged triggers, chatter and the push-to-talk limit.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        if let l = listening, now - l.since >= Self.listenLimitMs {
            // What was heard still goes to Boop. The device's own
            // `listening` ends at the same limit.
            stopListening(now, face: l.by == .app ? "thinking" : nil, &fx)
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

    /// The first activity of a new day: short-term memory starts fresh, and
    /// the daily reflection on yesterday.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = config.time.day(now)
        guard today != lastActiveDay else { return }
        let yesterday = lastActiveDay
        lastActiveDay = today
        fx.append(.newDay(date: today, firstSeen: config.time.clock(now)))
        if let yesterday {
            fx.append(.trigger(Trigger(kind: .reflect, line: "reflect · yesterday \(yesterday)", ts: now)))
        }
    }

    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening == nil else { return }
        listening = (talker, now)
        fx.append(.listen(true))
    }

    /// Turns the mic off, if it's on, and plays `face` on the device.
    func stopListening(_ now: Int64, face: String?, _ fx: inout [CoreEffect]) {
        guard listening != nil else { return }
        listening = nil
        fx.append(.listen(false))
        if let face { play(face, &fx) }
    }

    /// Plays a rule moment now. The device replaces one that's playing.
    func play(_ anim: String, _ fx: inout [CoreEffect]) {
        fx.append(.moment(anim: anim))
    }

    /// A finished turn: a cheer, even while other sessions are still
    /// working (BEHAVIORS.md §3.1).
    func finished(_ s: Session, durationMs ms: Int64, _ now: Int64, _ fx: inout [CoreEffect]) {
        play("cheer", &fx)
        if ms >= 30_000 {
            fx.append(.happened("\(config.time.clock(now)) \(s.agent.short) · \(s.project) · finished (\(took(ms)))"))
        }
        var extra: [String] = []
        if let topic = s.topic { extra.append("topic: \(topic)") }
        extra.append("took \(took(ms))")
        eventTrigger("turn finished", s, extra: extra, rank: ms >= 300_000 ? 3 : 2, now, &fx)
    }

    /// A failed turn: no moment of its own (BEHAVIORS.md §3.1); the brain
    /// may sass the agent.
    func failed(_ s: Session, durationMs ms: Int64, error: String?, _ now: Int64, _ fx: inout [CoreEffect]) {
        let topic = s.topic.map { " · \($0)" } ?? ""
        fx.append(.happened("\(config.time.clock(now)) \(s.agent.short) · \(s.project)\(topic) · failed"))
        var extra: [String] = []
        if let topic = s.topic { extra.append("topic: \(topic)") }
        if let error { extra.append("error: \(error.replacingOccurrences(of: "_", with: " "))") }
        eventTrigger("turn failed", s, extra: extra, rank: 4, now, &fx)
    }

    func took(_ ms: Int64) -> String {
        ms < 60_000 ? "\(ms / 1000) s" : "\(ms / 60_000) min"
    }

    func timeLine(_ now: Int64) -> String {
        "\(config.time.clock(now)) \(config.time.weekday(now))"
    }

    func eventTrigger(_ what: String, _ s: Session, extra: [String], rank: Int, _ now: Int64,
                      _ fx: inout [CoreEffect]) {
        let line = ([what, s.agent.short, s.project] + extra + [timeLine(now)]).joined(separator: " · ")
        offer(Trigger(kind: .event, line: line, ts: now), rank: rank, now, &fx)
    }

    /// While something needs you, and in quiet mode, only `talk` and the
    /// daily reflection reach the harness.
    func triggersAllowed(_ now: Int64) -> Bool {
        !needsYouShowing && quietLeft(now) == 0
    }

    /// Sends a trigger now, or holds it to merge with the burst it's part of.
    /// The held one keeps the most important line and goes out when the
    /// window ends.
    func offer(_ trigger: Trigger, rank: Int, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard triggersAllowed(now) else { return }
        if now - lastTriggerAt >= config.mergeMs && heldTrigger == nil {
            lastTriggerAt = now
            fx.append(.trigger(trigger))
            return
        }
        if let held = heldTrigger {
            heldTrigger = rank >= held.rank ? (trigger, rank, held.count + 1) : (held.trigger, held.rank, held.count + 1)
        } else {
            heldTrigger = (trigger, rank, 1)
        }
    }

    /// Runs every timer due by `now`, in order.
    func advance(to now: Int64, _ fx: inout [CoreEffect]) {
        for (key, var s) in sessions {
            if let pending = s.pendingSince {
                if now - s.lastEventAt >= config.safetyNetMs {
                    s.pendingSince = nil
                } else if now - pending >= config.codexGraceMs {
                    s.pendingSince = nil
                    s.needsSince = pending + config.codexGraceMs
                    s.status = .waiting
                }
            }
            if s.needsSince != nil && now - s.lastEventAt >= config.safetyNetMs {
                s.needsSince = nil
                s.clearedAt = now
                s.status = .working
            }
            if now - s.lastEventAt >= config.forgetMs {
                sessions[key] = nil
            } else {
                sessions[key] = s
            }
        }
        if quietUntil != 0 && quietUntil <= now { quietUntil = 0 }

        // Merged triggers.
        if let held = heldTrigger, now - lastTriggerAt >= config.mergeMs {
            heldTrigger = nil
            lastTriggerAt = now
            if triggersAllowed(now) {
                var trigger = held.trigger
                if held.count > 1 { trigger.line += " · +\(held.count - 1) more" }
                fx.append(.trigger(trigger))
            }
        }

        chatter(now, &fx)
    }

    /// Working chatter (BEHAVIORS.md §2): every 2–4 minutes while agents
    /// work, a mumble. About half the time it asks about a working session's
    /// latest topic (`curious`); otherwise it's `happy`, with no word.
    func chatter(_ now: Int64, _ fx: inout [CoreEffect]) {
        let working = sessions.values.filter { isWorking($0, now) && $0.needsSince == nil }
        guard !working.isEmpty else {
            nextChatterAt = nil
            return
        }
        guard let due = nextChatterAt else {
            nextChatterAt = now + chatterGap(now)
            return
        }
        guard now >= due else { return }
        nextChatterAt = now + chatterGap(now)
        guard mumblesAllowed(now) else { return }
        let topics = working.sorted { $0.order < $1.order }.compactMap(\.topic)
        let word = !topics.isEmpty && rng.chance(50) ? topics[rng.int(in: 0...(topics.count - 1))] : nil
        fx.append(.mumble(feeling: word == nil ? "happy" : "curious", word: word))
    }

    func chatterGap(_ now: Int64) -> Int64 {
        Int64(rng.int(in: config.chatterMs))
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
