import Foundation

/// The static parts of Jev's state (harness/HARNESS.md §6): the guide, the
/// personalities and the moods, read once from a copy of `plan/steering/`
/// and never written. Comments are left out, and a personality's front
/// matter goes to the core, not to Jev.
public struct Steering: Equatable, Sendable {
    public struct PersonalityFile: Equatable, Sendable {
        public var rules: Personality.Rules
        /// The PERSONALITY section.
        public var text: String
    }

    /// The guide, which opens the state with no heading.
    public var guide: String
    public var personalities: [String: PersonalityFile]
    /// The MOOD section for each mood, by name.
    public var moods: [String: String]

    /// Reads a steering folder: `guide.md`, `personality/*.md` and
    /// `mood/*.md`. Throws if the guide or any personality or mood Boop
    /// knows is missing.
    public init(directory: URL) throws {
        func read(_ path: String) throws -> String {
            do {
                return try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
            } catch {
                throw SteeringError("\(path) is missing from \(directory.path)")
            }
        }
        guide = Steering.clean(try read("guide.md"))
        personalities = [:]
        for p in Personality.allCases {
            let (frontMatter, body) = Steering.frontMatter(try read("personality/\(p.rawValue).md"))
            personalities[p.rawValue] = PersonalityFile(rules: Personality.Rules(frontMatter: frontMatter),
                                                        text: Steering.clean(body))
        }
        moods = [:]
        for mood in MoodAction.moods.map(\.name) {
            moods[mood] = Steering.clean(try read("mood/\(mood).md"))
        }
    }

    public func personality(_ p: Personality) -> PersonalityFile {
        personalities[p.rawValue] ?? PersonalityFile(rules: Personality.Rules(), text: "")
    }

    public func mood(_ name: String) -> String { moods[name] ?? moods[MoodAction.initial] ?? "" }

    /// Splits a leading `---` block from the rest.
    static func frontMatter(_ text: String) -> (String, String) {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex)
        else { return ("", text) }
        return (String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]), String(text[end.upperBound...]))
    }

    /// The text without `<!-- … -->` comments, trimmed.
    static func clean(_ text: String) -> String {
        var s = text
        while let start = s.range(of: "<!--"), let end = s.range(of: "-->", range: start.upperBound..<s.endIndex) {
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Budgets in tokens (HARNESS.md §6.2).
    public enum Budget {
        public static let guide = 300
        public static let personality = 700
        public static let mood = 175
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when all fit.
    public func overBudget() -> [String] {
        var parts = [("guide", Steering.tokens(guide), Budget.guide)]
        for (name, p) in personalities.sorted(by: { $0.key < $1.key }) {
            parts.append(("personality/\(name)", Steering.tokens(p.text), Budget.personality))
        }
        for (name, text) in moods.sorted(by: { $0.key < $1.key }) {
            parts.append(("mood/\(name)", Steering.tokens(text), Budget.mood))
        }
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }
}

public struct SteeringError: Error, CustomStringConvertible {
    public var description: String
    init(_ description: String) { self.description = description }
}
