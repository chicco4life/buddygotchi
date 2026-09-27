import Foundation

/// The eight feelings a mumble can have (VOICE.md §4). `react` picks its
/// five among them (harness/DECISIONS.md §3).
public enum Feeling: String, CaseIterable, Sendable {
    case happy, excited, proud, curious, hopeful, annoyed, sad, sleepy

    public var tune: Tune {
        switch self {
        case .happy, .excited: .bounce
        case .proud: .lift
        case .curious, .hopeful: .up
        case .annoyed: .flat
        case .sad, .sleepy: .down
        }
    }
}

public enum Tune: String, Sendable {
    case up, down, bounce, flat, lift
}

/// What Minion speech is made of. Only Voice reads this.
public enum Sounds {
    public static let consonants = ["b", "p", "m", "n", "d", "t", "l", "k", "g"]
    public static let vowels = ["a", "e", "i", "o", "u"]

    /// The full set, 64 syllables, fixed in the firmware (VOICE.md §3):
    /// consonant + vowel, a few `y`/`w` glides, bare vowels for gasps, a few
    /// closed syllables that aren't English words, and two hums.
    public static let all: [String] =
        consonants.flatMap { c in vowels.map { c + $0 } }
        + ["ya", "yo", "yu", "wa", "we", "wo"]
        + vowels
        + ["pum", "lon", "kun", "tem", "gom", "lun"]
        + hums
    public static let hums = ["mm", "nn"]
    /// Every syllable in `all`, for quick checks.
    static let set = Set(all)

    /// The real words Boop can say (VOICE.md §6). `react`'s words are some
    /// of them (harness/DECISIONS.md §3). Topic words first, then
    /// interjections.
    public static let vocabulary: [String] = [
        "tests", "build", "docs", "deploy", "bug", "fix", "ship", "code", "merge", "review",
        "yay", "oops", "hmm", "finally", "done", "food", "sleepy", "hi", "bye", "love",
        "wow", "yes", "no", "nope", "okay", "again", "nice", "ugh", "boo", "whee",
        "hooray", "thanks", "hello", "more", "snack", "nap", "play", "good", "oh", "what",
    ]
    static let vocabularySet = Set(vocabulary)

    /// The line played when every try came out sounding like a real word.
    static let safeHum = [["mm", "nn"]]

    static func vowel(_ s: String) -> Character? { s.last(where: { "aeiou".contains($0) }) }
    static func consonant(_ s: String) -> Character? { s.first.flatMap { "aeiou".contains($0) ? nil : $0 } }
    static func isClosed(_ s: String) -> Bool { s.count == 3 }
    static func isBare(_ s: String) -> Bool { s.count == 1 }
}
