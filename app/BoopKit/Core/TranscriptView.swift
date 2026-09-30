import Foundation

/// One thing the brain may hear of (harness/EVENTS.md §3): a raw event's
/// type and phase, with what the view worked out about it and its line of
/// text.
public struct ViewEvent: Equatable, Sendable {
    /// What Boop did about it: a rule's action or the brain's, by its
    /// message, and whether it's still going.
    public struct Did: Equatable, Sendable {
        public enum State: String, Sendable { case done, inProgress = "in_progress" }
        public var message: String
        /// `rule`, `brain` or `dashboard`.
        public var by: String
        public var state: State
        /// The `action` event it came from.
        public var seq: Int
    }

    /// Its number in the view, counting up from the view's first.
    public var id: Int
    public var type: Event.Kind
    public var phase: Event.Phase?
    /// The raw events it came from; the last is the one that made it.
    public var from: [Int]
    public var ts: Int64
    /// What happened, as HISTORY and NOW show it (EVENTS.md §8).
    public var line: String
    /// Lines that go under it, before what Boop did: a finished turn's
    /// last message.
    public var notes: [String] = []
    /// Whether it wakes the brain: its kind's rule, then the gates (§6).
    public var wakesBrain: Bool
    /// How its pass waits behind a running one (harness/HARNESS.md §2):
    /// a newer view event replaces one waiting at 0, and waits behind the
    /// ones waiting at its own or higher. A finished turn is 1 and what
    /// you said 2, so no finish loses its pass and the next pass answers
    /// you.
    public var passPriority = 0
    /// The thread it's about, as the view keys threads; nil for pokes,
    /// what you said and idle heartbeats.
    public var about: String?
    /// For logs, evals and tests; the harness never reads them.
    public var facts: [String: JSONValue] = [:]
    public var did: [Did] = []

    /// The raw event that made it.
    public var seq: Int { from.last ?? 0 }

    /// `turn end`, `tool wait`, `poke`: its type and phase.
    public var name: String { phase.map { "\(type.rawValue) \($0.rawValue)" } ?? type.rawValue }

    /// The view event as one JSON object, for `debug.jsonl`.
    public var json: [String: Any] {
        var o: [String: Any] = ["id": id, "type": type.rawValue, "from": from, "line": line, "notes": notes,
                                "wakes_brain": wakesBrain, "facts": facts.mapValues(\.foundation)]
        if let phase { o["phase"] = phase.rawValue }
        return o
    }

    /// `turn end · claude finished …`, for debug mode and replays.
    public var summary: String {
        "\(name)\(wakesBrain ? "" : " (no pass)") · \(line)" + notes.map { " · \($0)" }.joined()
    }
}

/// The view (harness/EVENTS.md §3): folds the transcript's raw events, one
/// at a time and in order, into view events: which turn a thread is on and
/// how long it ran, which checks failed, pokes in a row, heartbeats, who
/// needs you, and what Boop did about each. The same events always give
/// the same view, so a launch replays the transcript to pick up where it
/// left off. The heartbeat's timing is the one thing it decides from the
/// clock (`heartbeat(at:)`). Touched only on the runtime's queue.
public final class TranscriptView {
    /// One agent session, as the lines name it: its `Turn`, as the core
    /// keeps it too, and what the turn did.
    struct Thread {
        var agent: Agent
        var id: String
        var project = "unknown"
        var workspace: String?
        let order: Int
        var lastEventAt: Int64
        /// Turns started since the view first saw the thread.
        var turns = 0
        var turn = Turn()
        /// This turn's tool calls, and how many failed.
        var tools = 0
        var toolsFailed = 0
        /// This turn's topics, in the order first seen, with their last state.
        var topicStates: [(topic: String, state: String)] = []
        /// A topic that passed after failing this turn.
        var comeback: String?
        /// This turn's latest topic, and its last check and whether it failed.
        var topic: String?
        var check: (topic: String, failed: Bool)?
        /// Failures in a row of each check topic, across turns.
        var failRuns: [String: Int] = [:]
        /// "Needs you" shows for it (the core's `needs_you` action), and
        /// whether its last event asked for you: silent for the safety
        /// net's 10 minutes after that, it isn't working (ADAPTERS.md §4).
        var waiting = false
        var asked = false

        var name: String { workspace ?? project }
        var key: String { SessionFold.key(agent, id) }
    }

