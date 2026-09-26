import Foundation

/// The calm if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no
/// model, always available. Calm mode decides with it. Boop keeps to itself
/// unless a turn failed or you talk to it; the core still shows "needs you"
/// and cheers a very long turn (over a minute):
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | nothing |
/// | Agent finished, done | nothing |
/// | Agent finished, failed | `react(annoyed)`: the one alert besides "needs you" |
/// | Poked again and again | nothing |
/// | You said anything | `Phrases`' table; told off, or yelled with nothing else said, nothing |
///
/// Calls the menu doesn't offer are left out.
public struct CalmRules: Classifier {
    public let id = "calm@1"

    public init() {}

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let (calls, rule) = CalmRules.decide(context.input)
        return Classification(calls: calls.filter { menu.definition($0.name) != nil }, evidence: rule)
    }

    /// The calls for an input and the row that matched.
    static func decide(_ input: Input) -> ([ToolCall], String) {
        switch input.kind {
        case .agentStarted:
            return ([], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([Phrases.react("annoyed")], "failed") }
            return ([], "done")
        case .poked:
            return ([], "poked again and again")
        case .said:
            return Phrases.reply(to: input, hurtMumbles: false)
        }
    }
}
