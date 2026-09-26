import Foundation

/// What both if-else classifiers make of your words (Stage 1, HARNESS.md §6).
/// They read only the input's own fields, never the transcript:
///
/// | You said | Decides |
/// | --- | --- |
/// | "remember" or "note", unless you yelled or told Boop off | `react(happy)`, `remember(where)`, where from the words below. It wins over "quiet": "remember I like it quiet" isn't asking for quiet |
/// | "quiet" | `quiet(n)`; n from the words: two hours 120, an hour 60, fifteen 15, else 30. Nothing else: Boop is quiet now |
/// | You yelled, or told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad)`, or nothing when the table keeps hurt to itself |
/// | Starting with "hello", "hi", "hey", "morning" or "good morning" | `react(happy)` |
/// | "bye", "goodbye", "see you", "good night" | `react(happy)` |
/// | "lunch", "dinner", "breakfast", "food", "snack", "hungry" | `react(hopeful)` |
/// | "good job", "well done", "nice", "great", "thanks", "the best" | `react(proud)` |
/// | Anything else | `react(curious)` |
///
/// The first row that matches wins; whole words count ("hi" isn't in
/// "this"). The writer picks every word.
///
/// Where to remember it (ARCHITECTURE.md §4), first match wins:
///
/// | The words have | Where |
/// | --- | --- |
/// | Someone else's name: a capitalised word that isn't the first, "I", a day, a month or an acronym ("Bob", not "PRs") | `today`: long-term keeps no one else's name |
/// | "I like", "I love", "I prefer", "I hate", "I don't like", "I'd rather" | `preference`: how you like things, long-term |
/// | "I", "I'm", "I've" or "my", with a sign it lasts: "always", "usually", "never", "every", "mostly", "generally", a weekday in the plural ("Fridays"), "weekends", "mornings", "evenings", "my name", "I'm a", "I work", "I live" | `about_you`: a durable fact about you, long-term |
/// | Anything else: a project, a date, today's session | `today`: short-term |
enum Phrases {
    /// The calls for what you said and the row that matched. `hurtMumbles`
    /// says whether a yell or telling off gets a sad mumble or nothing.
    static func reply(to input: Input, hurtMumbles: Bool) -> ([ToolCall], String) {
        let words = Input.plain(input.words ?? "")
        let hurt = input.yelled || Input.tellsOff(words)
        if input.asksToRemember {
            let place = place(input.words ?? "")
            return ([react("happy"), ToolCall("remember", ["where": .string(place)])], "asked to remember, \(place)")
        }
        if input.asksForQuiet {
            return ([ToolCall("quiet", ["minutes": .number(minutes(words))])], "asked for quiet")
        }
        if hurt { return (hurtMumbles ? [react("sad")] : [], input.yelled ? "yelled at" : "told off") }
        // Only at the start: "the tests broke this morning" isn't a greeting.
        if greetings.contains(where: words.hasPrefix) { return ([react("happy")], "a greeting") }
        if goodbyes.contains(where: words.contains) { return ([react("happy")], "a goodbye") }
        if meals.contains(where: words.contains) { return ([react("hopeful")], "a meal") }
        if praise.contains(where: words.contains) { return ([react("proud")], "praise") }
        return ([react("curious")], "said anything else")
    }

    static let greetings = [" hello ", " hi ", " hey ", " morning ", " good morning "]
    static let goodbyes = [" bye ", " goodbye ", " see you ", " good night ", " goodnight "]
    static let meals = [" lunch ", " dinner ", " breakfast ", " food ", " snack ", " hungry "]
    static let praise = [" good job ", " well done ", " nice ", " great ", " thanks ", " thank you ", " the best "]

    /// Where a thing to remember goes, from what you said (see the table
    /// above). A name is found as the memory store finds one, so a fact the
    /// store would refuse for long-term is kept for today instead.
    static func place(_ said: String) -> String {
        if MemoryText.otherName(Input.straight(said), boopName: nil) != nil { return "today" }
        let words = Input.plain(said)
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

    static func react(_ feeling: String) -> ToolCall {
        ToolCall("react", ["feeling": .string(feeling)])
    }
}