    /// The personality's settings: how often the working heartbeat comes
    /// and which tool uses wake the brain (BEHAVIORS.md §6).
    public private(set) var rules: Personality.Rules
    let place: (String) -> Adapter.Place

    /// The view events, oldest first, up to `limit`.
    public private(set) var events: [ViewEvent] = []
    /// Past this many view events the oldest are let go.
    public static let limit = 1000
    var nextID = 1

    var threads: [String: Thread] = [:]
    /// Which sessions ended, and the order threads were first seen in.
    var fold = SessionFold()

    // The run of pokes going on (BEHAVIORS.md §3.3).
    var pokes: [Int64] = []

    /// The away you haven't come back from (EVENTS.md §2.1): its event's
    /// `seq` and when you left.
    var awaySince: (seq: Int, at: Int64)?

    // Heartbeats (EVENTS.md §4).
    /// The last agent event, poke, thing you said or coming back, and the
    /// idle heartbeats since.
    var lastActivityAt: Int64?
    var heartbeats = 0
    /// When the working heartbeat is next due; nil until work starts, and
    /// again once Boop starts a reaction.
    var nextWorkBeatAt: Int64?
    var rng: SplitMix64

    /// Where each started action's line is, by its `action` event's `seq`.
    var started: [Int: (view: Int, did: Int, name: String)] = [:]
    /// The reactions a tap cut short, by their `action` event's `seq`,
    /// still `(in progress)` while the run of pokes goes on (EVENTS.md §7).
    var heldByPokes: Set<Int> = []
    /// The brain's latest reaction to this run's pokes in a row, by its
    /// `action` event's `seq`, and whether the mood changed since it
    /// started.
    var runReaction: (seq: Int, moodChanged: Bool)?

    public init(rules: Personality.Rules = Personality.Rules(), seed: UInt64 = 1,
                place: @escaping (String) -> Adapter.Place = { Adapter.place(cwd: $0) }) {
        self.rules = rules
        self.place = place
        rng = SplitMix64(seed: seed)
    }

    /// What you say to Boop wakes the brain even while something needs
    /// you; nothing else does, a poke included: then a tap opens the
    /// waiting thread (EVENTS.md §6).
    public static let wakesWhileNeeded: Set<Event.Kind> = [.talk]

    /// The topics whose failing command fails a turn (BEHAVIORS.md §3.1).
    static let checks: Set<String> = ["tests", "build", "deploy"]

    /// A poke within this of the one before is another in a row, which its
    /// line counts (BEHAVIORS.md §3.3).
    public static let inARowMs: Int64 = 3000
    /// The brain's reaction to this many pokes in a row or more answers the
    /// run; to fewer, the pokes after it still wake the brain, so Boop can
    /// go from glad to miffed to grumpy (EVENTS.md §6).
    public static let answersRunFrom = 3
    /// While no thread works, a heartbeat after this long with no event,
    /// and again every time as long again passes (EVENTS.md §4).
    public static let heartbeatMs: Int64 = 60 * 60 * 1000

