import Foundation

/// The normal if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no
/// model, always available. Normal mode decides with it without Jev's key.
/// It follows normal's column (BEHAVIORS.md §6), which Jev is steered
/// toward: the rules' cheer is enough for a start or a short turn, and Boop
/// speaks up for a long turn, a failure, a poke streak and you:
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | nothing |
/// | Agent finished, done, a short turn (under 15 s) | nothing: the rules' cheer |
/// | Agent finished, done, a long or very long turn (15 s or more) | `react(proud, mumble)` |
/// | Agent finished, failed | `react(annoyed, mumble)` |
/// | Poked again and again | `react(annoyed, mumble)`: the grumble |
/// | You said anything | `Phrases`' table; yelled at or told off, `react(sad, mumble)` |
///
/// Calls the menu doesn't offer are left out.
public struct NormalRules: Classifier {
    public let id = "normal@1"

    public init() {}

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let (calls, rule) = NormalRules.decide(context.input)
        return Classification(calls: calls.filter { menu.definition($0.name) != nil }, evidence: rule)
    }

    /// The calls for an input and the row that matched.
    static func decide(_ input: Input) -> ([ToolCall], String) {
        let react = Phrases.react
        switch input.kind {
        case .agentStarted:
            return ([], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([react("annoyed", "mumble")], "failed") }
            switch input.length ?? .short {
            case .veryLong: return ([react("proud", "mumble")], "done, a very long turn")
            case .long: return ([react("proud", "mumble")], "done, a long turn")
            case .short: return ([], "done, a short turn")
            }
        case .poked:
            return ([react("annoyed", "mumble")], "poked again and again")
        case .said:
            return Phrases.reply(to: input, hurtMumbles: true)
        }
    }
}
