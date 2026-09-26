import Foundation

/// The chatty if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no
/// model, always available. Chatty mode decides with it. Every agent input
/// gets a mumble, and chatty mode's writer is asked again for a word it
/// leaves out:
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | `react(curious)` |
/// | Agent finished, done, a short turn (under 15 s) | `react(happy)` |
/// | Agent finished, done, a long turn (15 s up to a minute) | `react(proud)` |
/// | Agent finished, done, a very long turn (over a minute) | `react(excited)` |
/// | Agent finished, failed | `react(annoyed)`: the sass, one mumble per failure |
/// | Poked again and again | `react(annoyed)`: the grumble |
/// | You said anything | `Phrases`' table; told off, or yelled with nothing else said, `react(sad)` |
///
/// Calls the menu doesn't offer are left out.
public struct ChattyRules: Classifier {
    public let id = "chatty@1"

    public init() {}

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let (calls, rule) = ChattyRules.decide(context.input)
        return Classification(calls: calls.filter { menu.definition($0.name) != nil }, evidence: rule)
    }

    /// The calls for an input and the row that matched.
    static func decide(_ input: Input) -> ([ToolCall], String) {
        let react = Phrases.react
        switch input.kind {
        case .agentStarted:
            return ([react("curious")], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([react("annoyed")], "failed") }
            switch input.length ?? .short {
            case .veryLong: return ([react("excited")], "done, a very long turn")
            case .long: return ([react("proud")], "done, a long turn")
            case .short: return ([react("happy")], "done, a short turn")
            }
        case .poked:
            return ([react("annoyed")], "poked again and again")
        case .said:
            return Phrases.reply(to: input, hurtMumbles: true)
        }
    }
}
