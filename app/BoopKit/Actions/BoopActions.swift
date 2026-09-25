import Foundation

/// `say(feeling, word?)`: asks Voice for a Minion line and sends it as a
/// moment, with the face that goes with the feeling.
public final class SayAction: Action {
    public let context: ActionContext
    let voice: Voice
    /// Each line gets the next seed, logged so debug mode can replay it.
    var lines: UInt64 = 0

    public init(voice: Voice, context: ActionContext) {
        self.voice = voice
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "say", description: "Mumble. Pick a feeling; add one word only if it helps.",
        parameters: [
            .init("feeling", .choice(Feeling.allCases.map(\.rawValue))),
            .init("word", .choice(Sounds.vocabulary), optional: true),
        ])

    /// The face each feeling plays under its mumble. The device only speaks
    /// over an animation.
    static let faces: [Feeling: String] = [
        .happy: "happy", .excited: "happy", .proud: "proud", .curious: "curious",
        .hopeful: "love", .annoyed: "side_eye", .sad: "worried", .sleepy: "sleepy",
    ]

    public func perform(_ call: ToolCall) -> ActionOutcome {
        let args: [String: ToolValue]
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let a): args = a
        }
        guard context.mumblesAllowed() else { return .dropped("Boop is quiet right now") }
        let feeling = Feeling(rawValue: args["feeling"]?.string ?? "")!
        lines += 1
        let seed = lines
        let line = voice.line(feeling, word: args["word"]?.string, mood: context.mood(), seed: seed)
        context.send(DeviceMoment(anim: SayAction.faces[feeling]!, size: feeling == .excited ? 2 : 1, say: line))
        return .done("\(line.text) (seed \(seed))")
    }
}

/// `face(name)`: plays an animation as a moment. The brain picks from the
/// faces; the core's rules may play any animation.
public final class FaceAction: Action {
    public let context: ActionContext

    public init(context: ActionContext) { self.context = context }

    /// Faces the brain can pick (BEHAVIORS.md §7).
    public static let faces = ["happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "side_eye"]
    /// Every animation the device has.
    public static let anims: Set<String> = Set(faces + [
        "nod", "cheer", "oops", "wiggle", "stretch", "yawn", "listening", "thinking", "shrug", "zip", "gobble",
        "rumble", "levelup",
    ])

    public let definition = ToolDefinition(
        name: "face", description: "Show a feeling on your face.",
        parameters: [.init("name", .choice(FaceAction.faces))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            let name = args["name"]!.string!
            context.send(DeviceMoment(anim: name, size: 1))
            return .done(name)
        }
    }

    /// A rule reaction from the core (`.moment`): any animation, size 1–3.
    @discardableResult
    public func play(_ anim: String, size: Int) -> ActionOutcome {
        let outcome: ActionOutcome
        if !FaceAction.anims.contains(anim) {
            outcome = .dropped("no animation called \(anim)")
        } else if !(1...3).contains(size) {
            outcome = .dropped("size \(size) isn't 1–3")
        } else {
            context.send(DeviceMoment(anim: anim, size: size))
            outcome = .done("\(anim) \(size)")
        }
        if case .dropped(let why) = outcome { context.log("face: dropped \(anim) \(size): \(why)") }
        return outcome
    }
}

/// `quiet(minutes)`: tells the core to stop mumbles for a while.
public final class QuietAction: Action {
    public let context: ActionContext

    public init(context: ActionContext) { self.context = context }

    public static let choices = [15, 30, 60, 120]

    public let definition = ToolDefinition(
        name: "quiet", description: "Stop mumbling for a while, when asked to.",
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

/// `note(text)`: a line in today's notes.
public final class NoteAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "note", description: "Jot down something worth remembering later today. A few words.",
        parameters: [.init("text", .text(maxLength: MemoryLimits.noteChars))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            switch memory.note(args["text"]!.string!) {
            case .failure(let why): return .dropped(why.description)
            case .success(let line): return .done(line)
            }
        }
    }
}

/// `remember(text, kind)`: reflection only. A lasting fact or preference.
public final class RememberAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "remember", description: "Keep something about the person that will still matter in a month.",
        parameters: [
            .init("text", .text(maxLength: MemoryLimits.factChars)),
            .init("kind", .choice(MemoryStore.FactKind.allCases.map(\.rawValue))),
        ])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            let kind = MemoryStore.FactKind(rawValue: args["kind"]!.string!)!
            switch memory.remember(args["text"]!.string!, as: kind) {
            case .failure(let why): return .dropped(why.description)
            case .success(let line): return .done(line)
            }
        }
    }
}

/// `forget(text)`: reflection only. Removes a fact that turned out wrong.
public final class ForgetAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "forget", description: "Remove a line about the person that turned out wrong.",
        parameters: [.init("text", .text(maxLength: MemoryLimits.factChars))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            switch memory.forget(args["text"]!.string!) {
            case .failure(let why): return .dropped(why.description)
            case .success(let line): return .done(line)
            }
        }
    }
}

/// `temperament(text)`: reflection only. One new sentence about who Boop is.
public final class TemperamentAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "temperament", description: "Add one sentence about how you've changed, only if today gave a reason.",
        parameters: [.init("text", .text(maxLength: MemoryLimits.temperamentChars))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            switch memory.temperament(args["text"]!.string!, today: context.today()) {
            case .failure(let why): return .dropped(why.description)
            case .success(let line): return .done(line)
            }
        }
    }
}

/// `moment(text)`: reflection only. A truly memorable day, dated the day
/// being reflected on.
public final class MomentAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    public let definition = ToolDefinition(
        name: "moment", description: "Keep a truly memorable day. Most days aren't.",
        parameters: [.init("text", .text(maxLength: MemoryLimits.momentChars))])

    public func perform(_ call: ToolCall) -> ActionOutcome {
        switch arguments(call) {
        case .failure(let why): return .dropped(why.description)
        case .success(let args):
            switch memory.moment(args["text"]!.string!, day: memory.reflecting ?? context.today()) {
            case .failure(let why): return .dropped(why.description)
            case .success(let line): return .done(line)
            }
        }
    }
}
