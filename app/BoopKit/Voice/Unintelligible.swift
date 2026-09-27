import Foundation

/// Keeps the gibberish from saying anything (VOICE.md §7). A line fails if a
/// gibberish word, or the whole line without hyphens and spaces, is an
/// English word of three or more letters, a rude or sensitive word, or a
/// Minion word. Rude and Minion words of four or more letters also fail
/// anywhere inside the line.
///
/// A doubled syllable (`po-po`, `ki-ki`) is the Minion bounce, and the word
/// list is full of obscure doubles (`kiki`, `pipi`, `pala`), so doubles skip
/// the word list. Doubles people hear as words (`mama`, `papa`) still fail.
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
        // Nursery words for what comes out of you, in several languages.
        "kaka", "pipi", "pepe", "pupu", "caca",
    ]

    /// Minion words and catchphrases, which belong to the films.
    static let minion: Set<String> = [
        "banana", "bananonina", "bello", "belo", "poopaye", "papoy", "papoi", "tulaliloo", "tulalilu", "gelato",
        "kampai", "kanpai", "bapple", "bapples", "labodaa", "laboda", "bedo", "beedo", "bido", "baboi", "tankyu",
        "tatata", "bibo", "bananaaa",
    ]

    /// Doubled syllables that read as words.
    static let commonDoubles: Set<String> = [
        "mama", "papa", "dada", "nana", "baba", "tutu", "yoyo", "dodo", "bobo", "gaga", "wawa", "momo", "bebe",
        "dudu", "nono", "tata", "pupu",
    ]

    /// Rude and Minion words of four or more letters, which fail anywhere
    /// inside a line.
    static let anywhere = rude.union(minion).filter { $0.count >= 4 }.sorted()

    /// The word list's words of three or more letters, lowercased, that are
    /// spelled only with the letters of Boop's syllables: no other word can
    /// ever match gibberish, so keeping only these gives the same answers
    /// from about a tenth of the list, and loads faster.
    let words: Set<String>

    public init(dictionary: String = Unintelligible.dictionaryPath) {
        let text = (try? String(contentsOfFile: dictionary, encoding: .utf8)) ?? ""
        var letters = [Bool](repeating: false, count: 128)
        for c in Sounds.all.joined().utf8 { letters[Int(c)] = true }
        var words = Set<String>()
        var word: [UInt8] = []
        for line in text.utf8.split(whereSeparator: { $0 == 0x0A || $0 == 0x0D }) where line.count >= 3 {
            word.removeAll(keepingCapacity: true)
            var spelled = true
            for byte in line {
                let lower = (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
                guard lower < 128, letters[Int(lower)] else {
                    spelled = false
                    break
                }
                word.append(lower)
            }
            if spelled { words.insert(String(decoding: word, as: UTF8.self)) }
        }
        self.words = words
    }

    /// Whether the English word list loaded. Without it only the fixed lists apply.
    public var hasDictionary: Bool { !words.isEmpty }

    /// Why these gibberish words fail, or nil if they pass.
    public func failure(_ groups: [[String]]) -> String? {
        let whole = groups.map { $0.joined() }.joined()
        for group in groups {
            let doubled = group.count == 2 && group[0] == group[1]
            if let why = failure(word: group.joined(), wordList: !doubled) { return why }
        }
        if groups.count > 1, let why = failure(word: whole) { return why }
        for bad in Unintelligible.anywhere where whole.contains(bad) {
            return "contains \"\(bad)\""
        }
        return nil
    }

    func failure(word: String, wordList: Bool = true) -> String? {
        if Unintelligible.minion.contains(word) { return "\"\(word)\" is a Minion word" }
        if Unintelligible.rude.contains(word) { return "\"\(word)\" is rude" }
        if Unintelligible.commonDoubles.contains(word) { return "\"\(word)\" is a word" }
        if wordList && word.count >= 3 && words.contains(word) { return "\"\(word)\" is English" }
        return nil
    }
}
