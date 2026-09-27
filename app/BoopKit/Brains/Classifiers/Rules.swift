import Foundation

/// The if-else classifiers (Stage 1, HARNESS.md §6): plain Swift, no model,
/// always available, one per mode. Each decides exactly its mode's column
/// in BEHAVIORS.md §6; normal's is also what Jev is steered toward, and
/// decides without Jev's key. They read only the input's fields:
///
/// | Input | Chatty | Normal | Calm |
/// | --- | --- | --- | --- |
/// | Agent started | `react(curious)` | nothing | nothing |
/// | Agent finished, done, a short turn (under 15 s) | `react(happy)` | nothing: the rules' cheer | nothing |
/// | Agent finished, done, a long turn (15 s up to a minute) | `react(proud)` | `react(proud)` | nothing |
/// | Agent finished, done, a very long turn (over a minute) | `react(excited)` | `react(proud)` | nothing: the rules' cheer |
/// | Agent finished, failed | `react(annoyed)` | `react(annoyed)` | `react(annoyed)`: the one alert besides "needs you" |
/// | Poked again and again | `react(annoyed)`: the grumble | `react(annoyed)` | nothing |
/// | You said anything | `Phrases`' table | `Phrases`' table | `Phrases`' table, but nothing when told off, or yelled at with nothing else said |
///
/// Calls the menu doesn't offer are left out.
public struct Rules: Classifier {
    public let mode: Mode
    /// `chatty@1`, `normal@1` or `calm@1`.
    public var id: String { "\(mode.rawValue)@1" }

    public init(_ mode: Mode) { self.mode = mode }

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let (calls, rule) = decide(context.input)
        return Classification(calls: calls.filter { menu.definition($0.name) != nil }, evidence: rule)
    }

    /// The calls for an input and the row that matched.
    func decide(_ input: Input) -> ([ToolCall], String) {
        let react = Phrases.react
        switch input.kind {
        case .agentStarted:
            return (mode == .chatty ? [react("curious")] : [], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([react("annoyed")], "failed") }
            let length = input.length ?? .short
            let feeling: String? = switch (mode, length) {
            case (.chatty, .short): "happy"
            case (.chatty, .long), (.normal, .long), (.normal, .veryLong): "proud"
            case (.chatty, .veryLong): "excited"
            default: nil
            }
            return (feeling.map { [react($0)] } ?? [], "done, a \(length.rawValue) turn")
        case .poked:
            return (mode == .calm ? [] : [react("annoyed")], "poked again and again")
        case .said:
            return Phrases.reply(to: input, hurtMumbles: mode != .calm)
        }
    }
}