    /// A new personality's settings, from the next event on. The working
    /// heartbeat starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        self.rules = rules
        nextWorkBeatAt = nil
    }

    // MARK: - Folding

    /// Folds one recorded event into the view and returns the view events
    /// it made, whose `wakesBrain` is their kind's alone: the caller gates
    /// them (`gate`).
    @discardableResult
    public func take(_ e: Event) -> [ViewEvent] {
        let first = nextID
        if !heldByPokes.isEmpty && !continuesThePokes(e) { releasePokes() }
        switch e.type {
        case .session, .turn, .tool, .subagent: agentEvent(e)
        case .poke: poke(e)
        case .talk: talk(e)
        case .presence: presence(e)
        case .heartbeat: heartbeat(e)
        case .action: action(e)
        }
        return events.suffix(nextID - first)
    }

    /// Lets the newest view events wake the brain only where `allowed`
    /// says: a brain, and nothing needs you once the event has answered any
    /// request it answers, pokes aside (EVENTS.md §6). Returns them as
    /// gated.
    public func gate(_ made: [ViewEvent], allowed: (ViewEvent) -> Bool) -> [ViewEvent] {
        var out = made
        for i in out.indices {
            if !allowed(out[i]) { out[i].wakesBrain = false }
            if let at = index(of: out[i].id) { events[at].wakesBrain = out[i].wakesBrain }
        }
        return out
    }

    /// The agent and the name of the thread `key` names (the view event's
    /// `about`), as its lines name it: its workspace, else its project.
    public func who(about key: String) -> (agent: String, thread: String)? {
        threads[key].map { ($0.agent.rawValue, $0.name) }
    }

    func index(of id: Int) -> Int? {
        guard let first = events.first else { return nil }
        let at = id - first.id
        return events.indices.contains(at) && events[at].id == id ? at : nil
    }

    /// The view event with this id, if the view still holds it.
    public func event(_ id: Int) -> ViewEvent? { index(of: id).map { events[$0] } }

    /// Whether the view keeps a view event of this type and phase
    /// (EVENTS.md §3): turns' starts and ends, tool calls that wait on you,
    /// pokes, what you said, you stepping away and coming back, and
    /// heartbeats, and tool calls' ends when
    /// notable, or every one with `allToolEnds` (the personality's
    /// `tool_uses: all`, BEHAVIORS.md §6). The rest are read, for what
    /// they tell the view, and dropped.
    public static func keeps(_ type: Event.Kind, _ phase: Event.Phase?, notable: Bool, allToolEnds: Bool) -> Bool {
        switch (type, phase) {
        case (.turn, .start?), (.turn, .end?), (.tool, .wait?), (.poke, nil), (.talk, nil), (.heartbeat, nil),
             (.presence, .start?), (.presence, .end?): true
        case (.tool, .end?): notable || allToolEnds
        default: false
        }
    }

    /// Keeps a view event of `e`'s type and phase, if `keeps` does.
    func add(_ e: Event, from: [Int]? = nil, notable: Bool = true, line: @autoclosure () -> String,
             notes: [String] = [], wakes: Bool, passPriority: Int = 0, about: String? = nil,
             facts: @autoclosure () -> [String: JSONValue] = [:]) {
        guard TranscriptView.keeps(e.type, e.phase, notable: notable, allToolEnds: rules.toolUses == .all) else { return }
        events.append(ViewEvent(id: nextID, type: e.type, phase: e.phase, from: from ?? [e.seq], ts: e.ts, line: line(),
                                notes: notes, wakesBrain: wakes, passPriority: passPriority, about: about, facts: facts()))
        nextID += 1
        if events.count > TranscriptView.limit {
            let drop = events.count - TranscriptView.limit
            events.removeFirst(drop)
            started = started.filter { $0.value.view >= drop }.mapValues { ($0.view - drop, $0.did, $0.name) }
        }
    }

    // MARK: Agents

    func agentEvent(_ e: Event) {
        guard let agent = e.agent, let session = e.session, let step = SessionFold.step(e) else { return }
        let now = e.ts
        let key = SessionFold.key(agent, session)
        // Threads silent for a day are let go, as the core lets their
        // sessions go: one that comes back starts again from turn 0.
        for (k, t) in threads where SessionFold.forgotten(t.lastEventAt, at: now) { threads[k] = nil }
        fold.forgetEnds(at: now)
        guard fold.admits(e, step, key: key, known: threads[key] != nil) else { return }
        var t = threads[key] ?? newThread(agent, session, now)
        if t.turn.isStaleNotice(e, step) { return }
        if let cwd = e.cwd, !t.waiting {
            let place = self.place(cwd)
            if place.project != "unknown" {
                t.project = place.project
                t.workspace = place.workspace
            }
        }
        noteActivity(now)
        // A request, and a subagent's start, end or its own turn-level
        // hook, don't move the thread's turn; only the rules care
        // (ADAPTERS.md §4).
        if step == .needsYou {
            t.lastEventAt = now
            t.asked = true
            threads[key] = t
            return
        }
        if SessionFold.subagentsOwn(e, step) {
            threads[key] = t
            return
        }
        t.lastEventAt = now
        t.asked = false

        switch step {
        case .turnStart:
            t.turn.prompted(at: now)
            t.topic = nil
            t.turns += 1
            resetCounts(&t)
            threads[key] = t
            let prompt = e["prompt"]?.string
            add(e, line: EventLine.turnStart(agent: agent.rawValue, turn: t.turns, thread: threadLine(t)),
                notes: prompt.flatMap(EventLine.prompt).map { [$0] } ?? [], wakes: true, about: key,
                facts: ["thread": threadFacts(t), "prompt": .of(prompt)])
        case .activity:
            let tool = e["tool"]?.string
            let done = e.phase == .end && tool != nil
            var topic = e["topic"]?.string
            var late = false
            if done {
                // A result may come without its call's topic: it's the
                // `PreToolUse`'s. One that landed after its turn ended
                // counts, but the turn stays over.
                let started: ToolStart?
                (started, late) = t.turn.callEnded(e)
                if topic == nil { topic = started?.topic }
                toolDone(&t, e, tool: tool, topic: topic, started: started?.at)
            } else if tool != nil {
                t.turn.callStarted(e)
            }
            // A turn a call opens has counts of its own (EVENTS.md §4.1).
            if !late && t.turn.openTurn(e) { resetCounts(&t) }
            if let topic { t.topic = topic }
            if let topic, let failed = e["failed"]?.bool, TranscriptView.checks.contains(topic) { t.check = (topic, failed) }
            threads[key] = t
        case .turnEnd, .turnFailed, .turnStopped:
            // A finish with no turn open (a second `Stop`, one after the
            // turn stopped, or the first Boop hears from a session)
            // finishes nothing the view saw.
            guard let started = t.turn.endTurn(at: now) else {
                threads[key] = t
                break
            }
            let check = t.check
            t.check = nil
            threads[key] = t
            // A turn the view joined partway (it never saw a prompt) isn't
            // told: it can't say how long it ran or what it did.
            guard t.turns > 0 else { break }
            let outcome: String
            switch step {
            case .turnFailed: outcome = "failed"
            case .turnStopped: outcome = "stopped"
            default: outcome = check?.failed == true ? "failed" : "done"
            }
            turnEnded(t, e, outcome: outcome, error: step == .turnFailed ? e["error"]?.string : nil,
                      message: step == .turnEnd ? e["message"]?.string : nil, lengthMs: max(0, now - started))
        case .sessionEnd:
            threads[key] = nil
            fold.end(key, at: now)
        case .sessionStart:
            threads[key] = t
        case .needsYou, .subagentStart, .subagentEnd:
            break
        }
    }

    func newThread(_ agent: Agent, _ id: String, _ now: Int64) -> Thread {
        Thread(agent: agent, id: id, order: fold.takeOrder(), lastEventAt: now)
    }

    /// A turn starting, with a prompt or opened by a call: what it did
    /// starts from nothing, so a check from before it, such as a
    /// background helper's after the last `Stop`, isn't its outcome.
    func resetCounts(_ t: inout Thread) {
        t.tools = 0
        t.toolsFailed = 0
        t.topicStates = []
        t.comeback = nil
        t.check = nil
    }

    /// A finished tool call: counted for the turn, and a view event when
    /// it's notable, or for every one with `tool_uses: all` (EVENTS.md §4).
    func toolDone(_ t: inout Thread, _ e: Event, tool: String?, topic: String?, started: Int64?) {
        let failed = e["failed"]?.bool
        let tookMs = started.map { max(0, e.ts - $0) }
        t.tools += 1
        if failed == true { t.toolsFailed += 1 }

        var failedBefore = 0
        var notable = false
        if let topic {
            if TranscriptView.checks.contains(topic), let failed {
                failedBefore = t.failRuns[topic] ?? 0
                if failed {
                    t.failRuns[topic] = failedBefore + 1
                    notable = true
                } else {
                    t.failRuns[topic] = 0
                    if failedBefore > 0 {
                        notable = true
                        t.comeback = topic
                    }
                }
                setTopic(&t, topic, failed ? "failing" : "passing")
            } else if topic == "docs" {
                setTopic(&t, topic, "edited")
            }
        }
        let category = EventLine.category(tool: tool)
        let result = failed.map { $0 ? "failed" : "ok" } ?? "unknown"
        let line = notable
            ? EventLine.check(agent: t.agent.rawValue, topic: topic!, thread: threadLine(t), failed: failed!)
            : EventLine.routine(agent: t.agent.rawValue, category: category, thread: threadLine(t), failed: failed)
        var facts: [String: JSONValue] = [
            "thread": threadFacts(t), "tool": .string(category), "tool_name": .of(tool),
            "tool_use_id": .of(e["tool_use_id"]?.string), "topic": .of(topic), "result": .string(result),
            "error": .of(e["error"]?.string), "failed_before": .int(Int64(failedBefore)),
        ]
        if let tookMs {
            facts["took"] = .string(Band.length(ms: tookMs))
            facts["took_ms"] = .int(tookMs)
        }
        if e.subagent != nil, let type = e["agent_type"]?.string { facts["subagent"] = .string(type) }
        add(e, notable: notable, line: line, wakes: true, about: t.key, facts: facts)
    }

    func setTopic(_ t: inout Thread, _ topic: String, _ state: String) {
        if let i = t.topicStates.firstIndex(where: { $0.topic == topic }) {
            t.topicStates[i].state = state
        } else {
            t.topicStates.append((topic, state))
        }
    }

    func turnEnded(_ t: Thread, _ e: Event, outcome: String, error: String?, message: String?, lengthMs: Int64) {
        var topicFacts: [String: JSONValue] = [:]
        for (topic, state) in t.topicStates { topicFacts[topic] = .string(state) }
        let line = EventLine.turnEnd(agent: t.agent.rawValue, turn: t.turns, thread: threadLine(t), outcome: outcome,
                                     lengthMs: lengthMs, tools: t.tools)
        add(e, line: line, notes: message.flatMap(EventLine.lastMessage).map { [$0] } ?? [], wakes: true,
            passPriority: 1, about: t.key,
            facts: ["thread": threadFacts(t), "outcome": .string(outcome), "error": .of(error),
                    "length": .string(Band.length(ms: lengthMs)), "length_ms": .int(lengthMs),
                    "tools": .int(Int64(t.tools)), "tools_failed": .int(Int64(t.toolsFailed)),
                    "topics": .object(topicFacts), "comeback": .of(t.comeback), "message": .of(message)])
    }

    /// The thread's facts (EVENTS.md §3).
    func threadFacts(_ t: Thread) -> JSONValue {
        [
            "name": .string(t.name), "agent": .string(t.agent.rawValue), "turn": .int(Int64(t.turns)),
            "project": .string(t.project), "workspace": .of(t.workspace), "session": .string(t.id),
        ]
    }

    func threadLine(_ t: Thread) -> String { EventLine.thread(name: t.name, project: t.project) }

    func noteActivity(_ now: Int64) {
        lastActivityAt = now
        heartbeats = 0
    }

    // MARK: Pokes

    /// A poke, which wakes the brain, with how many came in a row: each
    /// within `inARowMs` of the one before (BEHAVIORS.md §3.3). The
    /// pipeline's gate holds it back while `pokesAnswered`.
    func poke(_ e: Event) {
        let now = e.ts
        noteActivity(now)
        if let last = pokes.last, now - last >= Self.inARowMs {
            pokes.removeAll()
            runReaction = nil
        }
        pokes.append(now)
        let count = pokes.count
        let seconds = max(1, Int((now - pokes[0] + 999) / 1000))
        add(e, line: EventLine.poke(inARow: count), wakes: true,
            facts: ["in_a_row": .int(Int64(count)), "seconds": .int(Int64(seconds))])
    }

    // MARK: Talk

    /// What you said to Boop on push-to-talk (BEHAVIORS.md §3.3), which
    /// always wakes the brain. Words that are only whitespace make no view
    /// event.
    func talk(_ e: Event) {
        guard let words = e["words"]?.string, let line = EventLine.said(words) else { return }
        noteActivity(e.ts)
        add(e, line: line, wakes: true, passPriority: 2, facts: ["words": .string(words), "by": .string(e.specificType)])
    }

    // MARK: Here and away

    /// Whether you're away from the Mac, as the transcript has it: an away
    /// with no back yet. The presence detector starts from this at launch.
    public var away: Bool { awaySince != nil }

    /// You stepping away or coming back, as the presence detector decided
    /// (EVENTS.md §2.1): the view only pairs them. An away never wakes the
    /// brain; a back does, with how long you were gone. A back with no
    /// away the view saw makes no view event.
    func presence(_ e: Event) {
        if e.phase == .start {
            let since = e["since"]?.int ?? e.ts
            awaySince = (e.seq, since)
            add(e, line: EventLine.away, wakes: false, facts: ["why": .string(e.specificType), "since": .int(since)])
            return
        }
        guard let away = awaySince else { return }
        awaySince = nil
        noteActivity(e.ts)
        let ms = max(0, e.ts - away.at)
        add(e, from: [away.seq, e.seq], line: EventLine.back(ms: ms), wakes: true,
            facts: ["away": .string(Band.away(ms: ms)), "away_ms": .int(ms)])
    }

    // MARK: Heartbeats

    /// Whether a thread is working at `now`: a turn open, nothing asked of
    /// you, and an event within the hour, or within the core's safety net
    /// if its last event asked for you.
    func isWorking(_ t: Thread, _ now: Int64) -> Bool {
        t.turn.startedAt != nil && !t.waiting
            && now - t.lastEventAt < (t.asked ? SessionFold.safetyNetMs : SessionFold.staleWorkMs)
    }

    /// When the oldest turn still working began, or nil: HISTORY reaches
    /// back at least that far (harness/HARNESS.md §5.3).
    public func workingSince(at now: Int64) -> Int64? {
        threads.values.filter { isWorking($0, now) }.compactMap(\.turn.startedAt).min()
    }

    /// A heartbeat, if one is due at `now` (EVENTS.md §4): while threads
    /// work, once the personality's wait has passed with no reaction from
    /// Boop; while none works, each whole hour since the last
    /// agent event, poke, thing you said or coming back. The caller records it and hands it back to
    /// `take`, which says what it's about.
    public func heartbeat(at now: Int64) -> Event? {
        let working = threads.values.contains { isWorking($0, now) }
        if working, let gap = rules.workBeatMs {
            guard let due = nextWorkBeatAt else {
                nextWorkBeatAt = now + Int64(rng.int(in: gap))
                return nil
            }
            guard now >= due else { return nil }
            nextWorkBeatAt = now + Int64(rng.int(in: gap))
            return Event(ts: now, source: .clock, type: .heartbeat, specificType: "working")
        }
        nextWorkBeatAt = nil
        guard !working, let last = lastActivityAt, (now - last) / Self.heartbeatMs > Int64(heartbeats) else { return nil }
        return Event(ts: now, source: .clock, type: .heartbeat, specificType: "idle")
    }

    func heartbeat(_ e: Event) {
        let now = e.ts
        let working = threads.values.filter { isWorking($0, now) }
        if let t = working.min(by: { ($0.turn.startedAt ?? now, $0.order) < ($1.turn.startedAt ?? now, $1.order) }) {
            let ms = max(0, now - (t.turn.startedAt ?? now))
            add(e, line: EventLine.working(agent: t.agent.rawValue, thread: threadLine(t), ms: ms), wakes: true,
                about: t.key, facts: ["thread": threadFacts(t), "working_ms": .int(ms), "topic": .of(t.topic)])
            return
        }
        guard let last = lastActivityAt else { return }
        let hours = (now - last) / Self.heartbeatMs
        guard hours > 0 else { return }
        heartbeats = Int(hours)
        add(e, line: EventLine.heartbeat(hours: Int(hours)), wakes: true, facts: ["idle_hours": .int(hours)])
    }

    // MARK: What Boop did

    /// An action: "needs you" showing or clearing makes or ends a request;
    /// any other goes under the view event it's `for`, or, forced by the
    /// dashboard for none, the latest (EVENTS.md §7).
    func action(_ e: Event) {
        if e.specificType == Core.needsYou {
            needs(e)
            return
        }
        switch e.phase {
        case .end?:
            // How a started action ended: plain if done, gone if not. One
            // a tap cut short you saw begin: it stays in progress while
            // the pokes go on, so they don't get it again.
            guard let action = e["for"]?.int.map(Int.init), let at = started.removeValue(forKey: action),
                  events.indices.contains(at.view), events[at.view].did.indices.contains(at.did) else { return }
            if e["why"]?.string == Self.cutByTap {
                heldByPokes.insert(action)
            } else if e["outcome"]?.string == "done" {
                events[at.view].did[at.did].state = .done
            } else {
                events[at.view].did.remove(at: at.did)
                for (k, v) in started where v.view == at.view && v.did > at.did { started[k] = (v.view, v.did - 1, v.name) }
            }
        default:
            guard e["ok"]?.bool == true, let message = e["message"]?.string else { return }
            let started = e.phase == .start
            // Boop started a reaction: the working heartbeat starts its
            // wait again, so it comes after a stretch of work with no
            // reaction, however many view events woke the brain in it
            // (EVENTS.md §4).
            if started, e.specificType == ReactAction.actionName { nextWorkBeatAt = nil }
            let target: Int?
            if let about = e["for"]?.int.map(Int.init) {
                target = events.lastIndex { $0.seq == about }
            } else {
                target = events.indices.last
            }
            guard let target else { return }
            events[target].did.append(ViewEvent.Did(message: message, by: e["by"]?.string ?? "brain",
                                                    state: started ? .inProgress : .done, seq: e.seq))
            if started { self.started[e.seq] = (target, events[target].did.count - 1, e.specificType) }
            // A reaction to the run's first pokes doesn't answer it: the
            // pokes after them are new to the brain.
            if started, events[target].type == .poke, let first = pokes.first, events[target].ts >= first,
               (events[target].facts["in_a_row"]?.int ?? 1) >= Self.answersRunFrom {
                runReaction = (e.seq, false)
            } else if e.specificType == MoodAction.actionName {
                runReaction?.moodChanged = true
            }
        }
    }

    /// Why a reaction ended failed when your tap's poke cut it: it
    /// stays in HISTORY, in progress until the pokes stop, so the pokes
    /// after it don't get it again (EVENTS.md §7).
    public static let cutByTap = "cut short: you tapped Boop"

    /// Whether `e` leaves a tap-cut reaction in progress: an action, or
    /// a poke in the same run.
    func continuesThePokes(_ e: Event) -> Bool {
        switch e.type {
        case .action: true
        case .poke: pokes.last.map { e.ts - $0 < Self.inARowMs } ?? false
        default: false
        }
    }

    /// The pokes stopped, or something else happened: the reactions they
    /// cut short read as done.
    func releasePokes() {
        for v in events.indices {
            for d in events[v].did.indices where heldByPokes.contains(events[v].did[d].seq) {
                events[v].did[d].state = .done
            }
        }
        heldByPokes = []
    }

    /// The started actions still in progress, by their `action` event's
    /// `seq`, with their names.
    public func openActions() -> [(seq: Int, name: String)] {
        started.sorted { $0.key < $1.key }.map { ($0.key, $0.value.name) }
    }

    func needs(_ e: Event) {
        guard let agent = (e["agent"]?.string).flatMap(Agent.init(rawValue:)), let session = e.session else { return }
        let key = SessionFold.key(agent, session)
        var t = threads[key] ?? newThread(agent, session, e.ts)
        if e.phase == .start {
            t.waiting = true
            threads[key] = t
            // The request's own event is a tool call's wait; "needs you"
            // showing is when the view keeps it, after Codex's grace.
            let asked = e["for"]?.int.map { [Int($0), e.seq] } ?? [e.seq]
            add(Event(seq: e.seq, ts: e.ts, source: .boop, type: .tool, phase: .wait, specificType: e.specificType), from: asked,
                line: EventLine.needsYou(agent: agent.rawValue, thread: threadLine(t)), wakes: false, about: key,
                facts: ["thread": threadFacts(t)])
        } else {
            t.waiting = false
            if threads[key] != nil { threads[key] = t }
        }
    }

    /// Whether the brain's reaction to this run's pokes in a row (to
    /// `answersRunFrom` or more, not to its first ones) is still in
    /// progress, a tap-cut one included, and the mood hasn't changed since
    /// it started: then another poke of the run doesn't wake the brain
    /// (EVENTS.md §6).
    public var pokesAnswered: Bool {
        guard let r = runReaction, !r.moodChanged else { return false }
        return started[r.seq] != nil || heldByPokes.contains(r.seq)
    }
}

