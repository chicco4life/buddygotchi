import Foundation

/// Each mode's brain (HARNESS.md §6). Each mode has an if-else table;
/// normal decides with TypeSafe's Jev instead when it has the person's API
/// key, and with its table for a pass Jev can't answer. Every mode
/// writes with Apple's model, which fails each write while it can't run
/// and recovers by itself when it can; chatty's is asked again for a
/// mumble's word it leaves out. `--classifier` and `--writer` override the
/// mode's choice for one run.
public enum Brains {
    /// Jev's key for `boopdev` and `Boop --headless`, which read nothing
    /// else; in the menu-bar app it wins over the Keychain's.
    public static let jevKeyVariable = "BOOP_JEV_KEY"
    /// What `--classifier` and `--writer` take.
    public static let classifiers = ["chatty", "normal", "calm", "jev"]
    public static let writers = ["apple", "none"]

    /// The mode's classifier, or the override's. Jev's key is asked for only
    /// when Jev is chosen. Normal's Jev has its table behind it; `--classifier
    /// jev` is Jev alone, to check its own decisions.
    public static func classifier(for mode: Mode, override: String? = nil, key: () -> String? = { nil },
                                  log: @escaping @Sendable (String) -> Void = { _ in }) -> any Classifier {
        switch override ?? mode.rawValue {
        case "calm": return Rules(.calm)
        case "normal", "jev":
            guard override != "normal" else { return Rules(.normal) }
            guard let key = key(), !key.isEmpty else {
                log("brain: Jev needs an API key; deciding with the normal rules")
                return Rules(.normal)
            }
            let jev = JevClassifier(key: key)
            return override == "jev" ? jev : FallbackClassifier(jev, else: Rules(.normal), log: log)
        default: return Rules(.chatty)
        }
    }

    /// The mode's writer, or the override's. Apple's writer even when its
    /// model can't run yet (still downloading, or Apple Intelligence off):
    /// it asks before every write, so it starts writing once it can.
    public static func writer(for mode: Mode, override: String? = nil, log: (String) -> Void = { _ in }) -> any Writer {
        if override == "none" { return NoWriter() }
        if let why = AppleWriter.unavailableReason {
            log("brain: Apple's model can't run yet (\(why)); mumbles have no word until it can")
        }
        return AppleWriter(wordRequired: mode == .chatty)
    }

    /// Whether the mode, or the override, decides with Jev when it has a key.
    public static func wantsJevKey(_ mode: Mode, override: String?) -> Bool {
        override == "jev" || override == nil && mode == .normal
    }

    /// Jev's key from `BOOP_JEV_KEY`, else the Keychain. May block on a
    /// Keychain prompt: never call it on the main thread or `home`.
    public static func jevKey() -> String? {
        environmentJevKey() ?? Keychain.key(.jev)
    }

    /// `BOOP_JEV_KEY`, which wins over the Keychain.
    public static func environmentJevKey() -> String? {
        ProcessInfo.processInfo.environment[jevKeyVariable].flatMap { $0.isEmpty ? nil : $0 }
    }
}
