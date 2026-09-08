import Foundation

// MARK: - Activity Signals

enum ActivitySignalKind: String, Sendable, Equatable {
    case startWorking = "start_working"
    case keepWorking = "keep_working"
    case stopWorking = "stop_working"
    case celebrate = "celebrate"
    case error = "error"
}

enum TurnOutcome: Sendable, Equatable { case completed; case failed(errorClass: String?) }

// MARK: - Events

enum BuddyEvent: Sendable {
    case onboardingCheer(at: Double, line: String)
    case voiceLine(at: Double, kind: VoiceLineKind, text: String)
    case recapReady(at: Double, recap: Recap)
    case languageChanged(at: Double, language: String)
    case leaderboardUpdated(at: Double, snapshot: LeaderboardSnapshot?)
    case growthUpdated(at: Double, growth: GrowthSnapshot, cosmetic: EquippedCosmetic)
    case requestDescribed(at: Double, sessionId: String, stakes: Stakes, gloss: String)
    case effortObserved(at: Double, sessionId: String, level: EffortTier)
    case goalRead(at: Double, sessionId: String, goalKey: String, runner: String, outcome: GoalOutcome, tally: GoalTally)
    case fileEdited(at: Double, sessionId: String, path: String, count: Int)
    case localTurnHour(at: Double, sessionId: String, hour: Int)
    case adapterDegraded(at: Double, source: String)
    case turnStarted(at: Double, sessionId: String, source: String)
    case toolCalled(at: Double, sessionId: String, source: String, tool: String, hint: String, goal: String? = nil)
    case toolResulted(at: Double, sessionId: String, source: String, tool: String, ok: Bool?, durationMs: Double?, goal: String? = nil)
    case turnEnded(at: Double, sessionId: String, source: String, outcome: TurnOutcome)
    case devicePostureChanged(at: Double, posture: DevicePosture)
    case deviceBatteryChanged(at: Double, battery: DeviceBattery)
    case focusToggled(at: Double, on: Bool)
    case collectArrived(at: Double)
    case nudgeDismissed(at: Double)

    case sessionStarted(at: Double, sessionId: String, source: String, cwd: String?, project: String = "unknown")
    case sessionEnded(at: Double, sessionId: String)

    case requestArrived(at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?)
    case requestCleared(at: Double, sessionId: String)

    case activitySignal(at: Double, sessionId: String, source: String, signal: ActivitySignalKind, tool: String?, hint: String?)
    case staleTick(at: Double)

    case approvalArrived(at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?)
    case approvalResolved(at: Double, sessionId: String, requestId: String, decision: ApprovalDecision)
    /// The hook that was blocked on this approval is gone (its HTTP request was
    /// cancelled). Nobody can receive an answer any more, so the card must not
    /// keep asking for one.
    case approvalAbandoned(at: Double, sessionId: String, requestId: String)
    /// Which sessions currently have a live process watcher on their agent
    /// host. Supervised sessions are exempt from the stale-activity reap: the
    /// watcher delivers a definitive `sessionEnded` the moment the process
    /// exits, so silence alone is not evidence of death.
    case processWatchChanged(at: Double, watchedSessionIds: Set<String>)
    case speciesChanged(at: Double, species: String)
    case boopArrived(at: Double)

    case reviewDismissed(at: Double)
    case errorDismissed(at: Double, sessionId: String)

    /// Persisted pet memory arriving from disk at startup. Seeds the reducer's
    /// memory without counting as presence (no greet, no histogram sample).
    case memoryLoaded(at: Double, memory: PetMemory)
    /// An agent's own difficulty self-report via MCP. Overrides the effort
    /// heuristic for its session.
    case effortReported(at: Double, sessionId: String, level: EffortTier)
    /// An agent claimed identity markers for this session (MCP `introduce`).
    case agentIntroduced(at: Double, agentId: String, color: String?, signatureEmote: String?, greeting: String?)
    /// An agent expression (MCP `express`/`say`). The reducer refuses it while
    /// any prompt is pending (S1); caps and enum validation happened at the
    /// MCP layer (S4/S5), rate limiting in the engine (S6).
    case agentExpressed(at: Double, agentId: String, emotion: String, intensity: String, motion: String?, say: String?, delivery: String?)
    /// An agent left a drawing (MCP `draw`). ALWAYS kept as a keepsake; the
    /// held-up display is separate and S1-suppressed — a gift is never lost
    /// to timing, and never shares the screen with a trust decision.
    case agentDrew(at: Double, agentId: String, rows: [String], caption: String?)

