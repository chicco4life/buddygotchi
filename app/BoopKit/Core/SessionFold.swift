import Foundation

/// The bookkeeping about agent sessions that the core and the view both
/// fold from the same events (ARCHITECTURE.md §3.2, ADAPTERS.md §4): what
/// an agent's event means, which sessions ended, so that a hook of theirs
/// landing later is let go, and how long a silent session still counts. The
/// core adds who asks and "needs you" (`Core.Session`), the view what each
/// turn did (`TranscriptView.Thread`); both keep a session's turn as
/// `AgentSession` does.
struct SessionFold {
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

    /// A subagent's start or end, or its own turn-level hook: the
    /// subagent's alone, so it doesn't move the session's turn or clock
    /// (ADAPTERS.md §4).
    static func subagentsOwn(_ e: Event, _ step: Step) -> Bool {
        step == .subagentStart || step == .subagentEnd || (e.subagent != nil && turnLevel.contains(step))
    }

    /// A working session with no events for this long counts as idle.
    static let staleWorkMs: Int64 = 60 * 60 * 1000
    /// A session with no events for this long is forgotten.
    static let forgetMs: Int64 = 24 * 60 * 60 * 1000
    /// "Needs you" clears anyway after this long with no events, and the
    /// session goes idle (ADAPTERS.md §4).
    static let safetyNetMs: Int64 = 10 * 60 * 1000
    /// Claude's idle notice comes after a minute at its prompt, so one
    /// sooner than this after you sent a prompt is from before it.
    static let idleNoticeMinMs: Int64 = 30_000

    /// A session's key: `claude/s1`.
    static func key(_ agent: Agent, _ id: String) -> String { agent.rawValue + "/" + id }

    /// When each session that ended (`session_end`) did, until it starts
    /// again or a day passes: a hook of its that lands later landed late,
    /// and doesn't bring it back (ADAPTERS.md §4).
    var ended: [String: Int64] = [:]
    /// The last session's place in the order they were first seen.
    var lastOrder = 0

    /// The next session's place in the order.
    mutating func takeOrder() -> Int {
        lastOrder += 1
        return lastOrder
    }

    /// Whether `e` counts for the session `key`, which is `known` or not
    /// yet: a session that ended is back only when it starts again, resumed
    /// or with a new prompt. Anything else of its came from before the end
    /// (a Notification as you quit at the prompt, a background subagent's
    /// result, the command Codex's Interrupt aborted).
    mutating func admits(_ e: Event, _ step: Step, key: String, known: Bool) -> Bool {
        guard !known, ended[key] != nil else { return true }
        guard e.subagent == nil, step == .sessionStart || step == .turnStart else { return false }
        ended[key] = nil
        return true
    }

    /// The session `key` ended at `now`.
    mutating func end(_ key: String, at now: Int64) { ended[key] = now }

    /// Lets go of sessions that ended a day or more before `now`.
    mutating func forgetEnds(at now: Int64) {
        ended = ended.filter { now - $0.value < Self.forgetMs }
    }
}

/// A tool call's start, for its result: when, and its topic.
typealias ToolStart = (at: Int64, topic: String?)

/// A session's turn, its clock and its tool calls, as the core and the view
/// both keep them (ADAPTERS.md §4, harness/EVENTS.md §4.1).
protocol AgentSession {
    var lastEventAt: Int64 { get set }
    /// When the turn now open started, and when the last one ended: a
    /// call's result from before the end landed late.
    var turnStartedAt: Int64? { get set }
    var lastTurnEndedAt: Int64? { get set }
    /// When you last sent a prompt (a `turn` start), for a stale idle
    /// notice: a turn a call started (a background subagent's, after the
    /// main agent stopped) had no prompt to race.
    var promptedAt: Int64? { get set }
    /// Each running tool call's start, by `tool_use_id`, and the last
    /// one's, for a result that carries no ID or topic.
    var toolStarts: [String: ToolStart] { get set }
    var lastToolStart: ToolStart? { get set }
}

extension AgentSession {
    /// Claude's idle notice means it has sat at its prompt for a minute,
    /// so one within 30 s of your last prompt is from before it: a new
    /// prompt typed just as the minute ran out (ADAPTERS.md §4).
    func isStaleNotice(_ e: Event, _ step: SessionFold.Step) -> Bool {
        step == .turnStopped && e["notice"] != nil
            && promptedAt.map { e.ts - $0 < SessionFold.idleNoticeMinMs } == true
    }

    /// No event for `forgetMs` before `now`.
    func forgotten(at now: Int64) -> Bool { now - lastEventAt >= SessionFold.forgetMs }

    /// You sent a prompt at `now`: a turn starts.
    mutating func prompted(at now: Int64) {
        turnStartedAt = now
        promptedAt = now
    }

    /// A tool call starting, with its topic, kept for its result.
    mutating func callStarted(_ e: Event, topic: String?) {
        let start = (at: e.ts, topic: topic)
        if let id = e["tool_use_id"]?.string { toolStarts[id] = start }
        lastToolStart = start
    }

    /// A call's result: its call's start, by `tool_use_id` or else the
    /// last one's, and whether it landed late: the call started before the
    /// turn ended or stopped, and none is open (Esc as it finished, or a
    /// subagent's racing the interrupt), so the turn stays over.
    mutating func callEnded(_ e: Event) -> (started: ToolStart?, late: Bool) {
        let started = e["tool_use_id"]?.string.flatMap { toolStarts.removeValue(forKey: $0) } ?? lastToolStart
        let late = turnStartedAt == nil && started.map { s in lastTurnEndedAt.map { s.at <= $0 } == true } == true
        return (started, late)
    }

    /// A call with no turn open opens one at `now`, with no prompt (a
    /// background subagent's after the main agent's `Stop`, say). Whether
    /// it did.
    mutating func openTurn(at now: Int64) -> Bool {
        guard turnStartedAt == nil else { return false }
        turnStartedAt = now
        return true
    }

    /// The turn open ends at `now`: when it started, or nil with none open.
    mutating func endTurn(at now: Int64) -> Int64? {
        guard let started = turnStartedAt else { return nil }
        turnStartedAt = nil
        lastTurnEndedAt = now
        return started
    }
}
