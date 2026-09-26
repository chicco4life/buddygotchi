import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides what the device shows, the rule reactions, XP,
/// hunger, mood, quiet and away, and which triggers reach the harness.
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
    public private(set) var growth: Growth
    public private(set) var away = false

    var sessions: [String: Session] = [:]
    var nextOrder = 0
    var rng: SplitMix64
    var mood = MoodState()
    var quietUntil: Int64 = 0
    /// The day "I'm away" started; the app keeps it in its settings so a
    /// restart doesn't restart the pause.
    public private(set) var awaySince: String?
    /// The last day with any activity; a new one starts the day's rituals.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?

    // Rule moments.
    struct Scheduled { var at: Int64; var anim: String; var size: Int }
    var scheduled: [Scheduled] = []
    /// Follow-up moments still to play (`side_eye` after `oops`, `gobble`);
    /// the brain's moments wait for them.
    public var followUpsPending: Bool { !scheduled.isEmpty }
    var lastMomentAt: Int64 = -1_000_000
    var lastFinish: (at: Int64, size: Int)?
    var levelUpPending = false
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
    /// so a restart doesn't replay the morning.
    public init(config: Config, growth: Growth, lastActiveDay: String? = nil, now: Int64) {
        self.config = config
        self.growth = growth
        self.lastActiveDay = lastActiveDay
        rng = SplitMix64(seed: config.seed)
        mood.updated = now
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
                play("listening", 1, now, &fx)
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

    /// "I'm away" pauses hunger. `since` is the day an away period saved
    /// before a restart started, so the pause keeps counting from it.
    @discardableResult
    public func setAway(_ on: Bool, since: String? = nil, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        let today = config.time.day(now)
        if on && !away {
            awaySince = since.flatMap { LocalTime.isDay($0) ? min($0, today) : nil } ?? today
        } else if !on && away, let since = awaySince {
            // Only the away days since the last meal are paused: XP earned
            // while away already moved lastFed past the start.
            let paused = LocalTime.daysBetween(max(since, growth.lastFed), today)
            if paused > 0 { growth.lastFed = LocalTime.day(growth.lastFed, plus: paused) }
            awaySince = nil
            fx.append(.growth(growth))
        }
        away = on
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
    /// follow-up moments, merged triggers, chatter, level-ups and the
    /// push-to-talk limit.
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

    public func snapshot(at now: Int64) -> StateSnapshot {
        let visible = sessions.values.filter { $0.needsSince != nil }.sorted { ($0.needsSince!, $0.order) < ($1.needsSince!, $1.order) }
        let working = sessions.values.filter { $0.needsSince == nil && isWorking($0, now) }.sorted { $0.order < $1.order }
        let idle = sessions.values.filter { $0.needsSince == nil && !isWorking($0, now) }.sorted { $0.order < $1.order }
        let night = config.time.isNight(now)
        let base: String
        if !working.isEmpty {
            base = "working"
        } else if sessions.isEmpty || (night && visible.isEmpty) {
            base = "asleep"
        } else {
            base = "idle"
        }
        let attn = visible.first.map {
            StateSnapshot.Attention(agent: $0.agent.short, project: StateSnapshot.clip($0.project), more: visible.count - 1)
        }
        let rows = visible.map { [$0.agent.short, StateSnapshot.clip($0.project), "wait"] }
            + working.map { [$0.agent.short, StateSnapshot.clip($0.project), "work"] }
            + idle.map { [$0.agent.short, StateSnapshot.clip($0.project), "idle"] }
        let hunger = hungerNow(now)
        var snapshot = StateSnapshot(
            time: now / 1000, name: StateSnapshot.clip(config.name), base: base, attn: attn,
            busy: working.count, idle: idle.count, wait: visible.count,
            mood: mood.mood(at: now, night: night, hunger: hunger),
            quiet: quietLeft(now), vol: config.volume, night: night,
            level: growth.level, prog: growth.progress, days: growth.days(today: config.time.day(now)),
            hungry: hunger.rawValue, threads: Array(rows.prefix(StateSnapshot.maxThreads)))
        snapshot.fit()
        return snapshot
    }

    /// Energy, pace and pitch now, for Voice's tempo.
    public func currentMood(at now: Int64) -> Mood {
        mood.mood(at: now, night: config.time.isNight(now), hunger: hungerNow(now))
    }

    /// False in quiet mode, or while something needs you.
    public func canMumble(at now: Int64) -> Bool { mumblesAllowed(now) }

    /// How `short-term.md` describes Boop's mood right now.
    public func moodWord(at now: Int64) -> String {
        mood.word(at: now, night: config.time.isNight(now), hunger: hungerNow(now))
    }

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

    func hungerNow(_ now: Int64) -> Growth.Hunger {
        growth.hunger(today: awaySince ?? config.time.day(now))
    }

    func feeling(_ now: Int64) -> String {
        mood.feeling(at: now, night: config.time.isNight(now), hunger: hungerNow(now))
    }

    /// Mumbles never play in quiet mode, or while something needs you.
    func mumblesAllowed(_ now: Int64) -> Bool {
        quietLeft(now) == 0 && !needsYouShowing
    }

    /// The first activity of a new day: short-term memory starts fresh, and
    /// yesterday gets its reflection.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = config.time.day(now)
        guard today != lastActiveDay else { return }
        let yesterday = lastActiveDay
        lastActiveDay = today
        fx.append(.newDay(date: today, firstSeen: config.time.clock(now), mood: moodWord(at: now)))
        if let yesterday {
            fx.append(.trigger(Trigger(kind: .reflect, line: "reflect · yesterday \(yesterday)", ts: now)))
        }
    }

    /// Adds XP; a first meal after being hungry plays `gobble` once `after`.
    func feed(_ xp: Int, _ now: Int64, after: Int64, _ fx: inout [CoreEffect]) {
        let wasHungry = hungerNow(now) >= .hungry
        if growth.earn(xp, today: config.time.day(now)) {
            levelUpPending = true
        }
        if wasHungry {
            scheduled.append(Scheduled(at: after, anim: "gobble", size: 1))
        }
        fx.append(.growth(growth))
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
        if let face { play(face, 1, now, &fx) }
    }

    /// Plays a rule moment now. Follow-ups from an earlier one are dropped,
    /// since the device replaces a playing moment anyway.
    func play(_ anim: String, _ size: Int, _ now: Int64, _ fx: inout [CoreEffect]) {
        scheduled.removeAll()
        lastMomentAt = now
        fx.append(.moment(anim: anim, size: size))
    }

    /// A finished turn: a cheer sized by how long it took, even while other
    /// sessions are still working. Several at once make one cheer at the
    /// biggest size.
    func finished(_ s: Session, durationMs ms: Int64, _ now: Int64, _ fx: inout [CoreEffect]) {
        let size: Int
        switch ms {
        case ..<300_000: size = 1
        case ..<1_200_000: size = 2
        default: size = 3
        }
        let burst = lastFinish.map { now - $0.at < config.mergeMs } ?? false
        if !burst || size > lastFinish!.size {
            play("cheer", size, now, &fx)
            lastFinish = (now, burst ? max(size, lastFinish!.size) : size)
        } else {
            lastFinish = (now, lastFinish!.size)
        }
        mood.win(quick: ms < 300_000, at: now)
        feed(Growth.turnXP, now, after: now + 1600, &fx)
        if ms >= 30_000 {
            fx.append(.happened("\(config.time.clock(now)) \(s.agent.short) · \(s.project) · finished (\(took(ms)))"))
        }
        var extra: [String] = []
        if let topic = s.topic { extra.append("topic: \(topic)") }
        extra.append("took \(took(ms))")
        eventTrigger("turn finished", s, extra: extra, rank: ms >= 300_000 ? 3 : 2, now, &fx)
    }

    /// A failed turn: `oops`, then a side-eye at the agent.
    func failed(_ s: Session, durationMs ms: Int64, error: String?, _ now: Int64, _ fx: inout [CoreEffect]) {
        play("oops", 1, now, &fx)
        scheduled.append(Scheduled(at: now + 1400, anim: "side_eye", size: 1))
        lastFinish = nil
        mood.fail(at: now)
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
        var line = "\(config.time.clock(now)) \(config.time.weekday(now))"
        switch hungerNow(now) {
        case .fed: break
        case .hungry: line += " · hungry"
        case .starving: line += " · starving"
        }
        return line
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

        let today = awaySince ?? config.time.day(now)
        if growth.starve(today: today) { fx.append(.growth(growth)) }

        // Follow-up moments.
        while let first = scheduled.min(by: { $0.at < $1.at }), first.at <= now {
            scheduled.removeAll { $0.at == first.at && $0.anim == first.anim }
            lastMomentAt = first.at
            fx.append(.moment(anim: first.anim, size: first.size))
        }

        // A level-up plays at the next calm moment.
        if levelUpPending && scheduled.isEmpty && !needsYouShowing && now - lastMomentAt >= 3000 {
            levelUpPending = false
            lastMomentAt = now
            fx.append(.moment(anim: "levelup", size: 1))
            fx.append(.happened("\(config.time.clock(now)) reached level \(growth.level)"))
        }

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

    /// Working chatter: every 2–4 minutes while agents work, a mumble from
    /// Boop's mood, about half the time with the session's latest topic.
    /// Slower when tired or at night.
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
        fx.append(.mumble(feeling: feeling(now), word: word))
    }

    func chatterGap(_ now: Int64) -> Int64 {
        var gap = Int64(rng.int(in: config.chatterMs))
        let m = mood.mood(at: now, night: config.time.isNight(now), hunger: hungerNow(now))
        if m.energy < 70 { gap = gap * 3 / 2 }
        if config.time.isNight(now) { gap = gap * 3 / 2 }
        return gap
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        let snapshot = snapshot(at: now)
        guard !snapshot.sameContent(as: lastPublished) else { return }
        lastPublished = snapshot
        // The picture changes before any moment plays on top of it.
        fx.insert(.state(snapshot), at: 0)
    }
}
