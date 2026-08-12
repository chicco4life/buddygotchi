import Foundation

// MARK: - Pet State

enum PetState: String, Sendable, Equatable, CaseIterable {
    case sleep
    case idle
    case busy
    case attention
    case celebrate
    case error
    case thinking
    case heart

    var sfSymbol: String {
        switch self {
        case .sleep: "moon.zzz"
        case .idle: "circle"
        case .busy: "ellipsis.circle"
        case .attention: "exclamationmark.circle.fill"
        case .celebrate: "sparkles"
        case .error: "exclamationmark.triangle.fill"
        case .thinking: "brain"
        case .heart: "heart.fill"
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
    /// Errors seen since the last completion — feeds the effort tier and the
    /// payoff-scaled celebration. Cleared on celebrate.
    var errorCount: Int = 0
    /// Agent's own difficulty report (MCP report_effort); beats the heuristic.
    var reportedEffort: EffortTier?
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

    static let defaultSpecies = "blob"
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
    /// Device boop mirror: while set and in the future, calm pet states show
    /// heart-eyes so the desktop blob reacts to physical affection.
    var affectionUntil: Double?
    var lastTaskDurationMs: Double?
    /// When the most recent task finished, as a strictly-increasing marker.
    /// `lastCompleted` can't answer "did something just finish?" — aggregation
    /// nulls it whenever any *other* session is still busy, so on a multi-agent
    /// desk one agent finishing leaves no trace in the projection at all. This
    /// survives that, which is what the completion chirp edges on.
    var lastCompletionAt: Double?
    var lastCompleted: CompletedTask?
    var firstErrored: ErroredSession?
    var firstThinking: ThinkingSession?
    var activeSessions: [SessionSnapshot]
    var currentActivityKind: ActivityKind?

    // MARK: Personality (System P)

    /// While set and in the future, the pet greets a returning user — shown as
    /// heart-eyes over calm states (wire-compatible with existing firmware).
    var greetUntil: Double?
    /// 1 = glad to see you, 2 = the big missed-you (a week or more away).
    var greetLevel: Int?
    /// Circadian flavor: expectant near the usual start hour, surprised at an
    /// hour this user never works.
    var mood: PetMood?
    /// Expiry for the surprised mood; expectant clears by conditions instead.
    var moodUntil: Double?
    /// How hard the current work looks (busy state only).
    var effortTier: EffortTier?
    /// 1..3, struggle-proportional celebration size. Rides with celebrateUntil.
    var celebrateIntensity: Int?

    // MARK: Agent embodiment (System E)

    /// The agent expression currently coloring the pet, if any. Never present
    /// while a prompt is pending (S1).
    var agentOverlay: AgentOverlay?

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
        affectionUntil: nil,
        lastTaskDurationMs: nil,
        lastCompletionAt: nil,
        lastCompleted: nil,
        firstErrored: nil,
        firstThinking: nil,
        activeSessions: [],
        currentActivityKind: nil,
        greetUntil: nil,
        greetLevel: nil,
        mood: nil,
        moodUntil: nil,
        effortTier: nil,
        celebrateIntensity: nil,
        agentOverlay: nil
    )
}
