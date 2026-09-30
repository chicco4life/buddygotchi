import Foundation

/// The core (ARCHITECTURE.md §3.2): plain rules with no queue. It keeps the
/// session table and decides which visual the device shows, what the
/// agents are doing included (`act`), and which one-shots the rules play
/// (BEHAVIORS.md §3.1). What it does by rule it records as `action`
/// events: "needs you" showing and ending, and a poke (the `wiggle`
/// action, by its older name: the device plays its poke), or while
/// something needs you, the thread it opens (`open_thread`). What the
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

    /// A session: its `Turn`, as the view keeps it too, and what the rules
    /// add.
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
        /// The app the agent runs in and that app's ID for the session, the
        /// last an event brought: where a tap opens the thread.
        var app: String?
        var appSession: String?
        /// Working on a turn: not idle, and not waiting on "needs you".
        var working = false
        var turn = Turn()
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
        /// The tool calls running this turn, for the look, by
        /// `tool_use_id` or a key of their own (BEHAVIORS.md §2).
        var calls: [String: Call] = [:]
        /// The helpers seen starting this turn (`SubagentStart`) that
        /// haven't ended, by `agent_id`: the main agent is delegating.
        var helpers: Set<String> = []
        /// Claude's plan mode, as the last event that said had it.
        var planMode = false
        /// Its activity as it shows, held (`Core.settle`).
        var held: Timed?

        var key: String { SessionFold.key(agent, id) }
    }

    public private(set) var config: Config

    var sessions: [String: Session] = [:]
    /// Which sessions ended, and the order sessions were first seen in.
    var fold = SessionFold()
    /// The last request's number: they count up from `config.firstAsk`.
    var lastAsk: Int
    var rng: SplitMix64
    /// The last day with any activity, or the day the app opened: the first
    /// activity of a later one is a new day.
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
    var shownAct: Timed?
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

    /// `lastActiveDay` is the day the app opened, which the launch has
    /// started already, or nil to make the first activity a new day.
    /// `place` names a working directory's project (ADAPTERS.md §3).
    public init(config: Config, lastActiveDay: String? = nil,
                place: @escaping (String) -> Adapter.Place = { Adapter.place(cwd: $0) }) {
        self.config = config
        self.lastActiveDay = lastActiveDay
        self.place = place
        lastAsk = config.firstAsk
        rng = SplitMix64(seed: config.seed)
    }

    /// The thread's name as its agent's app shows it, for the session `key`
    /// names (the view's keys are the same), or nil.
    public func name(about key: String) -> String? { sessions[key]?.name }

    /// Where the session `key` names opens on the Mac, or nil.
    public func thread(about key: String) -> ThreadRef? { sessions[key].map(ThreadRef.init) }

    /// The asker of a request that came as a `Notification` alone, which
    /// doesn't say who asked: any event from the session answers it.
    static let anyone = "*"

    /// How far apart a request's own hook and its `Notification` may land,
    /// either way round (ADAPTERS.md §4).
    static let noticeLagMs: Int64 = 5000

    /// Codex's grace period before "needs you" shows (ADAPTERS.md §4).
    static let codexGraceMs: Int64 = 2000

    /// In its first second, a request from "anyone" isn't answered by a
    /// call: its own hook may still be coming, and nobody answers a prompt
    /// that fast (ADAPTERS.md §4).
    static let noticeFirstMs: Int64 = 1000

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
        guard let agent = event.agent, let session = event.session, let step = SessionFold.step(event) else { return [] }
        let now = event.ts
        var fx: [CoreEffect] = []
        let shot = take(event, step, agent, session)
        startDayIfNew(now, &fx)
        if let shot { play(shot, now, &fx) }
        publish(now, &fx)
        return fx
    }

    /// `event` without the name, app, app session and mode its session
    /// already has, which `apply` carries on, so the transcript doesn't
    /// repeat them on every line (harness/EVENTS.md §2). A session this
    /// core doesn't hold, or forgets before the event, gets them all, and
    /// so does its first event of each of the transcript's days: a launch
    /// reads back only the last days' files.
    func unrepeated(_ event: Event) -> Event {
        guard let agent = event.agent, let session = event.session,
              let s = sessions[SessionFold.key(agent, session)], !SessionFold.forgotten(s.lastEventAt, at: event.ts),
              config.time.day(s.lastEventAt) == config.time.day(event.ts) else { return event }
        var event = event
        for (key, held) in [("name", s.name), ("app", s.app), ("app_session", s.appSession)]
        where held != nil && event[key]?.string == held {
            event.data[key] = nil
        }
        if let mode = event["mode"]?.string, (mode == "plan") == s.planMode { event.data["mode"] = nil }
        return event
    }

    /// A launch picks the sessions up from the transcript it reads back, as
    /// the view does (ARCHITECTURE.md §6): each agent event is taken as
    /// `handle` takes it, and the timers run at every event's time, as the
    /// last launch's ticks did when they recorded something. What the
    /// rules did then is recorded already, so nothing is carried out.
    /// Which requests were shown is what the `needs_you` records say, as
    /// the view has it: where the sessions folded again disagree, the
    /// first publish records the start or end that's missing, with why a
    /// request the read-back cleared did.
    public func replay(_ event: Event) {
        if let agent = event.agent, let session = event.session, let step = SessionFold.step(event) {
            _ = take(event, step, agent, session)
            return
        }
        advance(to: event.ts)
        if event.type == .action, event.specificType == Core.needsYou, let session = event.session,
           let agent = event["agent"]?.string.flatMap(Agent.init(rawValue:)) {
            let key = SessionFold.key(agent, session)
            shownNeeds[key] = event.phase == .start ? (agent, session) : nil
            if event.phase == .start { clearedWhy[key] = nil }
        }
    }

    /// An agent's event folded into the session table, the timers due by
    /// its time run first: the one-shot it plays, if any.
    private func take(_ event: Event, _ step: SessionFold.Step, _ agent: Agent, _ session: String) -> DeviceMoment? {
        let now = event.ts
        let key = SessionFold.key(agent, session)
        // The event's own session is left until after the event: a Codex
        // request past its grace that the event answers was never shown,
        // so it isn't recorded as needing you either (ADAPTERS.md §4).
        advance(to: now, sparing: key)
        let shot = apply(event, step, agent, session, key, now)
        if var s = sessions[key] {
            promote(&s, now)
            sessions[key] = s
        }
        return shot
    }

    /// The event's changes to its session, before the snapshot goes out,
    /// and the one-shot it plays, if any (BEHAVIORS.md §3.1).
    private func apply(_ event: Event, _ step: SessionFold.Step, _ agent: Agent, _ session: String, _ key: String,
                       _ now: Int64) -> DeviceMoment? {
        let tool = event["tool"]?.string
        let notice = event["notice"]?.string
        // A finished call: a result with a tool (an `ElicitationResult` has none).
        let done = event.type == .tool && event.phase == .end && tool != nil
        guard fold.admits(event, step, key: key, known: sessions[key] != nil) else { return nil }
        let place = event.cwd.map(self.place)
        var s = sessions[key] ?? Session(agent: agent, id: session, project: place?.project ?? "unknown",
                                         lastEventAt: now, order: fold.takeOrder())
        let waiting = s.needsSince != nil || s.pendingSince != nil
        if s.turn.isStaleNotice(event, step) { return nil }
        // A session is where its events come from, except while a request
        // waits: the strip names where that was made, whatever folder a
        // sibling subagent works in meanwhile (BEHAVIORS.md §3.2).
        if let place, place.project != "unknown", !waiting {
            s.project = place.project
            s.workspace = place.workspace
        }
        if let name = event["name"]?.string { s.name = name }
        if let app = event["app"]?.string { s.app = app }
        if let appSession = event["app_session"]?.string { s.appSession = appSession }
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

        if SessionFold.subagentsOwn(event, step) {
            // A subagent that has finished can't be waiting on a prompt, so
            // its end answers its own request: denied, it carried on and
            // ended without another tool call. It answers nobody else, not
            // even "anyone". It isn't activity either: the session doesn't
            // start working and its clock doesn't move, so it can't make an
            // idle or stale session look busy. Once no asker is left, the
            // session works again only if its turn is still going
            // (ADAPTERS.md §4). A turn-level hook from inside a subagent
            // (its `agent_id` on a `StopFailure`, say) is that subagent's
            // alone too, not the session's turn, but only its end ends it:
            // a helper that worked on with no turn open (in the
            // background, after the main agent's `Stop`) is done once none
            // of its calls runs.
            if step == .subagentEnd, let id = event.subagent {
                subagentEnded(&s, id)
                if s.turn.startedAt == nil, s.calls.isEmpty, s.pendingSince == nil { s.working = false }
            }
            if waiting, let id = event.subagent, s.askers.removeValue(forKey: id) != nil {
                if s.askers.isEmpty {
                    clearRequest(&s, now)
                    s.working = s.turn.startedAt != nil
                } else {
                    anotherRequest(&s)
                }
            }
            // A helper Boop saw start returns, while its turn goes on.
            let returned = step == .subagentEnd && event.subagent.map { s.helpers.remove($0) != nil } == true
            sessions[key] = s
            return returned && s.turn.startedAt != nil ? DeviceMoment(anim: Core.helperReturn) : nil
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
        // `ElicitationResult` or the agent's next call, never a result. A
        // request from "anyone" is answered by any event, but by a call only
        // after its first second: a sibling's can land between a
        // `Notification` and its request's own hook.
        if waiting {
            let asker = event.subagent ?? ""
            let before = s.askers
            defer { denied(&s, before: before, event) }
            let alongside = done && s.askers[asker].map { asked in
                asked.isEmpty || tool.map { $0 != asked } == true
            } == true
            let anyoneAnswered = s.askers[Core.anyone] != nil
                && s.needsSince.map { now - $0 >= Core.noticeFirstMs } != false
            if step != .activity || anyoneAnswered {
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

        var shot: DeviceMoment?
        switch step {
        case .sessionStart:
            // Resumed or compacted, the work goes on; started or cleared,
            // it's a fresh session (BEHAVIORS.md §3.1).
            let source = event["source"]?.string
            shot = DeviceMoment(anim: Core.starting, ctx: source == "resume" || source == "compact" ? "continuation" : "session")
            sessions[key] = s
        case .turnStart:
            s.working = true
            s.turn.prompted(at: now)
            clearWork(&s)
            shot = DeviceMoment(anim: Core.starting, ctx: "new_task")
            sessions[key] = s
        case .activity:
            // A result that landed late leaves the turn over (ADAPTERS.md §4).
            var late = false
            if done {
                late = s.turn.callEnded(event).late
                let call = endCall(&s, event, now)
                let failed = event["failed"]?.bool == true
                if !late, failed, event["error"]?.string.map(Core.errorClasses.contains) == true {
                    // A command that failed or timed out, not a request
                    // you denied (BEHAVIORS.md §3.1).
                    shot = DeviceMoment(anim: Core.error)
                } else if !late, !failed, let call, call.act == .delegating, !call.sawHelper {
                    // A helper's call returned, from hooks that don't say
                    // when helpers start: its `SubagentStop` can't.
                    shot = DeviceMoment(anim: Core.helperReturn)
                }
            } else if let tool {
                s.turn.callStarted(event)
                s.calledSinceClear = true
                startCall(&s, event, tool: tool)
            }
            if !late {
                s.working = true
                s.turn.openTurn(event)
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
            if s.turn.endTurn(at: now) != nil, step == .turnStopped { shot = DeviceMoment(anim: Core.stopped) }
            clearWork(&s)
            sessions[key] = s
        case .sessionEnd:
            sessions[key] = nil
            fold.end(key, at: now)
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
    func play(_ shot: DeviceMoment, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let anim = shot.anim, !needsYouShowing, !showsListening(at: now) else { return }
        if anim == Core.error {
            if let last = lastErrorAt, now - last < Core.errorEveryMs { return }
            lastErrorAt = now
        }
        var moment = shot
        moment.variant = Core.pickVariant(mood: config.mood, state: anim, ctx: shot.ctx,
                                          avoiding: lastVariant[anim], &rng)
        lastVariant[anim] = moment.variant
        fx.append(.moment(moment))
    }

    /// A tap on the device, recorded as the poke `seq`, on the brain's
    /// finish for `finish`'s thread, if the device said so. The device has
    /// already reacted.
    @discardableResult
    public func poke(at now: Int64, seq: Int? = nil, finish: ThreadRef? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        poked(now, seq: seq, finish: finish, &fx)
        publish(now, &fx)
        return fx
    }

    /// Push-to-talk: start or stop listening, after the device's BOOT
    /// button (`talk_on`, `talk_off`), which already shows `listening`, or
    /// the app's mic button, for which the runtime has the device show it.
    @discardableResult
    public func listen(_ on: Bool, by talker: Talker = .app, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        if on { startListening(by: talker, now, &fx) } else { stopListening(now, &fx) }
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
        advance(to: now)
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
                agent: $0.agent.rawValue, project: StateSnapshot.clip($0.project, marked: true, max: StateSnapshot.maxSignBytes),
                name: $0.name.map { StateSnapshot.clip($0, marked: true, max: StateSnapshot.maxSignBytes) } ?? "",
                more: waiting.count - 1, id: $0.ask)
        }
        // What the agents are doing shows only in the working look, and
        // not while something needs you (BEHAVIORS.md §2).
        let act = base == "working" && attn == nil ? shownAct?.act.rawValue : nil
        var snapshot = StateSnapshot(base: base, act: act, mood: config.mood, attn: attn, busy: working.count,
                                     vol: config.volume, variant: 1)
        if shown.visual == snapshot.visual { snapshot.variant = shown.variant }
        return snapshot
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

    /// Why nothing but what you said wakes the brain (a tap then opens the
    /// thread), and no reaction plays, or nil: something needs you
    /// (BEHAVIORS.md §1, harness/EVENTS.md §6).
    public var needsYouBlock: String? {
        needsYouShowing ? "something needs you" : nil
    }

    /// Why a reaction can't play now, or nil: something needs you, or the
    /// mic is on, since a reaction would end `listening` before you've
    /// finished (BEHAVIORS.md §3.3).
    public var reactionBlock: String? {
        needsYouBlock ?? (listening != nil ? "the mic is on" : nil)
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

    /// The date at steady time `now`, on the wall clock: the calendar never
    /// sees steady time.
    private func day(_ now: Int64) -> String { config.time.day(wall(now)) }

    func isWorking(_ s: Session, _ now: Int64) -> Bool {
        s.working && now - s.lastEventAt < SessionFold.staleWorkMs
    }

    /// Whether "needs you" shows: then no event's pass starts
    /// (harness/EVENTS.md §6).
    public var needsYouShowing: Bool { sessions.values.contains { $0.needsSince != nil } }

    /// A Codex request whose grace is over, and nothing answered, shows,
    /// dated 2 s after it arrived (ADAPTERS.md §4).
    func promote(_ s: inout Session, _ now: Int64) {
        guard let pending = s.pendingSince, now - pending >= Core.codexGraceMs else { return }
        s.pendingSince = nil
        s.needsSince = pending + Core.codexGraceMs
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

    /// The first activity of a new day, for the transcript's pruning.
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
    /// words Jev reads (harness/EVENTS.md §2). While `listening` shows
    /// nothing replaces it: the device plays no poke, so nothing is
    /// recorded. While something needs you the device plays no poke either:
    /// the tap opens the thread the sign names on the Mac, recorded as the
    /// `open_thread` action (BEHAVIORS.md §3.2). Nor on the brain's finish
    /// that names whose turn it was: the tap opens that thread
    /// (BEHAVIORS.md §3.3).
    func poked(_ now: Int64, seq: Int?, finish: ThreadRef?, _ fx: inout [CoreEffect]) {
        guard !showsListening(at: now) else { return }
        let seq: JSONValue = seq.map { .int(Int64($0)) } ?? .null
        func open(_ thread: ThreadRef, _ message: String) {
            fx.append(.record(Event(ts: now, source: .boop, type: .action, specificType: Core.openThread,
                                    data: ["for": seq, "by": "rule", "ok": true, "agent": .string(thread.agent),
                                           "message": .string(message)])))
            fx.append(.open(thread))
        }
        if let waiting = grouped(at: now).waiting.first { return open(ThreadRef(waiting), Core.openedThread) }
        if let finish { return open(finish, Core.openedFinished) }
        fx.append(.record(Event(ts: now, source: .boop, type: .action, specificType: Core.wiggle,
                                data: ["for": seq, "by": "rule", "ok": true, "message": .string(Core.wiggled)])))
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
    public static let openThread = "open_thread"
    public static let openedThread = "Boop opened the thread that needs you on the Mac."
    public static let openedFinished = "Boop opened the thread that finished on the Mac."
    public static let needsYou = "needs_you"

    /// Runs every timer due by `now`, in order, but shows no Codex request
    /// of `sparing`'s session: its event comes first. Only a session with a
    /// Codex request in its grace, or silent 10 minutes, has one.
    func advance(to now: Int64, sparing: String? = nil) {
        for (key, var s) in sessions where s.pendingSince != nil || now - s.lastEventAt >= SessionFold.safetyNetMs {
            let silent = now - s.lastEventAt >= SessionFold.safetyNetMs
            if !silent && key != sparing { promote(&s, now) }
            if silent && (s.needsSince != nil || s.pendingSince != nil) {
                // Ten silent minutes, even for a Codex request no tick saw
                // through its grace (the Mac slept): the agent is still
                // waiting on its prompt, or gone. Either way it isn't
                // working. Its turn, if it goes on, still
                // counts from its start.
                clearRequest(&s, now, why: "nothing for 10 minutes")
                s.working = false
            }
            if SessionFold.forgotten(s.lastEventAt, at: now) {
                if s.needsSince != nil { clearedWhy[key] = "forgotten" }
                sessions[key] = nil
            } else {
                sessions[key] = s
            }
        }
        fold.forgetEnds(at: now)
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
                                           "agent": .string(s.agent.rawValue), "ok": true,
                                           "message": .string("Boop showed that \(s.agent.rawValue) needs you.")])))
        }
        for (key, was) in shownNeeds.sorted(by: { $0.key < $1.key }) where showing[key] == nil {
            shownNeeds[key] = nil
            let why = clearedWhy.removeValue(forKey: key) ?? (sessions[key] == nil ? "the session ended" : nil)
            var data: [String: JSONValue] = ["by": "rule", "agent": .string(was.agent.rawValue),
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
    /// Which thread it is, for clicking the row open.
    public var thread: ThreadRef?

    public init(agent: String, project: String, name: String? = nil, workspace: String? = nil, status: Status,
                thread: ThreadRef? = nil) {
        self.agent = agent
        self.project = project
        self.name = name
        self.workspace = workspace
        self.status = status
        self.thread = thread
    }

    init(_ s: Core.Session, _ status: Status) {
        self.init(agent: s.agent.rawValue, project: s.project, name: s.name, workspace: s.workspace, status: status,
                  thread: ThreadRef(s))
    }
}

/// One agent thread, as much as opening it on the Mac needs
/// (`ThreadLink`): the agent's session ID, the app it runs in and that
/// app's own ID for it.
public struct ThreadRef: Equatable, Sendable {
    /// `claude` or `codex`.
    public var agent: String
    public var session: String
    /// The app's bundle ID (HookWire's `HostApp`), when the hooks said.
    public var app: String?
    /// The Claude app's `local_…` ID.
    public var appSession: String?

    public init(agent: String, session: String, app: String? = nil, appSession: String? = nil) {
        self.agent = agent
        self.session = session
        self.app = app
        self.appSession = appSession
    }

    init(_ s: Core.Session) {
        self.init(agent: s.agent.rawValue, session: s.id, app: s.app, appSession: s.appSession)
    }
}
