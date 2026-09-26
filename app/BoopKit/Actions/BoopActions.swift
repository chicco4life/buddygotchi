import Foundation

/// `react(feeling, voice, word?)`: for a mumble, a Minion line from Voice
/// in the feeling's voice, with the one real word, sent as a moment with no
/// animation so it plays over whatever face is showing. The classifier picks
/// the feeling and whether to mumble; the writer picks the word, only for a
/// mumble. The mumble is dropped in quiet mode or while something needs you.
/// The feelings' own faces are parked (FUTURE.md), so `silent` shows nothing.
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
        ("proud", .proud, "Proud: something long or hard just finished."),
        ("curious", .curious, "Interested or unsure: something new, or a question."),
        ("hopeful", .hopeful, "Wanting something, warmly: attention, praise."),
        ("annoyed", .annoyed, "Irritated at an agent: a failure, flaky tests."),
        ("sad", .sad, "Down: something went badly."),
        ("sleepy", .sleepy, "Tired: late at night."),
        ("smug", .proud, "Pleased with itself: it knew all along."),
        ("sulky", .sad, "Pouting: told to be quiet, or brushed off."),
    ]

    /// Every animation the rules may play (BEHAVIORS.md §5).
    public static let anims: Set<String> = ["cheer", "wiggle", "listening"]

    public let definition = ToolDefinition(
        name: "react", description: "Mumble with a feeling, or stay silent.",
        parameters: [
            .init("feeling", .choice(ReactAction.feelings.map(\.name)),
                  about: Dictionary(uniqueKeysWithValues: ReactAction.feelings.map { ($0.name, $0.about) })),
            .init("voice", .choice(["silent", "mumble"]),
                  about: ["silent": "Say nothing.", "mumble": "A mumble of Boop's gibberish in that feeling."]),
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
            return .done("\(feeling.name), silent: Boop has no face for it in v1")
        }
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
