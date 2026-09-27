import Foundation

/// What every if-else table makes of your words (Stage 1, HARNESS.md §6).
/// They read only the input's own fields, never the transcript:
///
/// | You said | Decides |
/// | --- | --- |
/// | "remember" or "note", unless you told Boop off | `react(happy)`, `remember(where)`, where from the words below. It wins over "quiet": "remember I like it quiet" isn't asking for quiet |
/// | Asking Boop to stop being quiet: "stop being quiet", "don't have to be quiet", "don't need to be quiet", "no more quiet", "not quiet anymore", "quiet mode off", "turn off quiet", "you can talk again", "you can speak again", "you can mumble again", "unmute" | `quiet(0)`, which ends quiet, and `react(happy)` |
/// | "quiet" | `quiet(n)`: the time you said as the nearest of 15, 30, 60 and 120 (`minutes`), else 30. Nothing else: Boop is quiet now |
/// | You told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad)`, or nothing when the table keeps hurt to itself |
/// | Starting with "hello", "hi", "hey", "morning" or "good morning" | `react(happy)` |
/// | "bye", "goodbye", "see you", "good night" | `react(happy)` |
/// | "lunch", "dinner", "breakfast", "food", "snack", "hungry" | `react(hopeful)` |
/// | "good job", "well done", "nice", "great", "thanks", "the best" | `react(proud)` |
/// | You yelled, and the words say none of the above (or nothing) | `react(sad)`, or nothing when the table keeps hurt to itself |
/// | Anything else | `react(curious)` |
///
/// The first row that matches wins; whole words count ("hi" isn't in
/// "this"). The writer picks every word.
///
/// Where to remember it (HARNESS.md §6; the sections' rules are
/// ARCHITECTURE.md §4), first match wins:
///
/// | The words have | Where |
/// | --- | --- |
/// | Someone else's name: a capitalised word that isn't the first, "I", a day, a month, an acronym or Boop's own name ("Bob", not "PRs" or "Pip") | `today`: long-term keeps no one else's name |
/// | "I like", "I love", "I prefer", "I hate", "I don't like", "I'd rather" | `preference`: how you like things, long-term |
/// | "I", "I'm", "I've" or "my", with a sign it lasts: "always", "usually", "never", "every", "mostly", "generally", a weekday in the plural ("Fridays"), "weekends", "mornings", "evenings", "my name", "I'm a", "I work", "I live" | `about_you`: a durable fact about you, long-term |
/// | Anything else: a project, a date, today's session | `today`: short-term |
enum Phrases {
    /// The calls for what you said and the row that matched. `hurtMumbles`
    /// says whether a yell or telling off gets a sad mumble or nothing;
    /// `boopName` is Boop's own name, which isn't someone else's.
    static func reply(to input: Input, hurtMumbles: Bool, boopName: String? = nil) -> ([ToolCall], String) {
        let words = Input.plain(input.words ?? "")
        let hurt = hurtMumbles ? [react("sad")] : []
        if input.asksToRemember {
            let place = place(input.words ?? "", boopName: boopName)
            return ([react("happy"), ToolCall("remember", ["where": .string(place)])], "asked to remember, \(place)")
        }
        switch input.quietAsk {
        case .end: return ([ToolCall("quiet", ["minutes": .number(0)]), react("happy")], "asked to end quiet")
        case .start: return ([ToolCall("quiet", ["minutes": .number(minutes(input.words ?? ""))])], "asked for quiet")
        case nil: break
        }
        if Input.tellsOff(words) { return (hurt, "told off") }
        // Only at the start: "the tests broke this morning" isn't a greeting.
        if greetings.contains(where: words.hasPrefix) { return ([react("happy")], "a greeting") }
        if goodbyes.contains(where: words.contains) { return ([react("happy")], "a goodbye") }
        if meals.contains(where: words.contains) { return ([react("hopeful")], "a meal") }
        if praise.contains(where: words.contains) { return ([react("proud")], "praise") }
        // Loudness last: a yelled "good job!" is still praise.
        if input.yelled { return (hurt, "yelled at") }
        return ([react("curious")], "said anything else")
    }

    static let greetings = [" hello ", " hi ", " hey ", " morning ", " good morning "]
    static let goodbyes = [" bye ", " goodbye ", " see you ", " good night ", " goodnight "]
    static let meals = [" lunch ", " dinner ", " breakfast ", " food ", " snack ", " hungry "]
    static let praise = [" good job ", " well done ", " nice ", " great ", " thanks ", " thank you ", " the best "]

