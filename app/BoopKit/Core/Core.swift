import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides which visual the device shows and which
/// inputs reach the brain. Everything expressive is the brain's.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
/// The time is a steady clock, so a change to the Mac's clock can't stretch
/// a timer; days and times of day follow the wall clock the app reports
/// with `setWallClock`.
public final class Core {
    public struct Config: Sendable {
        public var volume: Int
        /// Boop's mood, which the mood action sets (harness/DECISIONS.md §4)
        /// and every `state` carries (PROTOCOL.md §3).
        public var mood = MoodAction.initial
        /// The personality's settings: how often the working heartbeat
        /// comes and which tool uses wake the brain (BEHAVIORS.md §6).
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
        /// Where this launch's request numbers start: the first request
        /// shown gets the one after it (`Core.nextAsk`). The app starts each
        /// launch somewhere random (`Core.randomFirstAsk`), so a request can't
        /// share `attn.id` with one the device still shows from the last
        /// launch (PROTOCOL.md §3).
        public var firstAsk = 0

        public init(volume: Int = 6, rules: Personality.Rules = Personality.Rules(), time: LocalTime = LocalTime(),
                    seed: UInt64 = 1) {
            self.volume = volume
            self.rules = rules
            self.time = time
            self.seed = seed
        }
    }

    struct Session {
        var agent: Agent
        var id: String
        var project: String
        /// Working on a turn: not idle, and not waiting on "needs you".
        var working = false
        var turnStartedAt: Int64?
        /// How long the Mac has slept since the turn started: the steady
        /// clock counts it, but the turn's length doesn't.
        var sleptMs: Int64 = 0
        /// When you last sent a prompt (`turn_start`), for a stale idle
        /// notice: a turn a call started (a background subagent's, after
        /// the main agent stopped) had no prompt to race.
        var promptedAt: Int64?
        var lastEventAt: Int64
        var topic: String?
        /// This turn's last test, build or deploy command, and whether it
        /// failed (BEHAVIORS.md §3.1).
        var check: (topic: String, failed: Bool)?
        /// When "needs you" started showing.
        var needsSince: Int64?
        /// The number of the request it shows (`Core.takeAsk`), for the
        /// order requests arrived in and for `attn.id`.
        var ask = 0
        /// Codex: when "needs you" arrived, during the grace period.
        var pendingSince: Int64?
        /// When "needs you" last cleared, to drop its late `Notification`.
        var clearedAt: Int64?
        /// A tool call has started since then: a new request follows one.
        var calledSinceClear = false
        /// The `Notification` types the waiting request's askers send, and
        /// those of the request that last cleared: only a late one of those
        /// is a copy.
        var notices: Set<String> = []
        var clearedNotices: Set<String> = []
        /// Who is asking, while "needs you" waits: `""` for the main agent,
        /// a Claude subagent's id, or `Core.anyone` for a `Notification` whose
        /// request's own hook hasn't come; each with the tool it asks for,
        /// or `""` for none. Only an asker's own next event answers it
        /// (ADAPTERS.md §4).
        var askers: [String: String] = [:]
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

        /// The turn's length at `now`, for one that started at `started`:
        /// the time the Mac was awake.
        func length(to now: Int64, from started: Int64) -> Int64 { max(0, now - started - sleptMs) }

        var key: String { Core.key(agent, id) }
    }

    public private(set) var config: Config

