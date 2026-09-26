import Foundation

/// Each mode's brain (HARNESS.md §6). Each mode has an if-else table;
/// normal decides with TypeSafe's Jev instead when it has the person's API
/// key, and with its table for a pass Jev can't answer. Every mode
/// writes with Apple's model, which falls back to no writer when it can't
/// run; chatty's is asked again for a mumble's word it leaves out. `--classifier` and
/// `--writer` override the mode's choice for one run.
public enum Brains {
    /// Overrides the Keychain's Jev key, for `boopdev` and headless runs.
    public static let jevKeyVariable = "BOOP_JEV_KEY"
    /// What `--classifier` and `--writer` take.
    public static let classifiers = ["chatty", "normal", "calm", "jev"]
    public static let writers = ["apple", "none", "deepseek"]

    /// The mode's classifier, or the override's. Jev's key is asked for only
    /// when Jev is chosen. Normal's Jev has its table behind it; `--classifier
    /// jev` is Jev alone, to check its own decisions.
    public static func classifier(for mode: Mode, override: String? = nil, key: () -> String? = { nil },
                                  log: @escaping @Sendable (String) -> Void = { _ in }) -> any Classifier {
        switch override ?? mode.rawValue {
        case "calm": return CalmRules()
        case "normal", "jev":
            guard override != "normal" else { return NormalRules() }
            guard let key = key(), !key.isEmpty else {
                log("brain: Jev needs an API key; deciding with the normal rules")
                return NormalRules()
            }
            let jev = JevClassifier(key: key)
            return override == "jev" ? jev : FallbackClassifier(jev, else: NormalRules(), log: log)
        default: return ChattyRules()
        }
    }

    /// The mode's writer, or the override's.
    public static func writer(for mode: Mode, override: String? = nil, log: (String) -> Void = { _ in }) -> any Writer {
        switch override {
        case "none": return NoWriter()
        case "deepseek": return DeepSeekWriter()
        default:
            if let why = AppleWriter.unavailableReason {
                log("brain: Apple's model can't run (\(why)); writing nothing")
                return NoWriter()
            }
            return AppleWriter(wordRequired: mode == .chatty)
        }
    }

    /// Jev's key from `BOOP_JEV_KEY`, else the Keychain.
    public static func jevKey() -> String? {
        ProcessInfo.processInfo.environment[jevKeyVariable].flatMap { $0.isEmpty ? nil : $0 } ?? Keychain.key(.jev)
    }
}
