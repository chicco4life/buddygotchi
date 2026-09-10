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
    case onboardingCheer(at: Double)
    case voiceLine(at: Double, kind: VoiceLineKind, text: String)
    case languageChanged(at: Double, language: String)
    case growthUpdated(at: Double, growth: GrowthSnapshot, cosmetic: EquippedCosmetic)
    case requestDescribed(at: Double, sessionId: String, stakes: Stakes, gloss: String)
    case adapterDegraded(at: Double, source: String)
    case turnStarted(at: Double, sessionId: String, source: String)
    case toolCalled(at: Double, sessionId: String, source: String, tool: String, hint: String, goal: String? = nil)
    case toolResulted(at: Double, sessionId: String, source: String, tool: String, ok: Bool?, durationMs: Double?, goal: String? = nil)
    case turnEnded(at: Double, sessionId: String, source: String, outcome: TurnOutcome)
    case devicePostureChanged(at: Double, posture: DevicePosture)
    case deviceBatteryChanged(at: Double, battery: DeviceBattery)
    case focusToggled(at: Double, on: Bool)
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

    var at: Double {
        switch self {
        case .onboardingCheer(let at), .voiceLine(let at, _, _), .languageChanged(let at, _),
             .growthUpdated(let at, _, _),
             .requestDescribed(let at, _, _, _), .adapterDegraded(let at, _),
             .turnStarted(let at, _, _),
             .toolCalled(let at, _, _, _, _, _),
             .toolResulted(let at, _, _, _, _, _, _),
             .turnEnded(let at, _, _, _),
             .devicePostureChanged(let at, _),
             .deviceBatteryChanged(let at, _),
             .focusToggled(let at, _),
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
             .memoryLoaded(let at, _):

            return at
        }
    }

    var name: String {
        switch self {
        case .voiceLine: "voiceLine"
        case .onboardingCheer: "onboardingCheer"
        case .languageChanged: "languageChanged"
        case .growthUpdated: "growthUpdated"
        case .requestDescribed: "requestDescribed"
        case .adapterDegraded: "adapterDegraded"
        case .turnStarted: "turnStarted"
        case .toolCalled: "toolCalled"
        case .toolResulted: "toolResulted"
        case .turnEnded: "turnEnded"
        case .devicePostureChanged: "devicePostureChanged"
        case .deviceBatteryChanged: "deviceBatteryChanged"
        case .focusToggled: "focusToggled"
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
        }
    }
}
