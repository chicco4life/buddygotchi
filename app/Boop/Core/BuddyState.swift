import Foundation

// MARK: - Creature

enum CreatureState: String, Encodable, Sendable, Equatable, CaseIterable { case asleep, idle, working, needsYou, done, uhoh }
enum CreatureEffort: String, CaseIterable, Encodable, Sendable, Equatable { case light, hard, grinding }
enum CheerSize: String, Codable, CaseIterable, Sendable, Equatable {
    case hop, cheer, dance
    var intensity: Int { switch self { case .hop: 1; case .cheer: 2; case .dance: 3 } }
}
enum UhohKind: String, Encodable, CaseIterable, Sendable, Equatable { case error }
enum CreatureOverlay: String, Encodable, Sendable, Equatable { case greet, boop }
enum Stakes: String, CaseIterable, Encodable, Sendable, Equatable { case fine, checkIt, careful }

struct CreatureCard: Encodable, Sendable, Equatable {
    var id: String
    var tool: String
    var gloss: String
    var stakes: Stakes
    var index: Int
    var count: Int
    var isApproval: Bool
}

struct Creature: Encodable, Sendable, Equatable {
    var state: CreatureState
    var effort: CreatureEffort?
    var cheer: CheerSize?
    var uhoh: UhohKind?
    var overlay: CreatureOverlay?
    var greetLevel: Int?
    var dots: Int
    var dotAlert: Int?
    var card: CreatureCard?
    var bubble: String?
    var focus: Bool
    var nudgeRung: Int

    static let initial = Creature(state: .asleep, dots: 0, focus: false, nudgeRung: 0)

    var statusLabel: String {
        let parameter = cheer?.rawValue ?? effort?.rawValue ?? uhoh?.rawValue
        return state.rawValue + (parameter.map { " · \($0)" } ?? "")
    }
}

/// Legacy diagnostic and desktop vocabulary is a rendering projection.
func legacyPetState(from creature: Creature, includingOverlay: Bool = true) -> PetState {
    if includingOverlay, creature.overlay != nil, [.idle, .working, .done].contains(creature.state) { return .heart }
    switch creature.state {
    case .asleep: return .sleep
    case .idle: return .idle
    case .working: return .busy
    case .needsYou: return .attention
    case .done: return .celebrate
    case .uhoh: return .error
    }
}

// MARK: - Pet State

enum PetState: String, Encodable, Sendable, Equatable, CaseIterable {
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

enum DesktopStatus: String, Encodable, Sendable, Equatable {
    case disconnected
    case connected
}

struct DesktopLink: Encodable, Sendable, Equatable {
    var status: DesktopStatus
    var lastHeartbeatAt: Double?
}

// MARK: - Sessions

enum SessionState: String, Encodable, Sendable, Equatable {
    case working
    case idle
    case needsConfirmation
    case errored
    case thinking
}

struct Session: Encodable, Sendable, Equatable {
    /// What this session last finished with, so the per-session breakdown can
    /// show its own cheer even after another session completes.
    var lastDone: DoneRecord?
    var project: String = "unknown"
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
    var uhoh: UhohKind?
    var lastGoal: String?
}

struct SessionCounts: Encodable, Sendable, Equatable {
    var total: Int
    var running: Int
    var waiting: Int

    static let zero = SessionCounts(total: 0, running: 0, waiting: 0)
}

// MARK: - Prompt

struct Prompt: Encodable, Sendable, Equatable {
    var stakes: Stakes?
    var gloss: String?
    var id: String
    var tool: String
    var hint: String
    var arrivedAt: Double
    var sessionLabel: String?
    var source: String?
    var isApproval: Bool = false
    var activityKind: ActivityKind = .work
}

enum ApprovalDecision: String, Encodable, Sendable {
    case allow
    case deny
    case passthrough
}

// MARK: - Completed Task

struct CompletedTask: Encodable, Sendable, Equatable {
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

struct ErroredSession: Encodable, Sendable, Equatable {
    var id: String
    var source: String
    var sessionLabel: String?
    var tool: String?
    var hint: String?
    var workStartedAt: Double?
}

struct DoneRecord: Encodable, Sendable, Equatable {
    var size: CheerSize
    var until: Double
}

// MARK: - Active Sessions (per-session breakdown for popover)

struct SessionSnapshot: Encodable, Sendable, Equatable, Identifiable {
    var cheer: CheerSize?
    var effort: CreatureEffort?
    var id: String
    var source: String
    var state: SessionState
    var sessionLabel: String?
    var currentTool: String?
}

// MARK: - Pet

struct Pet: Encodable, Sendable, Equatable {
    var state: PetState
    var species: String

    static let defaultSpecies = "blob"
    static let initial = Pet(state: .sleep, species: defaultSpecies)
}

// MARK: - BuddyState

struct BuddyState: Encodable, Sendable, Equatable {
    var language = "en"
    var growth = GrowthSnapshot()
    var cosmetic = EquippedCosmetic()
    var version: Int
    var updatedAt: Double

    var desktop: DesktopLink
    var sessions: SessionCounts

    var msg: String
    var entries: [String]

    var prompt: Prompt?
    var devicePosture: DevicePosture?
    var deviceBattery: DeviceBattery?
    var creature: Creature = .initial
    var species = Pet.defaultSpecies
    var pet: Pet { Pet(state: legacyPetState(from: creature), species: species) }
    var lastSignal: String? {
        creature.state == .asleep ? nil : legacyPetState(from: creature, includingOverlay: false).rawValue
    }
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
    /// How hard the current work looks (busy state only).
    var effortTier: EffortTier?
    /// 1..3, struggle-proportional celebration size. Rides with celebrateUntil.
    var celebrateIntensity: Int? { creature.cheer?.intensity }

    static let initial = BuddyState(
        version: 0,
        updatedAt: 0,
        desktop: DesktopLink(status: .disconnected, lastHeartbeatAt: nil),
        sessions: .zero,
        msg: "",
        entries: [],
        prompt: nil,
        creature: .initial,
        celebrateUntil: nil,
        affectionUntil: nil,
        lastTaskDurationMs: nil,
        lastCompletionAt: nil,
        lastCompleted: nil,
        firstErrored: nil,
        activeSessions: [],
        currentActivityKind: nil,
        greetUntil: nil,
        greetLevel: nil,
        effortTier: nil
    )
}
