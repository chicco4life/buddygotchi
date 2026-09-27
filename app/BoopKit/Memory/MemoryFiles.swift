import Foundation

public struct MemoryParseError: Error, Equatable, CustomStringConvertible {
    public var description: String
    init(_ description: String) { self.description = description }
}

/// `long-term.md`: who this Boop is (ARCHITECTURE.md §4.2).
public struct LongTerm: Equatable, Sendable {
    public enum Nature: String, Sendable { case sweet, cheeky }

    public var name: String
    public var hatched: String
    public var nature: Nature
    /// Picks the voice dialect. Written as hex.
    public var seed: UInt64

    public init(name: String, hatched: String, nature: Nature, seed: UInt64) {
        self.name = name
        self.hatched = hatched
        self.nature = nature
        self.seed = seed
    }

    public var markdown: String {
        "## Boop\nname: \(name) · hatched: \(hatched) · nature: \(nature.rawValue) · seed: \(String(seed, radix: 16))\n"
    }

    /// Reads the file. Hand edits are fine as long as the Boop line still
    /// reads. Other sections, like the ones files from before 2026-09-27
    /// have, are left out and left alone.
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
        return LongTerm(name: name, hatched: hatched, nature: nature, seed: seed)
    }
}

/// `short-term.md`: today (ARCHITECTURE.md §4.3).
public struct ShortTerm: Equatable, Sendable {
    public var date: String
    public var firstSeen: String

    public init(date: String, firstSeen: String) {
        self.date = date
        self.firstSeen = firstSeen
    }

    public var markdown: String { "## Today\n\(date) · first seen \(firstSeen)\n" }

    /// Reads the file. Anything else on the Today line, like the `mood:`
    /// files from before 2026-09-26 have, and other sections, like the
    /// Notes and Happened of files from before 2026-09-27, are left out.
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
        for part in parts.dropFirst() where part.hasPrefix("first seen ") {
            firstSeen = String(part.dropFirst("first seen ".count))
        }
        return ShortTerm(date: date, firstSeen: firstSeen)
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