    /// Where a thing to remember goes, from what you said (see the table
    /// above). A name is found as the memory store finds one, Boop's own
    /// name included, so a fact the store would refuse for long-term is
    /// kept for today instead, and "Hey Pip, remember I always ship on
    /// Fridays" isn't.
    static func place(_ said: String, boopName: String?) -> String {
        if MemoryText.otherName(Input.straight(said), boopName: boopName) != nil { return "today" }
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

    /// How long "quiet" lasts: the time you said, as the nearest of quiet's
    /// lengths (the shorter on a tie: 90 minutes is 60), or 30 when you
    /// didn't say. "Ten minutes" is 15, "three hours" 120, and "five
    /// minutes" 15: 0 only ends quiet, so it's never the nearest.
    static func minutes(_ said: String) -> Int {
        guard let asked = spokenMinutes(said) else { return 30 }
        return QuietAction.choices.filter { $0 > 0 }.min { abs(Double($0) - asked) < abs(Double($1) - asked) }!
    }

    /// A time in what you said, in minutes: a number (digits, "1.5", words
    /// up to ninety, "a", "a couple of", "a few", "one and a half") and a
    /// unit, "and a half" after it, "half an hour", "a quarter of an hour",
    /// "a little while" (15) or "a long while" (120). A unit with no number
    /// is one ("the next hour"), except hours ("for hours", 120). A number
    /// after "for" with no unit is minutes ("for fifteen"). Nil when
    /// there's none.
    static func spokenMinutes(_ said: String) -> Double? {
        // "1.5" stays one number.
        let w = Input.plain(said, keeping: "'.").split(separator: " ").map { $0.trimmingCharacters(in: ["."]) }.filter { !$0.isEmpty }
        let words = " " + w.joined(separator: " ") + " "
        if words.contains(" quarter ") { return 15 }
        if words.contains(" half an hour ") || words.contains(" half hour ") { return 30 }
        if words.contains(" little while ") { return 15 }
        if words.contains(" long while ") || words.contains(" long time ") { return 120 }
        for (i, word) in w.enumerated() {
            let perUnit: Double
            switch word {
            case "second", "seconds", "sec", "secs": perUnit = 1.0 / 60
            case "minute", "minutes", "min", "mins": perUnit = 1
            case "hour", "hours", "hr", "hrs": perUnit = 60
            default: continue
            }
            var j = i - 1
            if j >= 0, ["of", "more", "extra"].contains(w[j]) { j -= 1 }  // a couple of hours, ten more minutes
            var n: Double
            if j >= 3, w[j] == "half", w[j - 1] == "a", w[j - 2] == "and", let whole = number(w[j - 3]) {
                n = whole + 0.5  // one and a half hours
            } else if j >= 0, let said = number(w[j]) {
                n = said
                // Twenty five: the tens before the ones.
                if n < 10, j >= 1, let tens = number(w[j - 1]), isTens(tens) { n += tens }
                if words.contains(" \(word) and a half ") { n += 0.5 }  // an hour and a half
            } else if !word.hasSuffix("s") {
                n = 1  // the next hour, another minute
            } else if word == "hours" || word == "hrs" {
                return 120  // for hours
            } else {
                continue
            }
            return n * perUnit
        }
        // For fifteen, for the next 20: a number with no unit is minutes.
        guard var k = w.firstIndex(of: "for").map({ $0 + 1 }) else { return nil }
        while k < w.count, ["the", "next", "another", "about", "like", "just"].contains(w[k]) { k += 1 }
        guard k < w.count, !vague.contains(w[k]), var n = number(w[k]) else { return nil }
        if isTens(n), k + 1 < w.count, !vague.contains(w[k + 1]), let ones = number(w[k + 1]), ones < 10 { n += ones }
        return n
    }

    static func number(_ word: String) -> Double? {
        if word.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let n = Double(word) { return n }
        return numbers[word]
    }
    static func isTens(_ n: Double) -> Bool { n >= 20 && n < 100 && n.truncatingRemainder(dividingBy: 10) == 0 }
    static let numbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "couple": 2, "three": 3, "few": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90]
    /// Numbers that only count before a unit: "for a while" is no time.
    static let vague: Set = ["a", "an", "couple", "few"]

    static func react(_ feeling: String) -> ToolCall {
        ToolCall("react", ["feeling": .string(feeling)])
    }
}