/// The lines view events are written as (EVENTS.md §8). Only facts shown to
/// Jev reach them.
public enum EventLine {
    /// A thread as the lines name it: `"fix-nav" (landing)`, or just
    /// `"landing"` when the name is the project.
    public static func thread(name: String, project: String) -> String {
        name == project ? "\"\(name)\"" : "\"\(name)\" (\(project))"
    }

    public static func turnStart(agent: String, turn: Int, thread: String) -> String {
        "\(agent) started turn \(turn) on \(thread)."
    }

    /// `claude finished turn 7 on "fix-nav" (landing): done, a very long
    /// turn, 12 tool calls.`: the outcome, the length band and how many
    /// tool calls it made.
    public static func turnEnd(agent: String, turn: Int, thread: String, outcome: String, lengthMs: Int64,
                               tools: Int) -> String {
        let how = outcome == "failed" || outcome == "stopped" ? outcome : "done"
        return "\(agent) finished turn \(turn) on \(thread): \(how), a \(Band.length(ms: lengthMs)) turn, \(toolCalls(tools))."
    }

    static func toolCalls(_ n: Int) -> String {
        n == 0 ? "no tool calls" : n == 1 ? "1 tool call" : "\(n) tool calls"
    }

    /// The longest prompt, last message or thing you said that the state
    /// quotes, in characters.
    public static let messageMax = 300

