import Foundation

/// What the agents are doing, sustained, which the working look shows
/// instead of plain working (BEHAVIORS.md §2, PROTOCOL.md §3 `act`), in
/// priority order: the first is the highest.
public enum Act: String, CaseIterable, Sendable {
    case testing, delegating, terminal, searching, analyzing, toolUse = "tool_use", waiting, planning

    /// Its place in the priority: lower is higher.
    public var rank: Int { Act.allCases.firstIndex(of: self)! }

    /// Whether it outranks `other`.
    public func beats(_ other: Act) -> Bool { rank < other.rank }

    /// The tools that plan: Claude's `TodoWrite` and `ExitPlanMode`, and
    /// Codex's `update_plan`, if its hooks ever report it.
    static let planningTools: Set<String> = ["TodoWrite", "ExitPlanMode", "update_plan"]

    /// What a running call shows, by its tool and topic (BEHAVIORS.md §2):
    /// a call that runs tests is testing, a shell command that only looks
    /// (`inspect`) is analyzing, and otherwise its category decides
    /// (harness/EVENTS.md §4.1). A `Task` or `Agent` call is delegating only
    /// from the main agent. Anything else is `tool_use`.
    static func of(tool: String?, topic: String?, byMainAgent: Bool) -> Act {
        if topic == "tests" { return .testing }
        if topic == "inspect" { return .analyzing }
        if let tool, planningTools.contains(tool) { return .planning }
        switch EventLine.category(tool: tool) {
        case "shell": return .terminal
        case "read", "search": return .analyzing
        case "web": return .searching
        case "subagent": return byMainAgent ? .delegating : .toolUse
        default: return .toolUse
        }
    }
}

extension Core {
    /// A tool call running, for the look (BEHAVIORS.md §2).
    struct Call {
        let act: Act
        /// The order calls started in, for a result that names no call.
        let order: Int
        /// `""` for the main agent, else the subagent's `agent_id`.
        let by: String
        /// The tool, which a request names.
        let tool: String
        /// A `Task` or `Agent` call during which a helper was seen starting:
        /// that helper's `SubagentStop` is its return, not this call's end.
        var sawHelper = false
    }

    /// An activity and its time: for a session's, when its evidence was
    /// last in force; for the working look's, since when it has shown. A
    /// higher one replaces it at once, a lower one or none only
    /// `actHoldMs` after that time (BEHAVIORS.md §2).
    struct Timed: Equatable {
        var act: Act
        var at: Int64
    }

    /// An activity shows at least this long: after its last evidence in a
    /// session, and after it started showing, before a lower one or none
    /// replaces it, so fast tools don't flicker (BEHAVIORS.md §2).
    public static let actHoldMs: Int64 = 1500
    /// A call running with nothing heard from its session for this long
    /// shows as waiting (BEHAVIORS.md §2).
    public static let waitingMs: Int64 = 20_000

    /// A session's activity at `now`, before any hold: Codex's request in
    /// its grace is waiting; else the highest of its calls' (each waiting
    /// once the session has been quiet `waitingMs`, but a helper at work),
    /// delegating while a helper it saw start hasn't ended, and planning in
    /// plan mode.
    static func activity(_ s: Session, _ now: Int64) -> Act? {
        if s.pendingSince != nil { return .waiting }
        let quiet = now - s.lastEventAt >= waitingMs
        var acts = s.calls.values.map { quiet && $0.act != .delegating ? Act.waiting : $0.act }
        if !s.helpers.isEmpty { acts.append(.delegating) }
        if s.planMode { acts.append(.planning) }
        return acts.min { $0.beats($1) }
    }

    /// The activity after `held`, with `next` put forward: a higher one at
    /// once, a lower one or none once `actHoldMs` have passed since
    /// `held`'s time. The same one stays, its time moved to `now` when
    /// `refresh` (a session's evidence in force again) and kept when not
    /// (the look's, which has shown since then).
    static func settle(_ held: Timed?, _ next: Act?, now: Int64, refresh: Bool) -> Timed? {
        guard let held else { return next.map { Timed(act: $0, at: now) } }
        if next == held.act { return refresh ? Timed(act: held.act, at: now) : held }
        if let next, next.beats(held.act) { return Timed(act: next, at: now) }
        if now - held.at < actHoldMs { return held }
        return next.map { Timed(act: $0, at: now) }
    }

