import Foundation

/// Keeps the gibberish from saying anything (VOICE.md §7). A line fails if a
/// gibberish word, or the whole line without hyphens and spaces, is an
/// English word of three or more letters, a rude or sensitive word, or a
/// Minion word. Rude and Minion words of four or more letters also fail
/// anywhere inside the line.
public final class Unintelligible: Sendable {
    public static let dictionaryPath = "/usr/share/dict/words"
    public static let shared = Unintelligible()

    /// Rude or sensitive words in the launch languages (English, Korean,
    /// Japanese, romanised Chinese), in forms Boop's sounds could make.
    static let rude: Set<String> = [
        // English, including some the word list leaves out.
        "tit", "tits", "titi", "poo", "poop", "pee", "bum", "dung", "butt", "boob", "boobs", "pube", "wank", "twat",
        "nig", "niga", "nigga", "kike", "paki", "dago", "dyke", "dike", "gook", "coon", "homo", "lame", "dumb",
        "damn", "dammit", "tampon", "penis", "nude",
        // Japanese.
        "baka", "aho", "manko", "unko", "tinko", "tinpo", "tinpoko", "kintama", "boke", "kuso", "yariman",
        // Korean.
        "gaenom", "gae", "byungsin", "byeongsin", "micin", "nom", "nyeon", "bogi", "boji", "jaji", "jot",
        // Chinese.
        "tamade", "nima", "nimade", "wangba", "wangbadan", "niubi", "baichi", "bendan", "sabi", "diao", "gundan",
        "gun", "tama",
    ]

    /// Minion words and catchphrases, which belong to the films.
    static let minion: Set<String> = [
        "banana", "bananonina", "bello", "belo", "poopaye", "papoy", "papoi", "tulaliloo", "tulalilu", "gelato",
        "kampai", "kanpai", "bapple", "bapples", "labodaa", "laboda", "bedo", "beedo", "bido", "baboi", "tankyu",
        "tatata", "bibo", "bananaaa",
    ]

    let words: Set<String>

    public init(dictionary: String = Unintelligible.dictionaryPath) {
        let text = (try? String(contentsOfFile: dictionary, encoding: .utf8)) ?? ""
        var words = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) where line.count >= 3 {
            words.insert(line.lowercased())
        }
        self.words = words
    }

    /// Whether the English word list loaded. Without it only the fixed lists apply.
    public var hasDictionary: Bool { !words.isEmpty }

    /// Why these gibberish words fail, or nil if they pass.
    public func failure(_ groups: [[String]]) -> String? {
        let whole = groups.map { $0.joined() }.joined()
        for candidate in groups.map({ $0.joined() }) + [whole] {
            if let why = failure(word: candidate) { return why }
        }
        for bad in Unintelligible.rude.union(Unintelligible.minion) where bad.count >= 4 && whole.contains(bad) {
            return "contains \"\(bad)\""
        }
        return nil
    }

    func failure(word: String) -> String? {
        if Unintelligible.minion.contains(word) { return "\"\(word)\" is a Minion word" }
        if Unintelligible.rude.contains(word) { return "\"\(word)\" is rude" }
        if word.count >= 3 && words.contains(word) { return "\"\(word)\" is English" }
        return nil
    }
}