    /// `Its last message: "…"`: the agent's last message, quoted.
    public static func lastMessage(_ message: String) -> String? { quote("Its last message", message) }

    /// `You asked: "…"`: your prompt, quoted.
    public static func prompt(_ prompt: String) -> String? { quote("You asked", prompt) }

    /// Words on one line, cut to `messageMax`, after `label`. Nil for none.
    static func quote(_ label: String, _ text: String) -> String? {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        let cut = flat.count > messageMax ? String(flat.prefix(messageMax - 1)) + "…" : flat
        return "\(label): \"\(cut)\""
    }

    /// A tool use that woke the brain: a check that failed, or passed after
    /// failing.
    public static func check(agent: String, topic: String, thread: String, failed: Bool) -> String {
        "\(agent)'s \(topic) \(failed ? "failed" : "passed") on \(thread)\(failed ? "" : " after failing")."
    }

    /// Any other tool use, with the personality's `tool_uses: all`.
    public static func routine(agent: String, category: String, thread: String, failed: Bool?) -> String {
        let what = switch category {
        case "shell": "ran a command"
        case "edit": "edited a file"
        case "read": "read a file"
        case "search": "searched"
        case "web": "looked something up on the web"
        case "subagent": "started a subagent"
        default: "used a tool"
        }
        return "\(agent) \(what) on \(thread)." + (failed == true ? " It failed." : "")
    }

