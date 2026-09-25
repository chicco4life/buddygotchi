import Foundation

/// The limits on the memory files (ARCHITECTURE.md §4.2–4.3). The byte
/// budgets keep each file within its share of the prompt (HARNESS.md §4), at
/// about four bytes a token.
public enum MemoryLimits {
    public static let temperamentSentences = 5
    public static let temperamentChars = 120
    public static let moments = 20
    public static let momentChars = 80
    public static let aboutYou = 30
    public static let preferences = 15
    public static let factChars = 100
    public static let notes = 10
    public static let noteChars = 80
    public static let happened = 40
    /// About 800 tokens.
    public static let longTermBytes = 3200
    /// About 600 tokens.
    public static let shortTermBytes = 2400
}

public struct MemoryParseError: Error, Equatable, CustomStringConvertible {
    public var description: String
    init(_ description: String) { self.description = description }
}

/// `long-term.md`: who this Boop has become (ARCHITECTURE.md §4.2).
public struct LongTerm: Equatable, Sendable {
    public enum Nature: String, Sendable { case sweet, cheeky }

    public struct Moment: Equatable, Sendable {
        public var date: String
        public var text: String
    }

    public var name: String
    public var hatched: String
    public var nature: Nature
    /// Picks the voice dialect. Written as hex.
    public var seed: UInt64
    public var temperament: [String]
    public var moments: [Moment]
    public var xp: Int
    public var lastFed: String
    public var lost: Int
    public var aboutYou: [String]
    public var preferences: [String]

    public init(name: String, hatched: String, nature: Nature, seed: UInt64, temperament: [String] = [],
                moments: [Moment] = [], growth: Growth? = nil, aboutYou: [String] = [], preferences: [String] = []) {
        self.name = name
        self.hatched = hatched
        self.nature = nature
        self.seed = seed
        self.temperament = temperament
        self.moments = moments
        let growth = growth ?? Growth(hatched: hatched)
        xp = growth.xp
        lastFed = growth.lastFed
        lost = growth.lost
        self.aboutYou = aboutYou
        self.preferences = preferences
    }

    public var growth: Growth {
        get { Growth(xp: xp, hatched: hatched, lastFed: lastFed, lost: lost) }
        set {
            xp = newValue.xp
            lastFed = newValue.lastFed
            lost = newValue.lost
        }
    }

    public var markdown: String {
        var out = "## Boop\n"
        out += "name: \(name) · hatched: \(hatched) · nature: \(nature.rawValue) · seed: \(String(seed, radix: 16))\n"
        out += "\n### Temperament\n"
        out += temperament.map { $0 + "\n" }.joined()
        out += "\n### Moments\n"
        out += moments.map { "- \($0.date): \($0.text)\n" }.joined()
        out += "\n### Growth\n"
        let g = growth
        out += "xp: \(g.xp) · level: \(g.level) · last fed: \(g.lastFed)" + (g.lost > 0 ? " · lost: \(g.lost)" : "") + "\n"
        out += "\n## About you\n"
        out += aboutYou.map { "- \($0)\n" }.joined()
        out += "\n## Preferences\n"
        out += preferences.map { "- \($0)\n" }.joined()
        return out
    }

