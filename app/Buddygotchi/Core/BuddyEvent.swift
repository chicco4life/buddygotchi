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

    var at: Double {
        switch self {
        case .sessionStarted(let at, _, _, _),
             .sessionEnded(let at, _),
             .requestArrived(let at, _, _, _, _, _),
             .requestCleared(let at, _),
             .activitySignal(let at, _, _, _),
             .staleTick(let at):
            return at
        }
    }
}
