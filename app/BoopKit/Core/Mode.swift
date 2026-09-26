import Foundation

/// How much Boop reacts (BEHAVIORS.md §6), chosen in Settings and applied at
/// once. The mode picks the brain (`Brains.classifier(for:)`) and sets the
/// core's own rules below; "needs you" is the same in every mode.
public enum Mode: String, CaseIterable, Sendable {
    /// The most reaction: every turn gets a mumble with a word. Decides with
    /// the chatty if-else table, so the same events always lead to the same
    /// decisions, which also makes it the mode to debug in.
    case chatty
    /// The balance: Jev decides, or the chatty table without Jev's key.
    case normal
    /// Only what you need to know: something needs you, a turn failed, or a
    /// very long one finished. Decides with the calm if-else table.
    case calm

    /// Working chatter comes this often while agents work; nil for none
    /// (BEHAVIORS.md §2, proposed).
    public var chatterMs: ClosedRange<Int>? {
        switch self {
        case .chatty: 45_000...90_000
        case .normal: 120_000...240_000
        case .calm: nil
        }
    }

    /// Whether a finished turn of this length gets the rules' cheer
    /// (BEHAVIORS.md §3.1): every one, but in calm only a very long one
    /// (over a minute, `Input.Length`).
    public func cheers(_ length: Input.Length) -> Bool {
        self != .calm || length == .veryLong
    }
}
