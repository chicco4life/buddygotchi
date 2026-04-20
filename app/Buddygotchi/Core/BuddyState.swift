import Foundation

// MARK: - Pet State

enum PetState: String, Sendable, Equatable {
    case sleep
    case idle
    case busy
    case attention

    var sfSymbol: String {
        switch self {
        case .sleep: "moon.zzz"
        case .idle: "circle"
        case .busy: "ellipsis.circle"
        case .attention: "exclamationmark.circle.fill"
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
}

struct Session: Sendable, Equatable {
    var source: String
    var state: SessionState
    var prompt: Prompt?
    var cwd: String?
    var lastActivityAt: Double
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
}

// MARK: - Pet

struct Pet: Sendable, Equatable {
    var state: PetState
    var species: String

    static let defaultSpecies = "bufo"
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

    static let initial = BuddyState(
        version: 0,
        updatedAt: 0,
        desktop: DesktopLink(status: .disconnected, lastHeartbeatAt: nil),
        sessions: .zero,
        msg: "",
        entries: [],
        prompt: nil,
        pet: .initial,
        lastSignal: nil
    )
}
