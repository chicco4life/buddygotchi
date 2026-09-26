import Foundation

/// What both if-else classifiers make of your words (Stage 1, HARNESS.md §6).
/// They read only the input's own fields, never the transcript:
///
/// | You said | Decides |
/// | --- | --- |
/// | "remember" or "note", unless you yelled or told Boop off | `react(happy, mumble)`, `remember(where)`, where from the words below. It wins over "quiet": "remember I like it quiet" isn't asking for quiet |
/// | "quiet" | `quiet(n)`; n from the words: two hours 120, an hour 60, fifteen 15, else 30. Yelled or told off too: then `react(sad, silent)` |
/// | You yelled, or told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad, mumble)`, or nothing when the table keeps hurt to itself |
/// | "hello", "hi", "hey", "morning" | `react(happy, mumble)` |
/// | "bye", "goodbye", "see you", "good night" | `react(happy, mumble)` |
/// | "lunch", "dinner", "breakfast", "food", "snack", "hungry" | `react(hopeful, mumble)` |
/// | "good job", "well done", "nice", "great", "thanks", "the best" | `react(proud, mumble)` |
/// | Anything else | `react(curious, mumble)` |
///
/// The first row that matches wins; whole words count ("hi" isn't in
/// "this"). The writer picks every word.
///
/// Where to remember it (ARCHITECTURE.md §4), first match wins:
///
/// | The words have | Where |
/// | --- | --- |
/// | "I like", "I love", "I prefer", "I hate", "I don't like", "I'd rather" | `preference`: how you like things, long-term |
/// | "I", "I'm", "I've" or "my", with a sign it lasts: "always", "usually", "never", "every", "mostly", "generally", a weekday in the plural ("Fridays"), "weekends", "mornings", "evenings", "my name", "I'm a", "I work", "I live" | `about_you`: a durable fact about you, long-term |
/// | Anything else: a project, a date, today's session | `today`: short-term |
enum Phrases {
    /// The calls for what you said and the row that matched. `hurtMumbles`
    /// says whether a yell or telling off gets a sad mumble or nothing: a
    /// silent react is on the menu only when you ask for quiet
    /// (HARNESS.md §2).
    static func reply(to input: Input, hurtMumbles: Bool) -> ([ToolCall], String) {
        let words = Input.plain(input.words ?? "")
        let hurt = input.yelled || tellsOff(words)
        if !hurt && [" remember ", " note "].contains(where: words.contains) {
            let place = place(words)
            return ([react("happy", "mumble"), ToolCall("remember", ["where": .string(place)])], "asked to remember, \(place)")
        }
        if input.asksForQuiet {
            let quiet = ToolCall("quiet", ["minutes": .number(minutes(words))])
            return hurt ? ([quiet, react("sad", "silent")], "asked for quiet, and hurt") : ([quiet], "asked for quiet")
        }
        if hurt { return (hurtMumbles ? [react("sad", "mumble")] : [], input.yelled ? "yelled at" : "told off") }
        if greetings.contains(where: words.contains) { return ([react("happy", "mumble")], "a greeting") }
        if goodbyes.contains(where: words.contains) { return ([react("happy", "mumble")], "a goodbye") }
        if meals.contains(where: words.contains) { return ([react("hopeful", "mumble")], "a meal") }
        if praise.contains(where: words.contains) { return ([react("proud", "mumble")], "praise") }
        return ([react("curious", "mumble")], "said anything else")
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
    static let goodbyes = [" bye ", " goodbye ", " see you ", " good night ", " goodnight "]
    static let meals = [" lunch ", " dinner ", " breakfast ", " food ", " snack ", " hungry "]
    static let praise = [" good job ", " well done ", " nice ", " great ", " thanks ", " thank you ", " the best "]

    /// Where a thing to remember goes, from the words (see the table above).
    static func place(_ words: String) -> String {
        if likes.contains(where: words.contains) { return "preference" }
        if firstPerson.contains(where: words.contains) && lasting.contains(where: words.contains) { return "about_you" }
        return "today"
    }
    static let likes = [" i like ", " i love ", " i prefer ", " i hate ", " i don't like ", " i dont like ", " i'd rather ",
                        " i would rather "]
    static let firstPerson = [" i ", " i'm ", " im ", " i've ", " my "]
    static let lasting = [" always ", " usually ", " never ", " every ", " mostly ", " generally ", " mondays ", " tuesdays ",
                          " wednesdays ", " thursdays ", " fridays ", " saturdays ", " sundays ", " weekends ", " mornings ",
                          " evenings ", " my name ", " i'm a ", " i am a ", " i work ", " i live "]

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
