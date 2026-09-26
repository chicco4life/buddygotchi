import Foundation

/// A brain call as text (HARNESS.md §4), for language models, stable parts
/// first so a provider can cache them: the system prompt, the conversation's
/// earlier exchanges, then this call's user message. Built from the typed
/// situation and menu, the same way every time.
public struct Prompt: Equatable, Sendable {
    public var system: String
    public var history: [Exchange] = []
    public var user: String

    /// Three lines ahead of `steering.md`.
    public static let preamble = """
        You are the brain of a Boop, reacting to one thing that just happened.
        Answer only with tool calls.
        No tool calls means staying quiet, which is often best.
        """

    /// Where the trigger starts in the user part.
    public static let nowMarker = "--- now ---"

    /// Budgets in tokens (HARNESS.md §4).
    public enum Budget {
        public static let system = 1000
        public static let longTerm = 800
        public static let shortTerm = 600
        public static let trigger = 100
        public static let tools = 400
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// The text of what the memory store supplies for one call.
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

    public init(system: String, history: [Exchange] = [], user: String) {
        self.system = system
        self.history = history
        self.user = user
    }

    /// The situation as text, for a language model: the system prompt, each
    /// earlier turn as the message it was sent as and the calls that ran, then
    /// this call's message with the menu's limit lines.
    public init(_ situation: Situation, _ menu: Menu) {
        let s = situation
        let history = s.recent.enumerated().map { i, turn in
            Exchange(user: Prompt.message(turn.trigger, s.memory, limits: turn.limits, opening: i == 0),
                     answer: Answer.json(turn.did))
        }
        self.init(system: Prompt.system(s.memory.steering), history: history,
                  user: Prompt.message(s.trigger, s.memory, limits: menu.limits, opening: s.recent.isEmpty))
    }

    /// One call on its own, with no earlier turns. `limits` are lines like
    /// `say limit: once every 10 min on event, next in 6 min`.
    public init(trigger: Trigger, memory: Memory, limits: [String] = []) {
        self.init(Situation(trigger: trigger, memory: memory), Menu(tools: [], limits: limits))
    }

    /// The memory text opens a conversation, so only its first message
    /// carries it; later ones are just the now section.
    static func message(_ trigger: Trigger, _ memory: Memory, limits: [String], opening: Bool) -> String {
        var now = trigger.line
        if let words = trigger.words { now += "\nthey said: \"\(Prompt.oneLine(words))\"" }
        for line in limits { now += "\n" + line }
        let shortTerm = trigger.kind == .reflect
            ? "Yesterday's short-term memory, to reflect on:\n\n" + memory.shortTerm
            : memory.shortTerm
        let parts = opening ? [memory.longTerm, shortTerm] : []
        return (parts + [Prompt.nowMarker + "\n" + now])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The preamble and `steering.md`.
    public static func system(_ steering: String) -> String {
        preamble + "\n\n" + stripComment(steering)
    }

    /// The part after `--- now ---`: the trigger line and, for `talk`, the words.
    public static func now(in user: String) -> String {
        guard let range = user.range(of: nowMarker + "\n", options: .backwards) else { return "" }
        return String(user[range.upperBound...])
    }

    /// Parts over their budget, as `part: N > budget`; empty when it fits.
    public static func overBudget(_ trigger: Trigger, _ memory: Memory, tools: [ToolDefinition]) -> [String] {
        let parts: [(String, Int, Int)] = [
            ("preamble + steering", tokens(preamble + "\n\n" + stripComment(memory.steering)), Budget.system),
            ("long-term", tokens(memory.longTerm), Budget.longTerm),
            ("short-term", tokens(memory.shortTerm), Budget.shortTerm),
            ("trigger", tokens(trigger.line + (trigger.words ?? "")), Budget.trigger),
            ("tools", tokens(tools.map(\.json).joined(separator: "\n")), Budget.tools),
        ]
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }

    /// `steering.md` without its leading `<!-- … -->` note for maintainers.
    static func stripComment(_ steering: String) -> String {
        var s = steering.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<!--"), let end = s.range(of: "-->") {
            s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "'")
    }
}