    var sessions: [String: Session] = [:]
    /// When each session that ended (`session_end`) did, until it starts
    /// again or a day passes: a hook of its that lands later landed late,
    /// and doesn't bring it back (ADAPTERS.md §4).
    var ended: [String: Int64] = [:]
    var nextOrder = 0
    /// The last request's number: they count up from `config.firstAsk`.
    var lastAsk: Int
    var rng: SplitMix64
    /// The last day with any activity; a new one starts short-term memory
    /// fresh.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    /// The session list as last published, which can change while the
    /// snapshot doesn't: a second idle session, say.
    var lastSessions: [SessionSummary] = []
    /// The visual the device shows and its variation, from 1, and the last
    /// variation each visual showed, which the next one there avoids.
    var shown: (visual: String, variant: Int) = ("", 1)
    var lastVariant: [String: Int] = [:]
    /// When the working heartbeat is next due; nil until work starts, and
    /// again after any event that woke the brain (harness/EVENTS.md §4).
    var nextWorkBeatAt: Int64?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0

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
        lastAsk = config.firstAsk
        rng = SplitMix64(seed: config.seed)
    }

    static func key(_ agent: Agent, _ id: String) -> String { agent.rawValue + "/" + id }

    /// The topics whose failing command fails a turn (BEHAVIORS.md §3.1).
    static let checks: Set<String> = ["tests", "build", "deploy"]

    /// The asker of a request that came as a `Notification` alone, which
    /// doesn't say who asked: any event from the session answers it.
    static let anyone = "*"

    /// The kinds that start or end a turn or a session: from inside a
    /// subagent, only that subagent's.
    static let turnLevel: Set<BoopEvent.Kind> = [.sessionStart, .turnStart, .turnEnd, .turnFailed, .sessionEnd]

    /// Claude's idle notice comes after a minute at its prompt, so one
    /// sooner than this after you sent a prompt is from before it.
    static let idleNoticeMinMs: Int64 = 30_000

    /// How far apart a request's own hook and its `Notification` may land,
    /// either way round (ADAPTERS.md §4).
    static let noticeLagMs: Int64 = 5000

    /// A poke streak never changes Boop's lasting mood: the mood action
    /// sits its pass out, so no answer can (EVENTS.md §6).
    public static let pokesSitOut: Set<String> = ["mood"]

    // MARK: - Inputs

    /// An agent event from an adapter.
    @discardableResult
    public func handle(_ event: BoopEvent) -> [CoreEffect] {
        let now = event.ts
        let key = Core.key(event.agent, event.session)
        var fx: [CoreEffect] = []
        // The event's own session is left until after the event: a Codex
        // request past its grace that the event answers was never shown,
        // so it isn't recorded as needing you either (ADAPTERS.md §4).
        advance(to: now, sparing: key, &fx)
        startDayIfNew(now, &fx)
        apply(event, key, now, &fx)
        if var s = sessions[key] {
            promote(&s, now, &fx)
            sessions[key] = s
        }
        publish(now, &fx)
        restartWorkBeat(fx)
        return fx
    }

    /// The event's changes to its session, before the snapshot goes out.
    private func apply(_ event: BoopEvent, _ key: String, _ now: Int64, _ fx: inout [CoreEffect]) {
        // A session that ended is back only when it starts again: resumed,
        // or a new prompt. Anything else of its came from before the end (a
        // Notification as you quit at the prompt, a background subagent's
        // result, the command Codex's Interrupt aborted).
        if sessions[key] == nil, ended[key] != nil {
            guard event.subagent == nil, event.event == .sessionStart || event.event == .turnStart else { return }
            ended[key] = nil
        }
        var s = sessions[key] ?? Session(agent: event.agent, id: event.session, project: event.project,
                                         lastEventAt: now, order: takeOrder())
        let waiting = s.needsSince != nil || s.pendingSince != nil
        // Claude's idle notice means it has sat at its prompt for a minute,
        // so one within 30 s of your last prompt is from before it: a new
        // prompt typed just as the minute ran out (ADAPTERS.md §4).
        if event.event == .turnStopped, event.detail.notice != nil, let prompted = s.promptedAt,
           now - prompted < Core.idleNoticeMinMs {
            return
        }
        // A session is where its events come from, except while a request
        // waits: the strip names where that was made, whatever folder a
        // sibling subagent works in meanwhile (BEHAVIORS.md §3.2).
        if event.project != "unknown" && !waiting {
            s.project = event.project
            s.workspace = event.workspace
        }
        noteActivity(now)

        if event.event == .needsYou {
            // A request's own hook (`PermissionRequest`, `Elicitation`) says
            // which agent asks; its `Notification` doesn't, so it's from
            // "anyone" until the hook comes. While a request waits, a
            // Notification is the same request, and a hook joins it: a
            // sibling subagent asking too, or, within 5 s of a Notification
            // that came alone, that request's own hook. With nothing
            // waiting, a Notification of the kind the request that last
            // cleared sends is its late copy if it comes within 5 s of the
            // clear, or before any tool call has started since
            // (ADAPTERS.md §4).
            let notice = event.detail.notice
            let asker = notice == nil ? event.subagent ?? "" : Core.anyone
            let kind = notice ?? (event.detail.tool == nil ? "elicitation_dialog" : "permission_prompt")
            let lateCopy = notice.map(s.clearedNotices.contains) == true
                && s.clearedAt.map { now - $0 < Core.noticeLagMs || !s.calledSinceClear } == true
            if !lateCopy { s.notices.insert(kind) }
            if waiting {
                if notice == nil {
                    if Array(s.askers.keys) == [Core.anyone], s.needsSince.map({ now - $0 < Core.noticeLagMs }) == true {
                        s.askers = [:]
                    }
                    s.askers[asker] = event.detail.tool ?? ""
                }
            } else if !lateCopy {
                s.askers = [asker: event.detail.tool ?? ""]
                if event.agent == .codex {
                    s.pendingSince = now
                    s.working = true
                } else {
                    s.needsSince = now
                    s.ask = takeAsk()
                    s.working = false
                    needsYouEvent(s, now, &fx)
                }
            }
            s.lastEventAt = now
            sessions[key] = s
            return
        }

        if event.event == .subagentEnd || (event.subagent != nil && Core.turnLevel.contains(event.event)) {
            // A subagent that has finished can't be waiting on a prompt, so
            // its end answers its own request: denied, it carried on and
            // ended without another tool call. It answers nobody else, not
            // even "anyone". It isn't activity either: the session doesn't
            // start working and its clock doesn't move, so it can't make an
            // idle or stale session look busy. Once no asker is left, the
            // session works again only if its turn is still going
            // (ADAPTERS.md §4). A turn-level hook from inside a subagent
            // (its `agent_id` on a `StopFailure`, say) is the same: that
            // subagent's alone, not the session's turn.
            if waiting, let id = event.subagent, s.askers.removeValue(forKey: id) != nil {
                if s.askers.isEmpty {
                    clearRequest(&s, now)
                    s.working = s.turnStartedAt != nil
                } else {
                    anotherRequest(&s)
                }
            }
            sessions[key] = s
            return
        }

        // The asker's next event means it moved on, and so does any
        // turn-level event. A sibling subagent's tool calls don't answer
        // another agent's request. Claude's idle notice (`turn_stopped` with
        // no tool) is turn-level too: Claude sits at its own prompt with the
        // turn over, which it never does while a prompt is up, a subagent's
        // included, so you pressed Esc on it, which sends no hook
        // (ADAPTERS.md §4).
        // An asker's result for another tool is a call it made alongside
        // the one that asks (Claude runs read-only calls in parallel, and
        // the main agent's Agent call runs on), so it isn't the answer. An
        // `Elicitation` (no tool) isn't a call: its answer is its
        // `ElicitationResult` or the agent's next call, never a result.
        if waiting {
            let asker = event.subagent ?? ""
            let alongside = event.detail.done && s.askers[asker].map { asked in
                asked.isEmpty || event.detail.tool.map { $0 != asked } == true
            } == true
            if event.event != .activity || s.askers[Core.anyone] != nil {
                s.askers.removeAll()
            } else if !alongside, s.askers.removeValue(forKey: asker) != nil, !s.askers.isEmpty {
                anotherRequest(&s)
            }
            if s.askers.isEmpty {
                clearRequest(&s, now)
                s.working = true
            }
        }
        s.lastEventAt = now
        // The table has the answer before the event applies, so whether
        // its event wakes the brain sees what it answered (EVENTS.md §6).
        sessions[key] = s

        switch event.event {
        case .sessionStart:
            sessions[key] = s
        case .turnStart:
            let gap = s.lastTurnEndedAt.map { Band.gap(ms: now - $0) }
            s.working = true
            s.turnStartedAt = now
            s.sleptMs = 0
            s.promptedAt = now
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
            var event = event
            var late = false
            if event.detail.done {
                // A result may come without its call's topic: it's the
                // `PreToolUse`'s, by ID or else the last one.
                let started = event.detail.toolUseID.flatMap { s.toolStarts.removeValue(forKey: $0) } ?? s.lastToolStart
                if event.detail.topic == nil { event.detail.topic = started?.topic }
                // The result of a call that started before the turn ended
                // or stopped landed late (Esc as it finished, or a
                // subagent's racing the interrupt): it counts, but the turn
                // stays over (ADAPTERS.md §4).
                if s.turnStartedAt == nil, let at = started?.at, let ended = s.lastTurnEndedAt, at <= ended { late = true }
                toolDone(&s, event, started: started?.at, now, &fx)
            } else if event.detail.tool != nil {
                let start = (at: now, topic: event.detail.topic)
                if let id = event.detail.toolUseID { s.toolStarts[id] = start }
                s.lastToolStart = start
                s.calledSinceClear = true
            }
            if !late {
                s.working = true
                if s.turnStartedAt == nil {
                    // A call opens a turn with no prompt (a background
                    // subagent's after the main agent's `Stop`, say): its
                    // counts are its own (EVENTS.md §4.1).
                    s.turnStartedAt = now
                    s.sleptMs = 0
                    s.tools = 0
                    s.toolsFailed = 0
                    s.topicStates = []
                    s.comeback = nil
                }
            }
            if let topic = event.detail.topic { s.topic = topic }
            if let topic = event.detail.topic, let failed = event.detail.failed, Core.checks.contains(topic) {
                s.check = (topic, failed)
            }
            sessions[key] = s
        case .turnEnd:
            s.working = false
            // A finish with no turn open (a second `Stop`, one after the
            // turn stopped, or the first Boop hears from a session) finishes
            // nothing Boop saw: no event (EVENTS.md §7).
            guard let started = s.turnStartedAt else {
                sessions[key] = s
                break
            }
            let ms = s.length(to: now, from: started)
            let check = s.check
            s.turnStartedAt = nil
            s.check = nil
            s.lastTurnEndedAt = now
            if s.turns == 0 {
                // Boop joined this turn partway (it launched, or forgot the
                // session, meanwhile), so it can't say how long it ran or
                // what it did: the brain hears nothing, as for a stop, and
                // nothing celebrates it (BEHAVIORS.md §3.1).
                sessions[key] = s
            } else if let check, check.failed {
                // It left its tests, build or deploy failing: a failure, not
                // a finish.
                sessions[key] = s
                turnEndEvent(s, outcome: "failed", error: nil, lengthMs: ms, reaction: nil, now, &fx)
            } else {
                // A finish: no rule celebrates it; the brain decides
                // (BEHAVIORS.md §3.1).
                sessions[key] = s
                turnEndEvent(s, outcome: "done", error: nil, lengthMs: ms, reaction: nil, now, &fx)
            }
        case .turnFailed:
            // As a finish: nothing with no turn open, nothing for the brain
            // from a turn Boop joined partway.
            s.working = false
            guard let started = s.turnStartedAt else {
                sessions[key] = s
                break
            }
            s.turnStartedAt = nil
            s.check = nil
            s.lastTurnEndedAt = now
            sessions[key] = s
            if s.turns > 0 {
                turnEndEvent(s, outcome: "failed", error: event.detail.error, lengthMs: s.length(to: now, from: started), reaction: nil,
                             now, &fx)
            }
        case .sessionEnd:
            sessions[key] = nil
            ended[key] = now
        case .turnStopped:
            // Over without finishing (ADAPTERS.md §3): a working session goes
            // idle, with no reaction. A turn still open ends as stopped, and
            // the brain hears of it, even once the safety net has made the
            // session idle: its turn went on (you approved, which sends no
            // hook), so a call's result after the stop is a late one.
            s.working = false
            if let started = s.turnStartedAt {
                s.turnStartedAt = nil
                s.check = nil
                s.lastTurnEndedAt = now
                if s.turns > 0 {
                    turnEndEvent(s, outcome: "stopped", error: nil, lengthMs: s.length(to: now, from: started), reaction: nil, now, &fx)
                }
            }
            sessions[key] = s
        case .needsYou, .subagentEnd:
            break
        }
    }

    /// An `input` message's `k` (PROTOCOL.md §4).
    public enum DeviceInput: String, Sendable {
        case tap
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
        }
        publish(now, &fx)
        restartWorkBeat(fx)
        return fx
    }

    @discardableResult
    public func setVolume(_ volume: Int, at now: Int64) -> [CoreEffect] {
        config.volume = max(0, min(10, volume))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The mood action saved a new mood: the next `state` carries it.
    public func setMood(_ mood: String, at now: Int64) -> [CoreEffect] {
        config.mood = mood
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
    /// on. The working heartbeat starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        config.rules = rules
        nextWorkBeatAt = nil
    }

    /// The Mac slept `ms`: the timers counted it, but no turn's length does.
    public func slept(_ ms: Int64) {
        for (key, s) in sessions where s.turnStartedAt != nil { sessions[key]?.sleptMs += ms }
    }

    /// Whether there's a brain to wake: Jev's key saved or removed.
    public func setBrain(_ available: Bool) { config.brain = available }

    /// Timers: the Codex grace period, the safety net and heartbeats.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        publish(now, &fx)
        restartWorkBeat(fx)
        return fx
    }

    // MARK: - Reading

    /// The sessions in the order the popover lists them: those that need
    /// you (oldest first), then working, then idle.
    func grouped(at now: Int64) -> (waiting: [Session], working: [Session], idle: [Session]) {
        let waiting = sessions.values.filter { $0.needsSince != nil }.sorted { ($0.needsSince!, $0.ask) < ($1.needsSince!, $1.ask) }
        let working = sessions.values.filter { $0.needsSince == nil && isWorking($0, now) }.sorted { $0.order < $1.order }
        let idle = sessions.values.filter { $0.needsSince == nil && !isWorking($0, now) }.sorted { $0.order < $1.order }
        return (waiting, working, idle)
    }

    public func snapshot(at now: Int64) -> StateSnapshot {
        let (waiting, working, _) = grouped(at: now)
        let base = !working.isEmpty ? "working" : sessions.isEmpty ? "asleep" : "idle"
        let attn = waiting.first.map {
            StateSnapshot.Attention(
                agent: $0.agent.short, project: StateSnapshot.clip($0.project, marked: true), more: waiting.count - 1,
                id: $0.ask)
        }
        let visual = attn != nil ? "needs_you" : base
        return StateSnapshot(base: base, mood: config.mood, attn: attn, busy: working.count, vol: config.volume,
                             variant: shown.visual == visual ? shown.variant : 1)
    }

    /// A variation of `state`'s design at random, from 1, never `last` when
    /// there's another (BEHAVIORS.md §1): the rules pick it for now, and the
    /// harness may later.
    public static func pickVariant(state: String, avoiding last: Int?, _ rng: inout SplitMix64) -> Int {
        let choices = Array(1...FaceLoops.count(state: state)).filter { $0 != last }
        guard !choices.isEmpty else { return 1 }
        return choices[rng.int(in: 0...(choices.count - 1))]
    }

    /// Every session, for the popover's list. The device doesn't
    /// get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (waiting, working, idle) = grouped(at: now)
        return waiting.map { SessionSummary($0, .waiting) } + working.map { SessionSummary($0, .working) }
            + idle.map { SessionSummary($0, .idle) }
    }

    /// Why a mumble can't play now, or nil: something needs you
    /// (BEHAVIORS.md §1).
    public var mumbleBlock: String? {
        needsYouShowing ? "something needs you" : nil
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

    /// The date at steady time `now`, on the wall clock: the calendar never
    /// sees steady time.
    private func day(_ now: Int64) -> String { config.time.day(wall(now)) }

    func takeOrder() -> Int {
        nextOrder += 1
        return nextOrder
    }

    func isWorking(_ s: Session, _ now: Int64) -> Bool {
        s.working && now - s.lastEventAt < config.staleWorkMs
    }

    var needsYouShowing: Bool { sessions.values.contains { $0.needsSince != nil } }

    /// A Codex request whose grace is over, and nothing answered, shows,
    /// dated 2 s after it arrived (ADAPTERS.md §4).
    func promote(_ s: inout Session, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let pending = s.pendingSince, now - pending >= config.codexGraceMs else { return }
        s.pendingSince = nil
        s.needsSince = pending + config.codexGraceMs
        s.ask = takeAsk()
        s.working = false
        needsYouEvent(s, now, &fx)
    }

    /// A request's number, in the order requests start showing.
    func takeAsk() -> Int {
        lastAsk = Core.nextAsk(after: lastAsk)
        return lastAsk
    }

    /// The largest request number: the device keeps `attn.id` in 32 bits.
    static let maxAsk = Int(Int32.max)

    /// The number after `ask`, back to 1 past `maxAsk`: never 0, which
    /// means no number (PROTOCOL.md §3).
    static func nextAsk(after ask: Int) -> Int { ask >= maxAsk ? 1 : ask + 1 }

    /// A random place for a launch's request numbers to start.
    public static func randomFirstAsk() -> Int { Int.random(in: 0..<maxAsk) }

    /// One of several askers in a session was answered, so Claude shows
    /// another's prompt now: a different request, with its own number, so
    /// the device chirps if it's the one shown (BEHAVIORS.md §3.2).
    func anotherRequest(_ s: inout Session) {
        if s.needsSince != nil { s.ask = takeAsk() }
    }

    /// Nobody is waiting on the session any more.
    func clearRequest(_ s: inout Session, _ now: Int64) {
        s.needsSince = nil
        s.pendingSince = nil
        s.askers.removeAll()
        s.clearedAt = now
        s.calledSinceClear = false
        s.clearedNotices = s.notices
        s.notices = []
    }

    /// The first activity of a new day: short-term memory starts fresh.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = day(now)
        guard today != lastActiveDay else { return }
        lastActiveDay = today
        fx.append(.newDay(date: today))
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
                               wakesBrain: wakes, facts: facts, sitsOut: Core.pokesSitOut)))
    }

    /// Runs every timer due by `now`, in order, but shows no Codex request
    /// of `sparing`'s session: its event comes first.
    func advance(to now: Int64, sparing: String? = nil, _ fx: inout [CoreEffect]) {
        for (key, var s) in sessions {
            let silent = now - s.lastEventAt >= config.safetyNetMs
            if !silent && key != sparing { promote(&s, now, &fx) }
            if silent && (s.needsSince != nil || s.pendingSince != nil) {
                // Ten silent minutes, even for a Codex request no tick saw
                // through its grace (the Mac slept): the agent is still
                // waiting on its prompt, or gone. Either way it isn't
                // working. Its turn, if it goes on, still
                // counts from its start.
                clearRequest(&s, now)
                s.working = false
            }
            if now - s.lastEventAt >= config.forgetMs {
                sessions[key] = nil
            } else {
                sessions[key] = s
            }
        }
        ended = ended.filter { now - $0.value < config.forgetMs }
        workingHeartbeat(now, &fx)
        heartbeat(now, &fx)
    }

    /// The working heartbeat (BEHAVIORS.md §2, harness/EVENTS.md §4): while
    /// agents work, an event for the brain once the personality's wait has
    /// passed with no event that woke it, so the brain may mumble in a
    /// quiet stretch of work. It names the thread working longest and its
    /// latest topic. No rule mumbles.
    func workingHeartbeat(_ now: Int64, _ fx: inout [CoreEffect]) {
        let working = sessions.values.filter { isWorking($0, now) && $0.needsSince == nil }
        guard !working.isEmpty, let gap = config.rules.workBeatMs else {
            nextWorkBeatAt = nil
            return
        }
        guard let due = nextWorkBeatAt else {
            nextWorkBeatAt = now + Int64(rng.int(in: gap))
            return
        }
        guard now >= due else { return }
        nextWorkBeatAt = now + Int64(rng.int(in: gap))
        guard let s = working.min(by: { ($0.turnStartedAt ?? now, $0.order) < ($1.turnStartedAt ?? now, $1.order) }) else { return }
        let ms = s.length(to: now, from: s.turnStartedAt ?? now)
        fx.append(.event(Event(.heartbeat, at: now,
                               line: EventLine.working(agent: s.agent.short, thread: threadLine(s), ms: ms, topic: s.topic),
                               wakesBrain: wakes, about: s.key,
                               facts: ["thread": threadFacts(s), "working_ms": .int(ms), "topic": .of(s.topic)])))
    }

    /// Any event that woke the brain starts the working heartbeat's wait
    /// again, so it comes only in a quiet stretch.
    func restartWorkBeat(_ fx: [CoreEffect]) {
        let woke = fx.contains { if case .event(let e) = $0 { e.wakesBrain } else { false } }
        if woke { nextWorkBeatAt = nil }
    }

    // MARK: - Events (harness/EVENTS.md)

    /// Whether an event whose kind wakes the brain does: never while
    /// something needs you, or with no brain (EVENTS.md §6).
    var wakes: Bool {
        config.brain && !needsYouShowing
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
        fx.append(.event(Event(.turnStart, at: now, line: line, wakesBrain: wakes, about: s.key,
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
        fx.append(.event(Event(.turnEnd, at: now, line: line, reaction: reaction, wakesBrain: wakes, about: s.key,
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
        fx.append(.event(Event(.toolUse, at: now, line: line, wakesBrain: wakes, about: s.key, facts: facts)))
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
                               wakesBrain: wakes, facts: ["idle_hours": .int(hours)])))
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
            "\"\(s.name)\" (\(s.agent.short)\(s.name == s.project ? "" : ", \(s.project)")), for \(Band.took(s.length(to: now, from: s.turnStartedAt ?? now)))"
        }
        return "Working now: " + parts.joined(separator: "; ") + "."
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        var snapshot = snapshot(at: now)
        if snapshot.visual != shown.visual {
            // A new visual: a variation of it at random.
            shown = (snapshot.visual, Core.pickVariant(state: snapshot.visual, avoiding: lastVariant[snapshot.visual], &rng))
            lastVariant[snapshot.visual] = shown.variant
            snapshot.variant = shown.variant
        }
        let sessions = sessionList(at: now)
        defer { lastSessions = sessions }
        if snapshot != lastPublished {
            lastPublished = snapshot
            // The picture changes before any moment plays on top of it.
            fx.insert(.state(snapshot), at: 0)
        } else if sessions != lastSessions {
            fx.insert(.sessions, at: 0)
        }
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
