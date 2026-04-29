import Foundation

// MARK: - Activity Signals

enum ActivitySignalKind: String, Sendable, Equatable {
    case startWorking = "start_working"
    case keepWorking = "keep_working"
    case stopWorking = "stop_working"
    case celebrate = "celebrate"
}

// MARK: - Events

enum BuddyEvent: Sendable {
    case sessionStarted(at: Double, sessionId: String, source: String, cwd: String?)
    case sessionEnded(at: Double, sessionId: String)

    case requestArrived(at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?)
    case requestCleared(at: Double, sessionId: String)

    case activitySignal(at: Double, sessionId: String, source: String, signal: ActivitySignalKind)
    case staleTick(at: Double)

    case approvalArrived(at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?)
    case approvalResolved(at: Double, sessionId: String, requestId: String, decision: ApprovalDecision)

    var at: Double {
        switch self {
        case .sessionStarted(let at, _, _, _),
             .sessionEnded(let at, _),
             .requestArrived(let at, _, _, _, _, _),
             .requestCleared(let at, _),
             .activitySignal(let at, _, _, _),
             .staleTick(let at),
             .approvalArrived(let at, _, _, _, _, _, _),
             .approvalResolved(let at, _, _, _):
            return at
        }
    }

    var name: String {
        switch self {
        case .sessionStarted: "sessionStarted"
        case .sessionEnded: "sessionEnded"
        case .requestArrived: "requestArrived"
        case .requestCleared: "requestCleared"
        case .activitySignal(_, _, _, let signal): "activitySignal(\(signal.rawValue))"
        case .staleTick: "staleTick"
        case .approvalArrived: "approvalArrived"
        case .approvalResolved(_, _, _, let decision): "approvalResolved(\(decision.rawValue))"
        }
    }
}
