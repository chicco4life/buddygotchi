import Foundation

/// The if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no model,
/// always available, and the default. It reads only the input's own fields,
/// never the transcript:
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | nothing |
/// | Agent finished, done, 5 min or more | `react(proud, mumble)` |
/// | Agent finished, done, shorter | nothing |
/// | Agent finished, failed | `react(annoyed, mumble)`: the sass, one mumble per failure |
/// | You said "shut up", "quiet", "hush", "stop talking", "keep it down" | `quiet(n)` then `react(sulky, silent)`; n from the words: two hours 120, an hour 60, fifteen 15, else 30 |
/// | You said "remember" or "note" | `react(happy, mumble)`, `remember(today)` |
/// | You said "hello", "hi", "hey", "morning" | `react(happy, mumble)` |
/// | You said "good job", "well done", "nice", "great", "thanks", "the best" | `react(proud, mumble)` |
/// | You said anything else | `react(curious, mumble)` |
/// | New day | nothing: deciding what lasts needs a model (Jev) |
///
/// The first row that matches wins; whole words count ("hi" isn't in
/// "this"). The writer picks every word. Calls the menu doesn't offer are
/// left out.
public struct RulesClassifier: Classifier {
    public let id = "rules@2"

    public init() {}

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let (calls, rule) = RulesClassifier.decide(context.input, memory: context.memory)
        return Classification(calls: calls.filter { menu.definition($0.name) != nil }, evidence: rule)
    }

    /// The calls for an input and the row that matched.
    static func decide(_ input: Input, memory: Prompt.Memory) -> ([ToolCall], String) {
        switch input.kind {
        case .agentStarted:
            return ([], "agent started")
        case .agentFinished:
            if input.outcome == .failed { return ([react("annoyed", "mumble")], "failed") }
            if (input.tookMs ?? 0) >= 300_000 { return ([react("proud", "mumble")], "done, 5 min or more") }
            return ([], "done, under 5 min")
        case .said:
            let words = plain(input.words ?? "")
            if hush.contains(where: words.contains) {
                return ([ToolCall("quiet", ["minutes": .number(minutes(words))]), react("sulky", "silent")], "asked for quiet")
            }
            if ["remember", "note"].contains(where: words.contains) {
                return ([react("happy", "mumble"), ToolCall("remember", ["where": .string("today")])], "asked to remember")
            }
            if greetings.contains(where: words.contains) { return ([react("happy", "mumble")], "a greeting") }
            if praise.contains(where: words.contains) { return ([react("proud", "mumble")], "praise") }
            return ([react("curious", "mumble")], "said anything else")
        case .newDay:
            return ([], "a new day")
        }
    }

    /// Lowercase words between single spaces, padded, so a phrase matches
    /// whole words only: " hi there ".
    static func plain(_ words: String) -> String {
        let letters = words.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return " " + String(letters).split(separator: " ").joined(separator: " ") + " "
    }

    static let hush = [" shut up ", " quiet ", " hush ", " stop talking ", " keep it down "]
    static let greetings = [" hello ", " hi ", " hey ", " morning ", " good morning "]
    static let praise = [" good job ", " well done ", " nice ", " great ", " thanks ", " thank you ", " the best "]

    /// How long "quiet" lasts, from the words.
    static func minutes(_ words: String) -> Int {
        if [" two hours ", " couple of hours ", " 2 hours "].contains(where: words.contains) { return 120 }
        if [" fifteen ", " 15 "].contains(where: words.contains) { return 15 }
        if [" half an hour ", " thirty ", " 30 "].contains(where: words.contains) { return 30 }
        if words.contains(" hour ") { return 60 }
        return 30
    }

    static func react(_ feeling: String, _ voice: String) -> ToolCall {
        ToolCall("react", ["feeling": .string(feeling), "voice": .string(voice)])
    }
}
