import Foundation

// MARK: - Pet State

enum PetState: String, Sendable, Equatable {
    case sleep
    case idle
    case busy
    case attention
    case celebrate
    case error
    case thinking

    var sfSymbol: String {
        switch self {
        case .sleep: "moon.zzz"
        case .idle: "circle"
        case .busy: "ellipsis.circle"
        case .attention: "exclamationmark.circle.fill"
        case .celebrate: "sparkles"
        case .error: "exclamationmark.triangle.fill"
        case .thinking: "brain"
        }
    }
}

// MARK: - Desktop

enum DesktopStatus: String, Sendable, Equatable {
    case disconnected
    case connected
}

struct DesktopLink: Sendable, Equatable {
    var status: DesktopStatus
    var lastHeartbeatAt: Double?
}

// MARK: - Sessions

enum SessionState: String, Sendable, Equatable {
    case working
    case idle
    case needsConfirmation
    case errored
    case thinking
}

struct Session: Sendable, Equatable {
    var source: String
    var state: SessionState
    var prompt: Prompt?
    var cwd: String?
    var lastActivityAt: Double
    var workStartedAt: Double?
    var lastWorkSignalAt: Double?
    var lastTool: String?
    var lastHint: String?
    var currentTool: String?
    var currentHint: String?
    var currentActivityKind: ActivityKind?
}

struct SessionCounts: Sendable, Equatable {
    var total: Int
    var running: Int
    var waiting: Int

    static let zero = SessionCounts(total: 0, running: 0, waiting: 0)
}

// MARK: - Prompt

struct Prompt: Sendable, Equatable {
    var id: String
    var tool: String
    var hint: String
    var arrivedAt: Double
    var sessionLabel: String?
    var source: String?
    var isApproval: Bool = false
    var activityKind: ActivityKind = .work
}

enum ApprovalDecision: String, Sendable {
    case allow
    case deny
    case passthrough
}

// MARK: - Completed Task

struct CompletedTask: Sendable, Equatable {
    var id: String
    var tool: String?
    var hint: String?
    var source: String?
    var sessionLabel: String?
    var durationMs: Double?
    var completedAt: Double
    var activityKind: ActivityKind = .work
}

// MARK: - Errored Session

struct ErroredSession: Sendable, Equatable {
    var id: String
    var source: String
    var sessionLabel: String?
    var tool: String?
    var hint: String?
    var workStartedAt: Double?
}

// MARK: - Thinking Session

/// A session that has been actively working but went silent past the work-stall
/// threshold. Distinct from .errored: this is presumed-still-alive ("thinking
/// hard"), not failed; no Dismiss button, no alert sound.
struct ThinkingSession: Sendable, Equatable {
    var id: String
    var source: String
    var sessionLabel: String?
    var tool: String?
    var hint: String?
    var workStartedAt: Double?
    var lastWorkSignalAt: Double?
}

// MARK: - Active Sessions (per-session breakdown for popover)

struct SessionSnapshot: Sendable, Equatable, Identifiable {
    var id: String
    var source: String
    var state: SessionState
    var sessionLabel: String?
    var currentTool: String?
}

// MARK: - Pet

struct Pet: Sendable, Equatable {
    var state: PetState
    var species: String

    static let defaultSpecies = "cat"
    static let initial = Pet(state: .sleep, species: defaultSpecies)
}

// MARK: - BuddyState

struct BuddyState: Sendable, Equatable {
    var version: Int
    var updatedAt: Double

    var desktop: DesktopLink
    var sessions: SessionCounts

    var msg: String
    var entries: [String]

    var prompt: Prompt?
    var pet: Pet
    var lastSignal: String?
    var celebrateUntil: Double?
    var lastTaskDurationMs: Double?
    var lastCompleted: CompletedTask?
    var firstErrored: ErroredSession?
    var firstThinking: ThinkingSession?
    var activeSessions: [SessionSnapshot]
    var currentActivityKind: ActivityKind?

    static let initial = BuddyState(
        version: 0,
        updatedAt: 0,
        desktop: DesktopLink(status: .disconnected, lastHeartbeatAt: nil),
        sessions: .zero,
        msg: "",
        entries: [],
        prompt: nil,
        pet: .initial,
        lastSignal: nil,
        celebrateUntil: nil,
        lastTaskDurationMs: nil,
        lastCompleted: nil,
        firstErrored: nil,
        firstThinking: nil,
        activeSessions: [],
        currentActivityKind: nil
    )
}