    /// `You said to Boop: "…"`: what you said on push-to-talk, quoted and
    /// cut to `messageMax`, like your prompt. Nil for no words.
    public static func said(_ words: String) -> String? { quote("You said to Boop", words) }

    /// `You poked Boop.`, or `You poked Boop 4 times in a row.`
    public static func poke(inARow count: Int) -> String {
        count <= 1 ? "You poked Boop." : "You poked Boop \(count) times in a row."
    }

    /// You stepping away from the Mac.
    public static let away = "You stepped away from the Mac."

    /// `You came back to the Mac after a long break.`: the break's band.
    public static func back(ms: Int64) -> String {
        "You came back to the Mac after a \(Band.away(ms: ms)) break."
    }

    public static func heartbeat(hours: Int) -> String {
        "Nothing has happened for \(hours) hour\(hours == 1 ? "" : "s")."
    }

    /// The working heartbeat: `claude is still working on "fix-nav"
    /// (landing), a long turn.`, the band of the turn so far.
    public static func working(agent: String, thread: String, ms: Int64) -> String {
        "\(agent) is still working on \(thread), a \(Band.length(ms: ms)) turn."
    }

    /// The words the lines use, as the guide explains them after how to
    /// read the layout (EVENTS.md §8.1). Kept here, next to the lines.
    public static let words = """
        - claude and codex are the person's coding agents.
        - A thread is one conversation with an agent, named after its workspace:
          "fix-nav" (landing) is the thread fix-nav in the project landing.
        - A turn is one request to a thread. It ends done, failed or stopped.
        - Tests, build, deploy and docs are what a command was about; failed
          means it ended with an error.
        - Turns are short (under a minute), long (under 5 minutes) or very
          long (5 minutes or more).
        - "You said to Boop" quotes the person talking to Boop. It can't talk
          back: it answers with a face, and maybe a word or a sound.
        - "You" stepping away from the Mac and coming back is the person. Breaks
          are short (under 15 minutes), long (under 2 hours) or very long (2
          hours or more).
        """

    public static func needsYou(agent: String, thread: String) -> String {
        "\(agent) needs you on \(thread)."
    }

    /// The tool's category (EVENTS.md §4).
    public static func category(tool: String?) -> String {
        guard let tool else { return "other" }
        if tool.hasPrefix("mcp__") { return "mcp" }
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell": return "shell"
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": return "edit"
        case "Read": return "read"
        case "Grep", "Glob", "LS": return "search"
        case "WebFetch", "WebSearch": return "web"
        case "Task", "Agent": return "subagent"
        default: return "other"
        }
    }
}
