import Foundation

/// A cloud language model with the person's own API key. Interface only in
/// v1: it refuses every call.
public struct CloudBrain: TextBrain {
    public let model: String
    public var id: String { "cloud:\(model)" }

    public init(model: String) { self.model = model }

    public func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                         deadline: Duration) async throws -> String {
        throw BrainError("the cloud brain isn't available yet")
    }
}

/// The brain setting (HARNESS.md §7): `apple` (the default), `rules`, `jev`,
/// or `cloud:<model>`. Apple's model falls back to rules when it can't run:
/// for good if it can't at launch, and call by call if it stops later. Jev
/// needs the person's API key, asked for only when it's chosen; it writes
/// with the brain `apple` would give.
public enum Brains {
    /// Overrides the Keychain's key, for `boopdev brain` and headless runs.
    public static let keyVariable = "BOOP_API_KEY"

    public static func make(_ setting: String, key: () -> String? = { nil }, log: (String) -> Void = { _ in }) -> any Brain {
        switch setting {
        case "rules": return RulesBrain()
        case "jev":
            let writer = make("apple", log: log)
            guard let key = key(), !key.isEmpty else {
                log("brain: Jev needs an API key; using \(writer.id)")
                return writer
            }
            return JevBrain(key: key, writer: writer)
        case let s where s.hasPrefix("cloud:"): return CloudBrain(model: String(s.dropFirst("cloud:".count)))
        default:
            if let why = AppleBrain.unavailableReason {
                log("brain: Apple's model can't run (\(why)); using rules")
                return RulesBrain()
            }
            return AppleBrain()
        }
    }

    /// The key from `BOOP_API_KEY`, else the Keychain.
    public static func key() -> String? {
        ProcessInfo.processInfo.environment[keyVariable].flatMap { $0.isEmpty ? nil : $0 } ?? Keychain.apiKey()
    }
}
