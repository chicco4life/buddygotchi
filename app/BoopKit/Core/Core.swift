import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides which visual the device shows, what the
/// agents are doing included (`act`), and which one-shots the rules play
/// (BEHAVIORS.md §3.1). What it does by rule it records as `action`
/// events: "needs you" showing and ending, and a poke (the `wiggle`
/// action, by its older name: the device plays its poke). What the
/// brain hears is the view's (harness/EVENTS.md); everything expressive
/// is the brain's.
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
        /// Where this launch's request numbers start: the first request
        /// shown gets the one after it (`Core.nextAsk`). The app starts each
        /// launch somewhere random (`Core.randomFirstAsk`), so a request can't
        /// share `attn.id` with one the device still shows from the last
        /// launch (PROTOCOL.md §3).
        public var firstAsk = 0

        public init(volume: Int = 6, time: LocalTime = LocalTime(), seed: UInt64 = 1) {
            self.volume = volume
            self.time = time
            self.seed = seed
        }
    }

    struct Session {
        var agent: Agent
        var id: String
        var project: String
        /// The thread's name as its agent's app shows it, the last an
        /// event brought: the strip shows it in the project's place
        /// (BEHAVIORS.md §3.2).
        var name: String?
        /// The thread's workspace: a linked worktree's folder or the
        /// branch, which tells two sessions in one project apart.
        var workspace: String?
        /// Working on a turn: not idle, and not waiting on "needs you".
        var working = false
        /// When the turn now open started, and when the last one ended: a
        /// call's result from before the end landed late (ADAPTERS.md §4).
        var turnStartedAt: Int64?
        var lastTurnEndedAt: Int64?
        /// When you last sent a prompt (a `turn` start), for a stale idle
        /// notice: a turn a call started (a background subagent's, after
        /// the main agent stopped) had no prompt to race.
        var promptedAt: Int64?
        var lastEventAt: Int64
        /// When "needs you" started showing.
        var needsSince: Int64?
        /// The event that made it show (its `seq`): a Claude request's, or
        /// a Codex request's that its grace let through.
        var askSeq: Int?
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
        /// Each running tool call's start, by `tool_use_id`, and the last
        /// one's, for a result that carries no ID.
        var toolStarts: [String: Int64] = [:]
        var lastToolStart: Int64?
        /// The tool calls running this turn, for the look, by
        /// `tool_use_id` or a key of their own (BEHAVIORS.md §2).
        var calls: [String: Call] = [:]
        /// The helpers seen starting this turn (`SubagentStart`) that
        /// haven't ended, by `agent_id`: the main agent is delegating.
        var helpers: Set<String> = []
        /// Claude's plan mode, as the last event that said had it.
        var planMode = false
        /// Its activity as it shows, held (`Core.hold`).
        var held: Held?

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
    /// The activity the working look shows (`updateActs`).
    var shownAct: Shown?
    /// Calls started, counted, so a result that names no call ends the
    /// last one.
    var callOrder = 0
    /// When the rules last played the error one-shot: at most one every
    /// `errorEveryMs`.
    var lastErrorAt: Int64?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0
    /// Where a working directory is: its project and workspace.
    let place: (String) -> Adapter.Place
    /// The sessions "needs you" showed for when last published, and why
    /// each that has cleared since did, for their `needs_you` actions.
    var shownNeeds: [String: (agent: Agent, id: String)] = [:]
    var clearedWhy: [String: String] = [:]

    // Push-to-talk (BEHAVIORS.md §3.3).
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// mic button.
    public enum Talker: String, Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// After the mic goes off, the device holds `listening` this long at
    /// most for the reply (firmware `kListenHoldMs`).
    public static let replyWaitMs: Int64 = 8000
    /// While the Mac's mic is on: who turned it on, and when.
    public private(set) var listening: (by: Talker, since: Int64)?
    /// Once the mic is off, until when the device still shows `listening`
    /// waiting for the reply; nil once it's over.
    var replyUntil: Int64?

    /// `lastActiveDay` is today's date from `short-term.md`, if there is one,
    /// so a restart doesn't start the day again. `place` names a working
    /// directory's project (ADAPTERS.md §3).
    public init(config: Config, lastActiveDay: String? = nil,
                place: @escaping (String) -> Adapter.Place = { Adapter.place(cwd: $0) }) {
        self.config = config
        self.lastActiveDay = lastActiveDay
        self.place = place
        lastAsk = config.firstAsk
        rng = SplitMix64(seed: config.seed)
    }

    static func key(_ agent: Agent, _ id: String) -> String { agent.rawValue + "/" + id }

    /// The thread's name as its agent's app shows it, for the session `key`
    /// names (the view's keys are the same), or nil.
    public func name(about key: String) -> String? { sessions[key]?.name }

    /// The asker of a request that came as a `Notification` alone, which
    /// doesn't say who asked: any event from the session answers it.
    static let anyone = "*"

    /// What an agent's event means to the rules.
    enum Step: Equatable {
        case sessionStart, turnStart, activity, needsYou, turnEnd, turnFailed, turnStopped, subagentStart, subagentEnd,
             sessionEnd
    }

    static func step(_ e: Event) -> Step? {
        switch (e.type, e.phase) {
        case (.session, .start?): .sessionStart
        case (.session, .end?): .sessionEnd
        case (.turn, .start?): .turnStart
        case (.turn, .end?):
            switch e["outcome"]?.string {
            case "failed": .turnFailed
            case "stopped": .turnStopped
            default: .turnEnd
            }
        case (.tool, .wait?): .needsYou
        case (.tool, _): .activity
        case (.subagent, .start?): .subagentStart
        case (.subagent, .end?): .subagentEnd
        default: nil
        }
    }

    /// The steps that start or end a turn or a session: from inside a
    /// subagent, only that subagent's.
    static let turnLevel: Set<Step> = [.sessionStart, .turnStart, .turnEnd, .turnFailed, .sessionEnd]

    /// Claude's idle notice comes after a minute at its prompt, so one
    /// sooner than this after you sent a prompt is from before it.
    static let idleNoticeMinMs: Int64 = 30_000

    /// How far apart a request's own hook and its `Notification` may land,
    /// either way round (ADAPTERS.md §4).
    static let noticeLagMs: Int64 = 5000

    /// A one-shot the rules play (BEHAVIORS.md §3.1): its design, and for
    /// `starting` what started.
    struct Shot: Equatable {
        var anim: String
        var ctx: String? = nil
    }

    /// The rules' one-shots (PROTOCOL.md §3 `moment`).
    public static let starting = "starting", stopped = "stopped", error = "error", helperReturn = "helper_return"
    /// The failed calls that play the error one-shot: a command that
    /// exited with an error or timed out, never a request you denied.
    static let errorClasses: Set<String> = ["exit_code", "timeout"]
    /// The error one-shot plays at most once in this long (BEHAVIORS.md §3.1).
    public static let errorEveryMs: Int64 = 30_000

    // MARK: - Inputs

    /// An agent's event, as recorded (its `seq` set): anything else is
    /// ignored. Its time is now.
    @discardableResult
    public func handle(_ event: Event) -> [CoreEffect] {
        guard let agent = event.agent, let session = event.session, let step = Core.step(event) else { return [] }
        let now = event.ts
        let key = Core.key(agent, session)
        var fx: [CoreEffect] = []
        // The event's own session is left until after the event: a Codex
        // request past its grace that the event answers was never shown,
        // so it isn't recorded as needing you either (ADAPTERS.md §4).
        advance(to: now, sparing: key, &fx)
        startDayIfNew(now, &fx)
        let shot = apply(event, step, agent, session, key, now, &fx)
        if var s = sessions[key] {
            promote(&s, now, &fx)
            sessions[key] = s
        }
        if let shot { play(shot, now, &fx) }
        publish(now, &fx)
        return fx
    }

    /// The event's changes to its session, before the snapshot goes out,
    /// and the one-shot it plays, if any (BEHAVIORS.md §3.1).
    private func apply(_ event: Event, _ step: Step, _ agent: Agent, _ session: String, _ key: String, _ now: Int64,
                       _ fx: inout [CoreEffect]) -> Shot? {
        let tool = event["tool"]?.string
        let notice = event["notice"]?.string
        // A finished call: a result with a tool (an `ElicitationResult` has none).
        let done = event.type == .tool && event.phase == .end && tool != nil
        // A session that ended is back only when it starts again: resumed,
        // or a new prompt. Anything else of its came from before the end (a
        // Notification as you quit at the prompt, a background subagent's
        // result, the command Codex's Interrupt aborted).
        if sessions[key] == nil, ended[key] != nil {
            guard event.subagent == nil, step == .sessionStart || step == .turnStart else { return nil }
            ended[key] = nil
        }
        let place = event.cwd.map(self.place)
        var s = sessions[key] ?? Session(agent: agent, id: session, project: place?.project ?? "unknown",
                                         lastEventAt: now, order: takeOrder())
        let waiting = s.needsSince != nil || s.pendingSince != nil
        // Claude's idle notice means it has sat at its prompt for a minute,
        // so one within 30 s of your last prompt is from before it: a new
        // prompt typed just as the minute ran out (ADAPTERS.md §4).
        if step == .turnStopped, notice != nil, let prompted = s.promptedAt,
           now - prompted < Core.idleNoticeMinMs {
            return nil
        }
        // A session is where its events come from, except while a request
        // waits: the strip names where that was made, whatever folder a
        // sibling subagent works in meanwhile (BEHAVIORS.md §3.2).
        if let place, place.project != "unknown", !waiting {
            s.project = place.project
            s.workspace = place.workspace
        }
        if let name = event["name"]?.string { s.name = name }
        if let mode = event["mode"]?.string { s.planMode = mode == "plan" }

        if step == .needsYou {
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
            let asker = notice == nil ? event.subagent ?? "" : Core.anyone
            let kind = notice ?? (tool == nil ? "elicitation_dialog" : "permission_prompt")
            let lateCopy = notice.map(s.clearedNotices.contains) == true
                && s.clearedAt.map { now - $0 < Core.noticeLagMs || !s.calledSinceClear } == true
            if !lateCopy { s.notices.insert(kind) }
            if waiting {
                if notice == nil {
                    if Array(s.askers.keys) == [Core.anyone], s.needsSince.map({ now - $0 < Core.noticeLagMs }) == true {
                        s.askers = [:]
                    }
                    s.askers[asker] = tool ?? ""
                }
            } else if !lateCopy {
                s.askers = [asker: tool ?? ""]
                s.askSeq = event.seq
                if agent == .codex {
                    s.pendingSince = now
                    s.working = true
                } else {
                    s.needsSince = now
                    s.ask = takeAsk()
                    s.working = false
                }
            }
            s.lastEventAt = now
            sessions[key] = s
            return nil
        }

        if step == .subagentStart {
            // A helper starting: the main agent delegates until it ends. Like
            // its end, it isn't activity, and answers no request.
            if let id = event.subagent { helperStarted(&s, id) }
            sessions[key] = s
            return nil
        }

        if step == .subagentEnd || (event.subagent != nil && Core.turnLevel.contains(step)) {
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
            if step == .subagentEnd, let id = event.subagent { subagentEnded(&s, id) }
            if waiting, let id = event.subagent, s.askers.removeValue(forKey: id) != nil {
                if s.askers.isEmpty {
                    clearRequest(&s, now)
                    s.working = s.turnStartedAt != nil
                } else {
                    anotherRequest(&s)
                }
            }
            // A helper Boop saw start returns, while its turn goes on.
            let returned = step == .subagentEnd && event.subagent.map { s.helpers.remove($0) != nil } == true
            sessions[key] = s
            return returned && s.turnStartedAt != nil ? Shot(anim: Core.helperReturn) : nil
        }

        // The asker's next event means it moved on, and so does any
        // turn-level event. A sibling subagent's tool calls don't answer
        // another agent's request. Claude's idle notice (a stopped `turn` end with
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
            let before = s.askers
            defer { denied(&s, before: before, event) }
            let alongside = done && s.askers[asker].map { asked in
                asked.isEmpty || tool.map { $0 != asked } == true
            } == true
            if step != .activity || s.askers[Core.anyone] != nil {
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

        var shot: Shot?
        switch step {
        case .sessionStart:
            // Resumed or compacted, the work goes on; started or cleared,
            // it's a fresh session (BEHAVIORS.md §3.1).
            let source = event["source"]?.string
            shot = Shot(anim: Core.starting, ctx: source == "resume" || source == "compact" ? "continuation" : "session")
            sessions[key] = s
        case .turnStart:
            s.working = true
            s.turnStartedAt = now
            s.promptedAt = now
            clearWork(&s)
            shot = Shot(anim: Core.starting, ctx: "new_task")
            sessions[key] = s
        case .activity:
            var late = false
            if done {
                // The result of a call that started before the turn ended
                // or stopped landed late (Esc as it finished, or a
                // subagent's racing the interrupt): the turn stays over
                // (ADAPTERS.md §4).
                let started = event["tool_use_id"]?.string.flatMap { s.toolStarts.removeValue(forKey: $0) } ?? s.lastToolStart
                if s.turnStartedAt == nil, let at = started, let ended = s.lastTurnEndedAt, at <= ended { late = true }
                let call = endCall(&s, event, now)
                let failed = event["failed"]?.bool == true
                if !late, failed, event["error"]?.string.map(Core.errorClasses.contains) == true {
                    // A command that failed or timed out, not a request
                    // you denied (BEHAVIORS.md §3.1).
                    shot = Shot(anim: Core.error)
                } else if !late, !failed, let call, call.act == .delegating, !call.sawHelper {
                    // A helper's call returned, from hooks that don't say
                    // when helpers start: its `SubagentStop` can't.
                    shot = Shot(anim: Core.helperReturn)
                }
            } else if let tool {
                if let id = event["tool_use_id"]?.string { s.toolStarts[id] = now }
                s.lastToolStart = now
                s.calledSinceClear = true
                startCall(&s, event, tool: tool)
            }
            if !late {
                s.working = true
                // A call opens a turn with no prompt (a background
                // subagent's after the main agent's `Stop`, say).
                if s.turnStartedAt == nil { s.turnStartedAt = now }
            }
            sessions[key] = s
        case .turnEnd, .turnFailed, .turnStopped:
            // Over, done, failed or stopped: a working session goes idle.
            // A stop ends a turn even once the safety net has made the
            // session idle: its turn went on (you approved, which sends no
            // hook), so a call's result after the stop is a late one. Only
            // a stop that ends a turn plays its one-shot: Claude's idle
            // notice after a turn that finished doesn't.
            s.working = false
            if s.turnStartedAt != nil {
                if step == .turnStopped { shot = Shot(anim: Core.stopped) }
                s.turnStartedAt = nil
                s.lastTurnEndedAt = now
            }
            clearWork(&s)
            sessions[key] = s
        case .sessionEnd:
            sessions[key] = nil
            ended[key] = now
        case .needsYou, .subagentStart, .subagentEnd:
            break
        }
        return shot
    }

    /// A rule's one-shot (BEHAVIORS.md §3.1), in Boop's mood with a
    /// variation at random, never the one it played last: not while
    /// something needs you or `listening` holds the screen, and the error
    /// one-shot at most once every `errorEveryMs`. The runtime also holds
    /// it back while a brain moment's line plays.
    func play(_ shot: Shot, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard !needsYouShowing, !showsListening(at: now) else { return }
        if shot.anim == Core.error {
            if let last = lastErrorAt, now - last < Core.errorEveryMs { return }
            lastErrorAt = now
        }
        let variant = Core.pickVariant(mood: config.mood, state: shot.anim, ctx: shot.ctx,
                                       avoiding: lastVariant[shot.anim], &rng)
        lastVariant[shot.anim] = variant
        fx.append(.moment(DeviceMoment(anim: shot.anim, variant: variant, ctx: shot.ctx)))
    }

    /// An `input` message's `k` (PROTOCOL.md §4).
    public enum DeviceInput: String, Sendable {
        case tap, talkOn = "talk_on", talkOff = "talk_off"
    }

    /// An `input` message from the device, recorded as the event `seq`.
    /// The device has already reacted.
    @discardableResult
    public func input(_ input: DeviceInput, at now: Int64, seq: Int? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        switch input {
        case .tap:
            poked(now, seq: seq, &fx)
        case .talkOn:
            // The device already shows `listening`.
            startListening(by: .device, now, &fx)
        case .talkOff:
            stopListening(now, &fx)
        }
        publish(now, &fx)
        return fx
    }

    /// The app's mic button: start or stop listening. The runtime has the
    /// device show `listening` for it.
    @discardableResult
    public func listen(_ on: Bool, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now, &fx)
        startDayIfNew(now, &fx)
        if on { startListening(by: .app, now, &fx) } else { stopListening(now, &fx) }
        publish(now, &fx)
        return fx
    }

    /// The link to the device dropped, so its button's release can't
    /// arrive: stop listening now. The app's mic button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        if listening?.by == .device { stopListening(now, &fx) }
        return fx
    }

    /// The device stopped showing `listening`: the reply went out, or the
    /// runtime ended it with the empty moment because none is coming, or
    /// the mic couldn't start.
    public func listeningEnded() {
        listening = nil
        replyUntil = nil
    }

    /// Whether the device shows `listening` at `now`: the mic is on, or it
    /// went off and the reply hasn't come yet.
    public func showsListening(at now: Int64) -> Bool {
        listening != nil || replyUntil.map { now < $0 } == true
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

    /// Timers: the Codex grace period, the safety net and the mic's 30 s
    /// limit.
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
                agent: $0.agent.short, project: StateSnapshot.clip($0.project, marked: true),
                name: $0.name.map { StateSnapshot.clip($0, marked: true) } ?? "", more: waiting.count - 1, id: $0.ask)
        }
        // What the agents are doing shows only in the working look, and
        // not while something needs you (BEHAVIORS.md §2).
        let act = base == "working" && attn == nil ? shownAct?.act.rawValue : nil
        let visual = attn != nil ? "needs_you" : act ?? base
        return StateSnapshot(base: base, act: act, mood: config.mood, attn: attn, busy: working.count,
                             vol: config.volume, variant: shown.visual == visual ? shown.variant : 1)
    }

    /// A variation of `mood`'s design for `state` at random, from 1, among
    /// those for `outcome` and `ctx` (FaceLoops.variants), never `last`
    /// when there's another (BEHAVIORS.md §1): the rules pick it for now,
    /// and the harness may later.
    public static func pickVariant(mood: String, state: String, outcome: String? = nil, ctx: String? = nil,
                                   avoiding last: Int?, _ rng: inout SplitMix64) -> Int {
        let fit = FaceLoops.variants(mood: mood, state: state, outcome: outcome, ctx: ctx)
        let choices = fit.filter { $0 != last }
        guard !choices.isEmpty else { return fit.first ?? 1 }
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
    /// (BEHAVIORS.md §1), or the mic is on, since a mumble would end
    /// `listening` before you've finished (§3.3).
    public var mumbleBlock: String? {
        if needsYouShowing { return "something needs you" }
        if listening != nil { return "the mic is on" }
        return nil
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

    /// Whether "needs you" shows: then no event's pass starts
    /// (harness/EVENTS.md §6).
    public var needsYouShowing: Bool { sessions.values.contains { $0.needsSince != nil } }

    /// A Codex request whose grace is over, and nothing answered, shows,
    /// dated 2 s after it arrived (ADAPTERS.md §4).
    func promote(_ s: inout Session, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let pending = s.pendingSince, now - pending >= config.codexGraceMs else { return }
        s.pendingSince = nil
        s.needsSince = pending + config.codexGraceMs
        s.ask = takeAsk()
        s.working = false
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
    /// the device alerts again if it's the one shown (BEHAVIORS.md §3.2).
    func anotherRequest(_ s: inout Session) {
        if s.needsSince != nil { s.ask = takeAsk() }
    }

    /// Nobody is waiting on the session any more; `why` it cleared if
    /// nobody answered.
    func clearRequest(_ s: inout Session, _ now: Int64, why: String? = nil) {
        if s.needsSince != nil, let why { clearedWhy[s.key] = why }
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

    /// A poke: the device plays its poke (`poked`, `tap_spam` from the third
    /// in a row), and the brain hears of it through the view, which counts
    /// the pokes in a row (BEHAVIORS.md §3.3). The rules add no animation of
    /// their own, but record it, as the `wiggle` action whose older name and
    /// words Jev reads (harness/EVENTS.md §2). While something needs you a
    /// poke means "I saw it", and while `listening` shows nothing replaces
    /// it: the device plays no poke, so nothing is recorded.
    func poked(_ now: Int64, seq: Int?, _ fx: inout [CoreEffect]) {
        guard !needsYouShowing, !showsListening(at: now) else { return }
        fx.append(.record(Event(ts: now, source: .boop, type: .action, specificType: Core.wiggle,
                                data: ["for": seq.map { .int(Int64($0)) } ?? .null, "by": "rule", "ok": true,
                                       "message": .string(Core.wiggled)])))
    }

    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening == nil else { return }
        listening = (talker, now)
        replyUntil = nil
        fx.append(.listen(true, by: talker))
    }

    /// Turns the mic off, if it's on. The device holds `listening` for the
    /// reply until the runtime says it's over (`listeningEnded`), or
    /// `replyWaitMs` at most.
    func stopListening(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let l = listening else { return }
        listening = nil
        replyUntil = now + Self.replyWaitMs
        fx.append(.listen(false, by: l.by))
    }

    /// The rule actions' names and messages (harness/EVENTS.md §2).
    public static let wiggle = "wiggle"
    public static let wiggled = "Boop wiggled on its own."
    public static let needsYou = "needs_you"

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
                clearRequest(&s, now, why: "nothing for 10 minutes")
                s.working = false
            }
            if now - s.lastEventAt >= config.forgetMs {
                if s.needsSince != nil { clearedWhy[key] = "forgotten" }
                sessions[key] = nil
            } else {
                sessions[key] = s
            }
        }
        ended = ended.filter { now - $0.value < config.forgetMs }
    }

    /// "Needs you" starting or clearing for a session, as a rule action:
    /// the view says who needs you from it, and knows while nothing may
    /// wake the brain (harness/EVENTS.md §2). A session gone while it
    /// waited clears too.
    func recordNeeds(_ now: Int64, _ fx: inout [CoreEffect]) {
        let showing = sessions.filter { $0.value.needsSince != nil }
        for (key, s) in showing.sorted(by: { ($0.value.needsSince!, $0.value.ask) < ($1.value.needsSince!, $1.value.ask) })
        where shownNeeds[key] == nil {
            shownNeeds[key] = (s.agent, s.id)
            clearedWhy[key] = nil
            fx.append(.record(Event(ts: now, source: .boop, type: .action, phase: .start, specificType: Core.needsYou,
                                    session: s.id,
                                    data: ["for": s.askSeq.map { .int(Int64($0)) } ?? .null, "by": "rule",
                                           "agent": .string(s.agent.short), "ok": true,
                                           "message": .string("Boop showed that \(s.agent.short) needs you.")])))
        }
        for (key, was) in shownNeeds.sorted(by: { $0.key < $1.key }) where showing[key] == nil {
            shownNeeds[key] = nil
            let why = clearedWhy.removeValue(forKey: key) ?? (sessions[key] == nil ? "the session ended" : nil)
            var data: [String: JSONValue] = ["by": "rule", "agent": .string(was.agent.short),
                                             "outcome": why == nil ? "done" : "failed"]
            if let why { data["why"] = .string(why) }
            fx.append(.record(Event(ts: now, source: .boop, type: .action, phase: .end, specificType: Core.needsYou,
                                    session: was.id, data: data)))
        }
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        recordNeeds(now, &fx)
        updateActs(now)
        var snapshot = snapshot(at: now)
        if snapshot.visual != shown.visual || shown.variant > FaceLoops.count(mood: config.mood, state: snapshot.visual) {
            // A new visual, or a new mood with fewer variations of it than
            // the one showing: a variation of it at random.
            shown = (snapshot.visual, Core.pickVariant(mood: config.mood, state: snapshot.visual,
                                                         avoiding: lastVariant[snapshot.visual], &rng))
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
    /// The thread's name as its agent's app shows it, once an event brought one.
    public var name: String?
    /// The thread's workspace: a linked worktree's folder or the branch,
    /// or nil when the folder has neither.
    public var workspace: String?
    public var status: Status

    public init(agent: String, project: String, name: String? = nil, workspace: String? = nil, status: Status) {
        self.agent = agent
        self.project = project
        self.name = name
        self.workspace = workspace
        self.status = status
    }

    init(_ s: Core.Session, _ status: Status) {
        self.init(agent: s.agent.short, project: s.project, name: s.name, workspace: s.workspace, status: status)
    }
}
