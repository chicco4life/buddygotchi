import Foundation

/// One earlier call as a text brain sees it: the user message as it was
/// sent, and the answer as what actually ran, in the answer format.
public struct Exchange: Equatable, Sendable {
    public var user: String
    public var answer: String

    public init(user: String, answer: String) {
        self.user = user
        self.answer = answer
    }
}

/// Boop's recent turns with the brain (HARNESS.md §4): what happened and
/// what ran, typed, whatever the brain. A text brain renders them as the
/// exchanges before the new message, so each request starts with the one
/// before and a provider can cache it. There is no compaction: when the
/// opening changes or the budget is spent, the conversation starts over. Kept in memory only, and touched only on the
/// harness's queue. Shared, like `ToolLimits`, by whoever runs several
/// harnesses as one (`boopdev brain`).
public final class Conversation: @unchecked Sendable {
    /// The whole request, estimated with `Prompt.tokens`, stays under this.
    /// It leaves room in the 8K context for a schema and the answer.
    public static let budget = 5000

    /// At most this many earlier turns; the next call starts over.
    public let maxExchanges: Int

    /// System prompt, memory text and tool definitions: what the first
    /// message was built from. A change starts a new conversation.
    var opening: String?
    public private(set) var turns: [Turn] = []
    /// Bumped at every restart, so an answer to an earlier conversation isn't added.
    private(set) var generation = 0
    public private(set) var restarts = 0

    public init(maxExchanges: Int = 4) {
        self.maxExchanges = maxExchanges
    }

    /// Starts over unless `opening` is what this conversation began with.
    func open(_ opening: String) {
        if opening != self.opening {
            if self.opening != nil { restart() }
            self.opening = opening
        }
    }

    func restart() {
        if !turns.isEmpty { restarts += 1 }
        turns = []
        generation += 1
    }

    func append(_ turn: Turn, generation: Int) {
        guard generation == self.generation else { return }
        turns.append(turn)
    }

    /// The estimated size of a request, tools included.
    static func tokens(_ prompt: Prompt, tools: [ToolDefinition]) -> Int {
        prompt.history.reduce(Prompt.tokens(prompt.system) + Prompt.tokens(prompt.user)
                              + Prompt.tokens(tools.map(\.json).joined(separator: "\n"))) {
            $0 + Prompt.tokens($1.user) + Prompt.tokens($1.answer)
        }
    }
}
