import Foundation

/// `react(feeling, voice, word?)`: the feeling's face on the device, and, for
/// a mumble, a Minion line from Voice with the one real word. The classifier
/// picks the feeling and whether to mumble; the writer picks the word, only
/// for a mumble. The mumble is dropped in quiet mode or while something
/// needs you, and the face still plays.
///
/// The core's rules use the same action: `play` for any animation (a cheer,
/// an oops) and a `react` call for working chatter.
public final class ReactAction: Action {
    public let context: ActionContext
    let voice: Voice
    /// Each line gets the next seed, logged so debug mode can replay it.
    var lines: UInt64 = 0

    public init(voice: Voice, context: ActionContext) {
        self.voice = voice
        self.context = context
    }

    /// The ten feelings, their faces, and the Voice feeling their mumble
    /// uses: `smug` mumbles like proud and `sulky` like sad (VOICE.md §4).
    public static let feelings: [(name: String, face: String, size: Int, voice: Feeling, about: String)] = [
        ("happy", "happy", 1, .happy, "Pleased and friendly: a greeting, a small win."),
        ("excited", "happy", 2, .excited, "Thrilled: something big just went right."),
        ("proud", "proud", 1, .proud, "Proud: something long or hard just finished."),
        ("curious", "curious", 1, .curious, "Interested or unsure: something new, or a question."),
        ("hopeful", "love", 1, .hopeful, "Wanting something, warmly: food, attention, praise."),
        ("annoyed", "side_eye", 1, .annoyed, "Irritated at an agent: a failure, flaky tests."),
        ("sad", "worried", 1, .sad, "Down: something went badly, or Boop is starving."),
        ("sleepy", "sleepy", 1, .sleepy, "Tired: late at night, or low on energy."),
        ("smug", "smug", 1, .proud, "Pleased with itself: it knew all along."),
        ("sulky", "sulky", 1, .sad, "Pouting: told to be quiet, or brushed off."),
    ]

    /// Every animation the device has (BEHAVIORS.md §7).
    public static let anims: Set<String> = Set(feelings.map(\.face) + [
        "nod", "cheer", "oops", "wiggle", "listening", "thinking", "shrug", "zip", "gobble",
        "rumble", "levelup",
    ])

    public let definition = ToolDefinition(
        name: "react", description: "Show a feeling on Boop's face, and mumble if it fits.",
        parameters: [
            .init("feeling", .choice(ReactAction.feelings.map(\.name)),
                  about: Dictionary(uniqueKeysWithValues: ReactAction.feelings.map { ($0.name, $0.about) })),
            .init("voice", .choice(["silent", "mumble"]),
                  about: ["silent": "Just the face.", "mumble": "The face and a mumble of Boop's gibberish."]),
            .init("word", .choice(Sounds.vocabulary), optional: true, role: .writtenWhen("voice", is: "mumble")),
        ])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        let args: [String: ToolValue]
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let a): args = a
        }
        let feeling = ReactAction.feelings.first { $0.name == args["feeling"]?.string }!
        guard args["voice"]?.string == "mumble" else {
            context.send(DeviceMoment(anim: feeling.face, size: feeling.size))
            return .done("\(feeling.name), silent")
        }
        guard context.mumblesAllowed() else {
            context.send(DeviceMoment(anim: feeling.face, size: feeling.size))
            return .done("\(feeling.name), face only: Boop is quiet right now")
        }
        lines += 1
        let seed = lines
        let line = voice.line(feeling.voice, word: args["word"]?.string, mood: context.mood(), seed: seed)
        context.send(DeviceMoment(anim: feeling.face, size: feeling.size, say: line))
        return .done("\(feeling.name): \(line.text) (seed \(seed))")
    }

    /// A rule reaction from the core (`.moment`): any animation, size 1–3.
    @discardableResult
    public func play(_ anim: String, size: Int) -> ActionOutcome {
        let outcome: ActionOutcome
        if !ReactAction.anims.contains(anim) {
            outcome = .dropped("no animation called \(anim)")
        } else if !(1...3).contains(size) {
            outcome = .dropped("size \(size) isn't 1–3")
        } else {
            context.send(DeviceMoment(anim: anim, size: size))
            outcome = .done("\(anim) \(size)")
        }
        if case .dropped(let why) = outcome { context.log("react: dropped \(anim) \(size): \(why)") }
        return outcome
    }
}

/// `quiet(minutes)`: tells the core to stop mumbles for a while.
public final class QuietAction: Action {
    public let context: ActionContext

    public init(context: ActionContext) { self.context = context }

    public static let choices = [15, 30, 60, 120]

    public let definition = ToolDefinition(
        name: "quiet", description: "Stop mumbling for a while, when the person asks for quiet.",
        parameters: [.init("minutes", .number(QuietAction.choices))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            let minutes = args["minutes"]!.number!
            context.setQuiet(minutes)
            return .done("\(minutes) min")
        }
    }
}

/// `remember(where, text)`: a line in Boop's memory, under that section's
/// own rules (ARCHITECTURE.md §4). The classifier picks where; the writer
/// writes the line. `today` is short-term Notes; the rest are long-term.
public final class RememberAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public static let sections: [(name: String, chars: Int, about: String)] = [
        ("today", MemoryLimits.noteChars, "A note for later today: something the person said or asked to note."),
        ("about_you", MemoryLimits.factChars, "Something about the person that will still matter in a month."),
        ("preference", MemoryLimits.factChars, "How the person likes things done."),
        ("temperament", MemoryLimits.temperamentChars, "One sentence on how Boop has changed, only if the day gave a reason."),
        ("moment", MemoryLimits.momentChars, "A truly memorable day. Most days aren't."),
    ]

    public let definition = ToolDefinition(
        name: "remember", description: "Keep a line in Boop's memory.",
        parameters: [
            .init("where", .choice(RememberAction.sections.map(\.name)),
                  about: Dictionary(uniqueKeysWithValues: RememberAction.sections.map { ($0.name, $0.about) })),
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
        case "today": result = memory.note(text)
        case "about_you": result = memory.remember(text, as: .aboutYou)
        case "preference": result = memory.remember(text, as: .preference)
        case "temperament": result = memory.temperament(text, today: context.today())
        default: result = memory.moment(text, day: memory.reflecting ?? context.today())
        }
        switch result {
        case .failure(let why): return .dropped(why.description)
        case .success(let line): return .done(line)
        }
    }
}
