import Foundation

/// One recorded take the board can play (VOICE.md §3): a word, a sound, a
/// phrase or a swear, performed in one of Boop's moods. The list is
/// `Take.all`, which voicegen writes from the voice bank.
public struct Take: Equatable, Sendable {
    /// How a take says its meaning, from the plainest up: Voice steps down
    /// this order when there's no take of the kind asked for.
    public enum Kind: String, CaseIterable, Sendable {
        case sound, word, phrase, swear
    }

    /// The board's id for it, as `say.take` sends it.
    public let id: String
    /// What it says, as the bubble shows it and HISTORY reads it.
    public let text: String
    /// What it means: one of `say.meaning`'s options.
    public let meaning: String
    public let kind: Kind
    /// The mood it was performed in: it only plays in that mood's face.
    public let mood: String
    /// The finish it needs (`success` or `failure`), or nil for any.
    public let finish: String?
    /// How long it plays on the board, in milliseconds.
    public let ms: Int
}
