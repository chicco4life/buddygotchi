import Foundation

/// `react(feeling, word?)`: a mumble, a Minion line from Voice in the
/// feeling's voice, with the one real word, sent as a moment with no
/// animation so it plays over whatever face is showing. The classifier picks
/// the feeling; the writer picks the word. The mumble is dropped in quiet
/// mode, while something needs you, and while you talk until your words
/// arrive. The feelings' own faces are parked (FUTURE.md), so staying silent
/// is not calling `react` at all.
///
/// The core's rules use the same action: `play` for their animations (a
/// cheer), `endListening` for the empty moment, and a `react` call for
/// working chatter.
public final class ReactAction: Action {
    public let context: ActionContext
    let voice: Voice
    /// Each line gets the next seed, logged so debug mode can replay it.
    var lines: UInt64 = 0

    public init(voice: Voice, context: ActionContext) {
        self.voice = voice
        self.context = context
    }

    /// The ten feelings and the Voice feeling their mumble uses: `smug`
    /// mumbles like proud and `sulky` like sad (VOICE.md §4).
    public static let feelings: [(name: String, voice: Feeling, about: String)] = [
        ("happy", .happy, "Pleased and friendly: a greeting, a small win."),
        ("excited", .excited, "Thrilled: something big just went right."),
        ("proud", .proud, "Proud: something long or hard just finished, whatever it was about."),
        ("curious", .curious, "Interested or unsure: something new, or a question."),
        ("hopeful", .hopeful, "Wanting something, warmly: attention, praise."),
        ("annoyed", .annoyed, "Irritated at an agent or its work: a turn that just failed, flaky tests, a build that keeps breaking."),
        ("sad", .sad, "Hurt: yelled at or told off."),
        ("sleepy", .sleepy, "Tired: late at night."),
        ("smug", .proud, "Pleased with itself: it knew all along."),
        ("sulky", .sad, "Pouting: brushed off or left out. Being told off is sad instead."),
    ]

    /// What a mumble's word can come from, in the order steering.md's
    /// Writing tries them. The writer picks one before the word, which
    /// keeps a small model from answering every annoyed mumble with the
    /// same annoyed word (HARNESS.md §7).
    public static let wordSources = ["what they said", "the failed topic", "how the turn went", "the feeling"]

    /// Every animation the rules may play (BEHAVIORS.md §5).
    public static let anims: Set<String> = ["cheer", "wiggle", "listening"]

    public let definition = ToolDefinition(
        name: "react", description: "Mumble with a feeling.",
        question: "Does what just happened call for Boop to react?",
        parameters: [
            .init("feeling", .choice(ReactAction.feelings.map(\.name)),
                  about: Dictionary(uniqueKeysWithValues: ReactAction.feelings.map { ($0.name, $0.about) }),
                  question: "Which feeling does Boop have about what just happened?"),
            .init("word", .choice(Sounds.vocabulary), optional: true, role: .written, sources: ReactAction.wordSources),
        ])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        let args: [String: ToolValue]
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let a): args = a
        }
        let feeling = ReactAction.feelings.first { $0.name == args["feeling"]?.string }!
        guard context.mumblesAllowed() else { return .dropped("Boop is quiet right now") }
        lines += 1
        let seed = lines
        let line = voice.line(feeling.voice, word: args["word"]?.string, seed: seed)
        context.send(DeviceMoment(say: line))
        return .done("\(feeling.name): \(line.text) (seed \(seed))")
    }

    /// A rule reaction from the core (`.moment`): one of `anims`.
    @discardableResult
    public func play(_ anim: String) -> ActionOutcome {
        guard ReactAction.anims.contains(anim) else {
            context.log("react: dropped \(anim): no animation called \(anim)")
            return .dropped("no animation called \(anim)")
        }
        context.send(DeviceMoment(anim: anim))
        return .done(anim)
    }

    /// The core's `.endListening`: the empty moment, which ends the device's
    /// `listening` face if no reply has.
    @discardableResult
    public func endListening() -> ActionOutcome {
        context.send(.empty)
        return .done("end listening")
    }
}

/// `quiet(minutes)`: tells the core to stop mumbles for a while, only when
/// the last thing you said asked for quiet (`Input.asksForQuiet`), whatever
/// the classifier decided (BEHAVIORS.md §3.3).
public final class QuietAction: Action {
    public let context: ActionContext

    public init(context: ActionContext) { self.context = context }

    public static let choices = [15, 30, 60, 120]

    public let definition = ToolDefinition(
        name: "quiet", description: "Stop mumbling for a while, when the person asks for quiet.",
        question: "Did the person just ask Boop to be quiet?",
        parameters: [.init("minutes", .number(QuietAction.choices),
                           about: ["15": "Fifteen minutes, or a little while.",
                                   "30": "Half an hour, or when they don't say how long.",
                                   "60": "An hour.", "120": "Two hours, or a long while."],
                           question: "How long did the person ask Boop to be quiet for?")])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            guard context.quietAsked() else { return .dropped("only when asked to be quiet") }
            let minutes = args["minutes"]!.number!
            context.setQuiet(minutes)
            return .done("\(minutes) min")
        }
    }
}

/// `remember(where, text)`: a line in Boop's memory, under that section's
/// own rules (ARCHITECTURE.md §4). The classifier picks where; the writer
/// writes the line. Facts about a project or this session are short-term
/// notes for today; durable facts about the person, and how they like
/// things done, are long-term.
public final class RememberAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public static let sections: [(name: String, chars: Int, about: String)] = [
        ("today", MemoryLimits.noteChars,
         "Short-term, for today: a fact about a project or this session, like what something is, a date, or what they're doing now."),
        ("about_you", MemoryLimits.factChars,
         "Long-term: a durable fact about the person that will still matter in a month, like their role, how they work or their routine."),
        ("preference", MemoryLimits.factChars,
         "Long-term: how the person likes things done, lasting."),
    ]

    public let definition = ToolDefinition(
        name: "remember", description: "Keep a line in Boop's memory, when the person tells Boop a fact.",
        question: "Is there something worth keeping in Boop's memory, as Remembering says?",
        parameters: [
            .init("where", .choice(RememberAction.sections.map(\.name)),
                  about: Dictionary(uniqueKeysWithValues: RememberAction.sections.map { ($0.name, $0.about) }),
                  question: "Where does it belong in Boop's memory, as Remembering says?"),
            .init("text", .text(maxLength: RememberAction.sections.map(\.chars).max()!, by: "where",
                                limits: Dictionary(uniqueKeysWithValues: RememberAction.sections.map { ($0.name, $0.chars) })),
                  role: .written),
        ])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        let args: [String: ToolValue]
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let a): args = a
        }
        let text = args["text"]!.string!
        let result: Result<String, Refusal>
        switch args["where"]!.string! {
        case "about_you": result = memory.remember(text, as: .aboutYou)
        case "preference": result = memory.remember(text, as: .preference)
        default: result = memory.note(text)
        }
        switch result {
        case .failure(let why): return .dropped(why.description)
        case .success(let line): return .done(line)
        }
    }
}
