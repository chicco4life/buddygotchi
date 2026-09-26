import Foundation

/// The text every pass may carry (HARNESS.md §4): the memory the store
/// supplies, and the budgets that keep it inside Apple's 8K context with
/// the transcript's window.
public enum Prompt {
    /// The text of what the memory store supplies for one pass.
    public struct Memory: Equatable, Sendable {
        public var steering: String
        public var longTerm: String
        public var shortTerm: String

        public init(steering: String, longTerm: String, shortTerm: String) {
            self.steering = steering
            self.longTerm = longTerm
            self.shortTerm = shortTerm
        }
    }

    /// Budgets in tokens (HARNESS.md §4).
    public enum Budget {
        public static let steering = 1000
        public static let longTerm = 800
        public static let shortTerm = 600
        /// The input's line and your words (at most 500 characters).
        public static let input = 200
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when it fits.
    public static func overBudget(_ input: Input, _ memory: Memory) -> [String] {
        let parts: [(String, Int, Int)] = [
            ("steering", tokens(stripComment(memory.steering)), Budget.steering),
            ("long-term", tokens(memory.longTerm), Budget.longTerm),
            ("short-term", tokens(memory.shortTerm), Budget.shortTerm),
            ("input", tokens(input.line + (input.words ?? "")), Budget.input),
        ]
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }

    /// `steering.md` without its leading `<!-- … -->` note for maintainers.
    public static func stripComment(_ steering: String) -> String {
        var s = steering.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<!--"), let end = s.range(of: "-->") {
            s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
