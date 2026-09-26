import Foundation

/// The if-else classifier (Stage 1, HARNESS.md §6): plain Swift, no model,
/// always available, and the default. It reads only the input's own fields,
/// never the transcript:
///
/// | Input | Decides |
/// | --- | --- |
/// | Agent started | nothing |
/// | Agent finished, done, 15 s or more | `react(proud, mumble)`; over a minute the writer is told to always find a word |
/// | Agent finished, done, shorter | nothing |
/// | Agent finished, failed | `react(annoyed, mumble)`: the sass, one mumble per failure |
/// | Poked again and again | `react(annoyed, mumble)`: the grumble |
/// | You said "quiet" | `quiet(n)`; n from the words: two hours 120, an hour 60, fifteen 15, else 30. Yelled or told off too: then `react(sad, silent)` |
/// | You yelled, or told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad, mumble)` |
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
            let took = input.tookMs ?? 0
            if took > 60_000 { return ([react("proud", "mumble")], "done, over a minute") }
            if took >= 15_000 { return ([react("proud", "mumble")], "done, 15 s or more") }
            return ([], "done, under 15 s")
        case .poked:
            return ([react("annoyed", "mumble")], "poked again and again")
        case .said:
            let words = Input.plain(input.words ?? "")
            let hurt = input.yelled || tellsOff(words)
            if input.asksForQuiet {
                let quiet = ToolCall("quiet", ["minutes": .number(minutes(words))])
                return hurt ? ([quiet, react("sad", "silent")], "asked for quiet, and hurt") : ([quiet], "asked for quiet")
            }
            if hurt { return ([react("sad", "mumble")], input.yelled ? "yelled at" : "told off") }
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

    /// Being told off (BEHAVIORS.md §3.3): one of these, or "you" with an
    /// insult, so "you're so annoying" counts and "this build is annoying"
    /// doesn't.
    static let tellingOff = [" shut up ", " go away ", " hate you ", " you suck ", " hush ", " stop talking ",
                             " keep it down "]
    static let you = [" you ", " you're ", " youre ", " ur "]
    static let insults = [" annoying ", " stupid ", " dumb ", " useless ", " idiot "]

    /// Plain words (`Input.plain`) that tell Boop off.
    static func tellsOff(_ words: String) -> Bool {
        tellingOff.contains(where: words.contains)
            || you.contains(where: words.contains) && insults.contains(where: words.contains)
    }
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