    /// Every working session's activity held at `now`, then the one the
    /// working look shows: the held activity of the working session with
    /// the most recent event, among those that have one (BEHAVIORS.md §2).
    /// A session that isn't working holds none, so it comes back from
    /// "needs you" or idle with what it does then; with no session working
    /// the look has none at once.
    func updateActs(_ now: Int64) {
        var working: [Session] = []
        for (key, s) in sessions {
            let shows = s.needsSince == nil && isWorking(s, now)
            sessions[key]!.held = shows ? Core.settle(s.held, Core.activity(s, now), now: now, refresh: true) : nil
            if shows { working.append(sessions[key]!) }
        }
        guard !working.isEmpty else {
            shownAct = nil
            return
        }
        let latest = working.filter { $0.held != nil }.max { ($0.lastEventAt, $0.order) < ($1.lastEventAt, $1.order) }
        shownAct = Core.settle(shownAct, latest?.held?.act, now: now, refresh: false)
    }

    /// A call starting: what it shows, from the main agent or a subagent.
    func startCall(_ s: inout Session, _ event: Event, tool: String) {
        let by = event.subagent ?? ""
        callOrder += 1
        let key = event["tool_use_id"]?.string ?? "#\(callOrder)"
        s.calls[key] = Call(act: Act.of(tool: tool, topic: event["topic"]?.string, byMainAgent: by.isEmpty),
                            order: callOrder, by: by, tool: tool)
    }

    /// A call's result: the call it ends, by `tool_use_id`, else the last
    /// one started without one, of the same tool by the same agent if
    /// there's one. The activity it showed holds from now.
    func endCall(_ s: inout Session, _ event: Event, _ now: Int64) -> Call? {
        let key: String?
        if let id = event["tool_use_id"]?.string {
            key = s.calls[id] != nil ? id : nil
        } else {
            let by = event.subagent ?? "", tool = event["tool"]?.string
            let unnamed = s.calls.filter { $0.key.hasPrefix("#") }
            let same = unnamed.filter { $0.value.by == by && $0.value.tool == tool }
            key = (same.isEmpty ? unnamed : same).max { $0.value.order < $1.value.order }?.key
        }
        guard let key, let call = s.calls.removeValue(forKey: key) else { return nil }
        if s.held?.act == call.act { s.held?.at = now }
        return call
    }

    /// Requests answered by something other than their call's result: the
    /// agent moved on, so you denied the call, which sends no hook
    /// (ADAPTERS.md §4). Each asker's latest call of the tool it asked for
    /// never runs, so it shows nothing more. `before` is who asked, and for
    /// which tool, before `event`.
    func denied(_ s: inout Session, before: [String: String], _ event: Event) {
        for (asker, tool) in before where !tool.isEmpty && s.askers[asker] == nil {
            let result = event.type == .tool && event.phase == .end && (event.subagent ?? "") == asker
                && event["tool"]?.string == tool
            guard !result else { continue }
            let latest = s.calls.filter { $0.value.by == asker && $0.value.tool == tool }
                .max { $0.value.order < $1.value.order }
            if let key = latest?.key { s.calls[key] = nil }
        }
    }

    /// A subagent ended: none of its calls runs any more.
    func subagentEnded(_ s: inout Session, _ id: String) {
        s.calls = s.calls.filter { $0.value.by != id }
    }

    /// A helper starting (`SubagentStart`): the main agent is delegating
    /// until it ends, and the `Task` or `Agent` calls running are waiting
    /// on it, so their ends aren't its return.
    func helperStarted(_ s: inout Session, _ id: String) {
        s.helpers.insert(id)
        for (key, call) in s.calls where call.act == .delegating { s.calls[key]?.sawHelper = true }
    }

    /// A turn starting or ending: its calls and helpers are over, and the
    /// session's look starts plain.
    func clearWork(_ s: inout Session) {
        s.calls.removeAll()
        s.helpers.removeAll()
        s.held = nil
    }
}
