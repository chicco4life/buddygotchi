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
    /// Needs you's takes are in the pack, but Boop never says them
    /// (VOICE.md §7).
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

extension Take {
    /// A take from its line in `Takes.swift`'s table: id, text, part,
    /// meaning, kind, mood, finish (empty for any) and milliseconds, tab
    /// separated. voicegen writes the table, and VoiceTests reads it back
    /// against the pack, so a bad line can't ship.
    init(row: Substring) {
        let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        self.init(id: f[0], text: f[1], part: Part(rawValue: f[2])!, meaning: f[3], kind: Kind(rawValue: f[4])!,
                  mood: f[5], finish: f[6].isEmpty ? nil : f[6], ms: Int(f[7])!)
    }
}
