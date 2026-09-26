import Foundation

/// A Minion line, ready for a `moment`'s `say` field (PROTOCOL.md §3).
public struct VoiceLine: Equatable, Sendable {
    /// Gibberish words of 1–3 syllables each.
    public var groups: [[String]]
    /// The one real word, if any.
    public var word: String?
    /// Where the word goes, as an index into the syllables: 0 is before the
    /// first, `syllableCount` after the last.
    public var at: Int
    public var tune: Tune
    public var ms: Int

    public var syllableCount: Int { groups.reduce(0) { $0 + $1.count } }
    /// `ma-po li bu-da`: hyphens inside a word, spaces between words.
    public var syl: String { groups.map { $0.joined(separator: "-") }.joined(separator: " ") }
    public var isSafeHum: Bool { groups == Sounds.safeHum }

    /// How it reads, for logs and review: `ma-po li bu-da… tests?`
    public var text: String {
        guard let word else { return syl + "…" }
        let mark = tune == .up ? "?" : "!"
        return at == 0 ? "\(word)! \(syl)…" : "\(syl)… \(word)\(mark)"
    }

    /// The `say` object of a `moment`.
    public var json: String {
        var parts = ["\"syl\":\"\(syl)\""]
        if let word {
            parts.append("\"word\":\"\(word)\"")
            parts.append("\"at\":\(at)")
        }
        parts.append("\"tune\":\"\(tune.rawValue)\"")
        parts.append("\"ms\":\(ms)")
        return "{" + parts.joined(separator: ",") + "}"
    }
}

/// This Boop's favourite syllables, picked once from its seed. Never changes.
public struct Dialect: Equatable, Sendable {
    public static let size = 16
    public let seed: UInt64
    public let favourites: [String]

    public init(seed: UInt64) {
        self.seed = seed
        var rng = SplitMix64(seed: seed ^ 0xD1A1_EC70)
        var pool = Sounds.all.filter { !Sounds.hums.contains($0) }
        var picked: [String] = []
        while picked.count < Dialect.size {
            picked.append(pool.remove(at: rng.int(in: 0...(pool.count - 1))))
        }
        favourites = picked
    }
}

/// Turns a feeling and an optional word into Minion speech (VOICE.md). The
/// only code that knows what it sounds like.
public struct Voice: Sendable {
    /// A failed line is regenerated up to this many times, then hummed.
    public static let retries = 5
    /// A gibberish word that fails is re-rolled up to this many times while
    /// the line is built.
    static let wordRerolls = 4
    /// Percent of syllables drawn from the dialect's favourites.
    static let favouriteShare = 70

    public let dialect: Dialect
    let check: Unintelligible

    public init(dialect: Dialect, check: Unintelligible = .shared) {
        self.dialect = dialect
        self.check = check
    }

    /// Builds a line. The same inputs and `seed` give the same line. A word
    /// outside the vocabulary is left out.
    /// `rejected` sees every try and why it failed, for debugging.
    public func line(_ feeling: Feeling, word: String? = nil, seed: UInt64,
                     rejected: (([[String]], String?) -> Void)? = nil) -> VoiceLine {
        let word = word.flatMap { Sounds.vocabularySet.contains($0) ? $0 : nil }
        let salt = UInt64(Feeling.allCases.firstIndex(of: feeling)! + 1) << 56
        var rng = SplitMix64(seed: (seed ^ salt) ^ dialect.seed &* 0x100_0000_01B3)
        for _ in 0...Voice.retries {
            let groups = gibberish(feeling, rng: &rng)
            let failure = check.failure(groups)
            rejected?(groups, failure)
            if failure == nil {
                return place(groups, word: word, feeling: feeling, rng: &rng)
            }
        }
        var hum = place(Sounds.safeHum, word: word, feeling: feeling, rng: &rng)
        hum.tune = .down
        return hum
    }

    func place(_ groups: [[String]], word: String?, feeling: Feeling, rng: inout SplitMix64) -> VoiceLine {
        let count = groups.reduce(0) { $0 + $1.count }
        // Usually at the end, as a question or exclamation; now and then at
        // the start, as an announcement. Curious always asks.
        let first = word != nil && feeling != .curious && rng.chance(20)
        return VoiceLine(groups: groups, word: word, at: word == nil ? count : (first ? 0 : count),
                         tune: feeling.tune, ms: Voice.tempo(feeling))
    }

