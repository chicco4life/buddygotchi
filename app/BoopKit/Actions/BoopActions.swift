import Foundation

/// `say(feeling, word?)`: asks Voice for a Minion line and sends it as a
/// moment with no animation, so it plays over whatever face is showing.
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
        let line = voice.line(feeling, word: args["word"]?.string, seed: seed)
        context.send(DeviceMoment(say: line))
        return .done("\(line.text) (seed \(seed))")
    }
}

/// Plays the core's rule moments (`.moment`). Not a tool: the brain can't
/// pick a face; only the rules play animations.
public final class FacePlayer {
    public let context: ActionContext

    public init(context: ActionContext) { self.context = context }

    /// Every animation the core may play (BEHAVIORS.md §5).
    public static let anims: Set<String> = ["cheer", "nod", "wiggle", "listening", "thinking", "shrug"]

    @discardableResult
    public func play(_ anim: String) -> ActionOutcome {
        guard FacePlayer.anims.contains(anim) else {
            context.log("face: dropped \(anim): no animation called \(anim)")
            return .dropped("no animation called \(anim)")
        }
        context.send(DeviceMoment(anim: anim))
        return .done(anim)
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

/// `forget(text)`: reflection only. Removes a line about the person that
/// turned out wrong. The brain picks from the lines there are, so it can't
/// name one that isn't.
public final class ForgetAction: Action {
    public let context: ActionContext
    let memory: MemoryStore

    public init(memory: MemoryStore, context: ActionContext) {
        self.memory = memory
        self.context = context
    }

    /// Built for each call from About you and Preferences as they are now.
    public var definition: ToolDefinition {
        let lt = memory.longTerm
        return ToolDefinition(
            name: "forget", description: "Remove a line about the person that turned out wrong.",
            parameters: [.init("text", .choice((lt?.aboutYou ?? []) + (lt?.preferences ?? [])))])
    }

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
