import Foundation

/// The chatty if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no
/// model, always available. Chatty mode decides with it, and so does normal
/// mode without Jev's key. Every agent input gets a mumble, and chatty
/// mode's writer is asked again for a word it leaves out:
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | `react(curious, mumble)` |
/// | Agent finished, done, a short turn (under 15 s) | `react(happy, mumble)` |
/// | Agent finished, done, a long turn (15 s up to a minute) | `react(proud, mumble)` |
/// | Agent finished, done, a very long turn (over a minute) | `react(excited, mumble)` |
/// | Agent finished, failed | `react(annoyed, mumble)`: the sass, one mumble per failure |
/// | Poked again and again | `react(annoyed, mumble)`: the grumble |
/// | You said anything | `Phrases`' table; yelled at or told off, `react(sad, mumble)` |
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
            return ([react("curious", "mumble")], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([react("annoyed", "mumble")], "failed") }
            switch input.length ?? .short {
            case .veryLong: return ([react("excited", "mumble")], "done, a very long turn")
            case .long: return ([react("proud", "mumble")], "done, a long turn")
            case .short: return ([react("happy", "mumble")], "done, a short turn")
            }
        case .poked:
            return ([react("annoyed", "mumble")], "poked again and again")
        case .said:
            return Phrases.reply(to: input, hurtMumbles: true)
        }
    }
}
