import Foundation

/// The two brain settings (HARNESS.md §6): the classifier, `rules` (the
/// default) or `jev`, and the writer, `apple` (the default), `none` or
/// `deepseek`. Jev needs the person's API key, asked for only when it's
/// chosen; without one Boop classifies with the rules. Apple's model falls
/// back to no writer when it can't run at launch.
public enum Brains {
    /// Overrides the Keychain's Jev key, for `boopdev brain` and headless runs.
    public static let jevKeyVariable = "BOOP_JEV_KEY"

    public static func classifier(_ setting: String, key: () -> String? = { nil },
                                  log: (String) -> Void = { _ in }) -> any Classifier {
        guard setting == "jev" else { return RulesClassifier() }
        guard let key = key(), !key.isEmpty else {
            log("brain: Jev needs an API key; classifying with the rules")
            return RulesClassifier()
        }
        return JevClassifier(key: key)
    }

    public static func writer(_ setting: String, log: (String) -> Void = { _ in }) -> any Writer {
        switch setting {
        case "none": return NoWriter()
        case "deepseek": return DeepSeekWriter()
        default:
            if let why = AppleWriter.unavailableReason {
                log("brain: Apple's model can't run (\(why)); writing nothing")
                return NoWriter()
            }
            return AppleWriter()
        }
    }

    /// Jev's key from `BOOP_JEV_KEY`, else the Keychain.
    public static func jevKey() -> String? {
        ProcessInfo.processInfo.environment[jevKeyVariable].flatMap { $0.isEmpty ? nil : $0 } ?? Keychain.key(.jev)
    }
}
