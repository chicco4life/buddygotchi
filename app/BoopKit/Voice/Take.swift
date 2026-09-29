import Foundation

/// One recorded take the board can play (VOICE.md §3): a word, a sound, a
/// phrase or a swear, performed in one of Boop's moods. The list is
/// `Take.all`, which voicegen writes from the voice bank.
public struct Take: Equatable, Sendable {
    /// How a take says its meaning, from the plainest up: Voice takes the
    /// nearest kind to the one asked for when there's none of it.
    public enum Kind: String, CaseIterable, Sendable {
        case sound, word, phrase, swear
    }

    /// Which of the brain's questions a take answers (DECISIONS.md §3):
    /// how Boop feels (`say.feeling`) or what NOW is about (`say.about`).
    /// Needs you's takes are the rules' only.
    public enum Part: String, CaseIterable, Sendable {
        case feeling, about, attention
    }

    /// The board's id for it, as `say.take` sends it.
    public let id: String
    /// What it says, as the bubble shows it and HISTORY reads it.
    public let text: String
    public let part: Part
    /// Its answer to its part's question, such as `upset` or `tests`.
    public let meaning: String
    public let kind: Kind
    /// The mood it was performed in: it only plays in that mood's face.
    public let mood: String
    /// The finish it needs (`success` or `failure`), or nil for any.
    public let finish: String?
    /// How long it plays on the board, in milliseconds.
    public let ms: Int
}