    var at: Double {
        switch self {
        case .onboardingCheer(let at, _), .voiceLine(let at, _, _), .recapReady(let at, _), .languageChanged(let at, _),
             .leaderboardUpdated(let at, _),
             .growthUpdated(let at, _, _),
             .requestDescribed(let at, _, _, _), .effortObserved(let at, _, _), .goalRead(let at, _, _, _, _, _), .fileEdited(let at, _, _, _), .localTurnHour(let at, _, _), .adapterDegraded(let at, _),
             .turnStarted(let at, _, _),
             .toolCalled(let at, _, _, _, _, _),
             .toolResulted(let at, _, _, _, _, _, _),
             .turnEnded(let at, _, _, _),
             .devicePostureChanged(let at, _),
             .deviceBatteryChanged(let at, _),
             .focusToggled(let at, _),
             .collectArrived(let at),
             .nudgeDismissed(let at),
             .sessionStarted(let at, _, _, _, _),
             .sessionEnded(let at, _),
             .requestArrived(let at, _, _, _, _, _),
             .requestCleared(let at, _),
             .activitySignal(let at, _, _, _, _, _),
             .staleTick(let at),
             .approvalArrived(let at, _, _, _, _, _, _),
             .approvalResolved(let at, _, _, _),
             .approvalAbandoned(let at, _, _),
             .processWatchChanged(let at, _),
             .speciesChanged(let at, _),
             .boopArrived(let at),
             .reviewDismissed(let at),
             .errorDismissed(let at, _),
             .memoryLoaded(let at, _),
             .effortReported(let at, _, _),
             .agentIntroduced(let at, _, _, _, _),
             .agentExpressed(let at, _, _, _, _, _, _),
             .agentDrew(let at, _, _, _):
            return at
        }
    }

    var name: String {
        switch self {
        case .voiceLine: "voiceLine"
        case .onboardingCheer: "onboardingCheer"
        case .recapReady: "recapReady"
        case .languageChanged: "languageChanged"
        case .leaderboardUpdated: "leaderboardUpdated"
        case .growthUpdated: "growthUpdated"
        case .requestDescribed: "requestDescribed"
        case .effortObserved: "effortObserved"
        case .goalRead: "goalRead"
        case .fileEdited: "fileEdited"
        case .localTurnHour: "localTurnHour"
        case .adapterDegraded: "adapterDegraded"
        case .turnStarted: "turnStarted"
        case .toolCalled: "toolCalled"
        case .toolResulted: "toolResulted"
        case .turnEnded: "turnEnded"
        case .devicePostureChanged: "devicePostureChanged"
        case .deviceBatteryChanged: "deviceBatteryChanged"
        case .focusToggled: "focusToggled"
        case .collectArrived: "collectArrived"
        case .nudgeDismissed: "nudgeDismissed"
        case .sessionStarted: "sessionStarted"
        case .sessionEnded: "sessionEnded"
        case .requestArrived: "requestArrived"
        case .requestCleared: "requestCleared"
        case .activitySignal(_, _, _, let signal, _, _): "activitySignal(\(signal.rawValue))"
        case .staleTick: "staleTick"
        case .approvalArrived: "approvalArrived"
        case .approvalResolved(_, _, _, let decision): "approvalResolved(\(decision.rawValue))"
        case .approvalAbandoned: "approvalAbandoned"
        case .processWatchChanged: "processWatchChanged"
        case .speciesChanged: "speciesChanged"
        case .boopArrived: "boopArrived"
        case .reviewDismissed: "reviewDismissed"
        case .errorDismissed: "errorDismissed"
        case .memoryLoaded: "memoryLoaded"
        case .effortReported(_, _, let level): "effortReported(\(level.rawValue))"
        case .agentIntroduced: "agentIntroduced"
        case .agentExpressed(_, _, let emotion, _, _, _, _): "agentExpressed(\(emotion))"
        case .agentDrew(_, let agentId, _, _): "agentDrew(\(agentId))"
        }
    }
}