    /// Reads the file. Hand edits are fine as long as the Boop line and the
    /// Growth line still read; list items may drop their `- `. Anything past a
    /// section's limit is left out.
    public static func parse(_ text: String) throws -> LongTerm {
        let sections = MarkdownSections(text)
        guard let boop = sections["Boop"]?.first(where: { !$0.isEmpty }) else {
            throw MemoryParseError("no Boop line")
        }
        let fields = Fields(boop)
        guard let name = fields["name"], !name.isEmpty, let hatched = fields["hatched"], LocalTime.isDay(hatched),
              let nature = fields["nature"].flatMap(Nature.init(rawValue:)),
              let seed = fields["seed"].flatMap({ UInt64($0, radix: 16) })
        else { throw MemoryParseError("the Boop line doesn't read: \(boop)") }

        guard let growthLine = sections["Growth"]?.first(where: { !$0.isEmpty }) else {
            throw MemoryParseError("no Growth line")
        }
        let g = Fields(growthLine)
        guard let xp = g["xp"].flatMap(Int.init), xp >= 0, let lastFed = g["last fed"], LocalTime.isDay(lastFed)
        else { throw MemoryParseError("the Growth line doesn't read: \(growthLine)") }
        let lost = g["lost"].flatMap(Int.init) ?? 0

        var moments: [Moment] = []
        for line in items(sections["Moments"]) {
            guard let colon = line.firstIndex(of: ":") else { throw MemoryParseError("a moment has no date: \(line)") }
            let date = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard LocalTime.isDay(date) else { throw MemoryParseError("a moment has no date: \(line)") }
            moments.append(Moment(date: date, text: line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
        }
        return LongTerm(
            name: name, hatched: hatched, nature: nature, seed: seed,
            temperament: Array(items(sections["Temperament"]).prefix(MemoryLimits.temperamentSentences)),
            moments: Array(moments.suffix(MemoryLimits.moments)),
            growth: Growth(xp: xp, hatched: hatched, lastFed: lastFed, lost: max(0, lost)),
            aboutYou: Array(items(sections["About you"]).prefix(MemoryLimits.aboutYou)),
            preferences: Array(items(sections["Preferences"]).prefix(MemoryLimits.preferences)))
    }
}

/// `short-term.md`: today (ARCHITECTURE.md §4.3).
public struct ShortTerm: Equatable, Sendable {
    public var date: String
    public var firstSeen: String
    public var mood: String
    public var notes: [String]
    public var happened: [String]

    public init(date: String, firstSeen: String, mood: String, notes: [String] = [], happened: [String] = []) {
        self.date = date
        self.firstSeen = firstSeen
        self.mood = mood
        self.notes = notes
        self.happened = happened
    }

    public var markdown: String {
        var out = "## Today\n\(date) · first seen \(firstSeen) · mood: \(mood)\n"
        out += "\n## Notes\n"
        out += notes.map { "- \($0)\n" }.joined()
        out += "\n## Happened\n"
        out += happened.map { "- \($0)\n" }.joined()
        return out
    }

    public static func parse(_ text: String) throws -> ShortTerm {
        let sections = MarkdownSections(text)
        guard let today = sections["Today"]?.first(where: { !$0.isEmpty }) else {
            throw MemoryParseError("no Today line")
        }
        let parts = today.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let date = parts.first, LocalTime.isDay(date) else {
            throw MemoryParseError("the Today line doesn't read: \(today)")
        }
        var firstSeen = ""
        var mood = ""
        for part in parts.dropFirst() {
            if part.hasPrefix("first seen ") { firstSeen = String(part.dropFirst("first seen ".count)) }
            if part.hasPrefix("mood: ") { mood = String(part.dropFirst("mood: ".count)) }
        }
        return ShortTerm(date: date, firstSeen: firstSeen, mood: mood,
                         notes: Array(items(sections["Notes"]).suffix(MemoryLimits.notes)),
                         happened: Array(items(sections["Happened"]).suffix(MemoryLimits.happened)))
    }
}

/// The non-empty lines of a section, without their `- `.
func items(_ lines: [String]?) -> [String] {
    (lines ?? []).compactMap { line in
        var s = Substring(line)
        if s.hasPrefix("- ") || s.hasPrefix("* ") { s = s.dropFirst(2) }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

/// Lines under each `##` or `###` heading, keyed by the heading's text.
struct MarkdownSections {
    var sections: [String: [String]] = [:]

    init(_ text: String) {
        var current: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                current = title
                if sections[title] == nil { sections[title] = [] }
            } else if let current {
                sections[current, default: []].append(line)
            }
        }
    }

    subscript(_ title: String) -> [String]? { sections[title] }
}

/// `key: value · key: value`.
struct Fields {
    var values: [String: String] = [:]

    init(_ line: String) {
        for part in line.components(separatedBy: "·") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
    }

    subscript(_ key: String) -> String? { values[key] }
}

extension LocalTime {
    /// `yyyy-MM-dd` that names a real day.
    static func isDay(_ s: String) -> Bool {
        guard s.count == 10, let n = ordinal(s) else { return false }
        return fromOrdinal(n) == s
    }
}