    /// Milliseconds per syllable at the neutral pace, before the feeling.
    static let neutralMs = 135

    /// 90–180 ms per syllable: the neutral pace, then by feeling.
    static func tempo(_ feeling: Feeling) -> Int {
        var ms = Voice.neutralMs
        switch feeling {
        case .excited: ms -= 20
        case .happy, .annoyed: ms -= 10
        case .hopeful: ms += 10
        case .sad: ms += 25
        case .sleepy: ms += 35
        case .proud, .curious: break
        }
        return max(90, min(180, ms))
    }

    func gibberish(_ feeling: Feeling, rng: inout SplitMix64) -> [[String]] {
        let total = length(feeling, rng: &rng)
        var groups: [[String]] = []
        var left = total
        while left > 0 {
            let roll = rng.int(in: 0...99)
            let size = min(left, roll < 25 ? 1 : roll < 75 ? 2 : 3)
            left -= size
            // A word that fails the check is re-rolled as it's built; the
            // whole line is still checked afterwards.
            var group = word(feeling, size: size, last: left == 0, rng: &rng)
            for _ in 0..<Voice.wordRerolls where check.failure([group]) != nil {
                group = word(feeling, size: size, last: left == 0, rng: &rng)
            }
            groups.append(group)
        }
        return groups
    }

    /// One gibberish word of `size` syllables. Only doubling repeats a
    /// syllable on purpose.
    func word(_ feeling: Feeling, size: Int, last: Bool, rng: inout SplitMix64) -> [String] {
        let doubling = [.happy, .excited].contains(feeling) ? 40 : 15
        if size == 2 && rng.chance(doubling) {
            let s = pick(feeling, last: last, rng: &rng)
            return [s, s]
        }
        var group: [String] = []
        for i in 0..<size {
            var s = pick(feeling, last: last && i == size - 1, rng: &rng)
            if s == group.last { s = pick(feeling, last: last && i == size - 1, rng: &rng) }
            group.append(s)
        }
        return group
    }

    /// Short (2–4) or long (5–8), from the feeling.
    func length(_ feeling: Feeling, rng: inout SplitMix64) -> Int {
        let long: Int
        switch feeling {
        case .excited: long = 80
        case .proud: long = 50
        case .happy: long = 45
        case .curious, .sad: long = 30
        case .hopeful: long = 25
        case .annoyed: long = 20
        case .sleepy: long = 10
        }
        return rng.chance(long) ? rng.int(in: 5...8) : rng.int(in: 2...4)
    }

    /// One syllable: mostly this Boop's favourites, shaped by the feeling.
    func pick(_ feeling: Feeling, last: Bool, rng: inout SplitMix64) -> String {
        let pool = Voice.pool(feeling, last: last)
        let favourites = dialect.favourites.filter(pool.contains)
        let from = !favourites.isEmpty && rng.chance(Voice.favouriteShare) ? favourites : pool
        return from[rng.int(in: 0...(from.count - 1))]
    }

    /// The syllables a feeling uses (VOICE.md §4). Never empty.
    static func pool(_ feeling: Feeling, last: Bool) -> [String] {
        func matching(vowels: String = "aeiou", consonants: String? = nil, bare: Bool = false, closed: Bool = true)
            -> [String] {
            Sounds.all.filter { s in
                guard !Sounds.hums.contains(s), let v = Sounds.vowel(s), vowels.contains(v) else { return false }
                if Sounds.isBare(s) { return bare }
                if Sounds.isClosed(s) && !closed { return false }
                guard let consonants else { return true }
                return Sounds.consonant(s).map(consonants.contains) ?? false
            }
        }
        switch feeling {
        case .happy, .excited:
            return matching(vowels: "ai", closed: false)
        case .proud:
            // Open `a` and `o`, with a long last syllable.
            return last ? matching(vowels: "ao", bare: true).filter { Sounds.isClosed($0) || Sounds.isBare($0) }
                : matching(vowels: "ao")
        case .curious:
            return last ? matching(vowels: "ie", closed: false) : matching(closed: false)
        case .hopeful:
            return matching(vowels: "ou", consonants: "mnlywb")
        case .annoyed:
            return matching(consonants: "tkp", closed: false)
        case .sad:
            return last ? ["u", "o"] : matching(vowels: "uo", closed: false)
        case .sleepy:
            return Sounds.hums + matching(vowels: "uo", consonants: "mn")
        }
    }
}
