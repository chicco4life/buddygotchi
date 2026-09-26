import Foundation

/// A `moment` message: something for the device to play once (PROTOCOL.md §3).
public struct DeviceMoment: Equatable, Sendable {
    public var anim: String
    public var size: Int
    public var say: VoiceLine?
    /// Seconds; the device skips it if it can't start in time.
    public var ttl: Int

    public init(anim: String, size: Int = 1, say: VoiceLine? = nil, ttl: Int = 5) {
        self.anim = anim
        self.size = size
        self.say = say
        self.ttl = ttl
    }

    /// Bubble time after the last syllable (firmware `kBubbleReadMs`).
    static let bubbleReadMs: Int64 = 1200

    /// How long the device plays it, given the mood in the last `state` it
    /// was sent, worked out as firmware/src/app/behaviour.cpp's `onMoment`
    /// and `play` do: a cheer is a size smaller when energy is under 60 and
    /// a size bigger at 140 or more; the animation's length
    /// (`animDuration` in firmware/src/render/anim.cpp) is scaled by 100 ÷
    /// pace, with pace held to 70–140; and a mumble lasts its syllables,
    /// plus two beats for a word, at 60–400 ms each, then 1.2 s for the
    /// bubble, when that's longer. `listening` and `thinking` count as 0:
    /// the device holds them until something replaces them.
    public func playMs(mood: Mood) -> Int64 {
        var size = Swift.max(1, Swift.min(3, self.size))
        if anim == "cheer" {
            if mood.energy < 60 { size = Swift.max(1, size - 1) }
            if mood.energy >= 140 { size = Swift.min(3, size + 1) }
        }
        let base: Int64 = switch anim {
        case "listening", "thinking": 0
        case "nod": 600
        case "cheer": 2000 + Int64(size - 1) * 400
        case "oops": 1400
        case "side_eye": 1600
        case "wiggle": 700
        case "shrug": 1200
        case "zip", "gobble", "rumble": 1500
        case "levelup": 2400
        default: 2500
        }
        var ms = base * 100 / Int64(Swift.max(70, Swift.min(140, mood.pace)))
        if let say, say.syllableCount > 0 {
            let beats = Int64(say.syllableCount + (say.word?.isEmpty == false ? 2 : 0))
            ms = Swift.max(ms, beats * Int64(Swift.max(60, Swift.min(400, say.ms))) + DeviceMoment.bubbleReadMs)
        }
        return ms
    }

    public var jsonLine: String {
        var parts = ["\"t\":\"moment\"", "\"anim\":\"\(anim)\"", "\"size\":\(size)"]
        if let say { parts.append("\"say\":" + say.json) }
        parts.append("\"ttl\":\(ttl)")
        return "{" + parts.joined(separator: ",") + "}"
    }
}

/// What actions may reach. The app wires each closure to the part that
/// carries it out; tests wire them to recorders.
public struct ActionContext {
    /// Sends a moment through the device link.
    public var send: (DeviceMoment) -> Void
    /// Boop's mood now, for Voice's tempo.
    public var mood: () -> Mood
    /// False in quiet mode, or while something needs you.
    public var mumblesAllowed: () -> Bool
    /// `Core.setQuiet`; the app routes the effects it returns.
    public var setQuiet: (Int) -> Void
    /// Today, `yyyy-MM-dd`.
    public var today: () -> String
    /// Where dropped calls are explained.
    public var log: (String) -> Void

    public init(send: @escaping (DeviceMoment) -> Void, mood: @escaping () -> Mood = { Mood() },
                mumblesAllowed: @escaping () -> Bool = { true }, setQuiet: @escaping (Int) -> Void = { _ in },
                today: @escaping () -> String, log: @escaping (String) -> Void = { _ in }) {
        self.send = send
        self.mood = mood
        self.mumblesAllowed = mumblesAllowed
        self.setQuiet = setQuiet
        self.today = today
        self.log = log
    }
}

/// What happened to a call.
public enum ActionOutcome: Equatable, Sendable {
    case done(String)
    case dropped(String)

    public var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

/// One of Boop's outputs (ARCHITECTURE.md §3.4). It owns its definition and
/// its rules, and carries out a call the same way whether a rule or the brain
/// made it.
public protocol Action: AnyObject {
    var definition: ToolDefinition { get }
    func perform(_ call: ToolCall) -> ActionOutcome
    var context: ActionContext { get }
}

extension Action {
    public var name: String { definition.name }

    /// Runs a call and logs why it was dropped, if it was. The log gets the
    /// reason, never the arguments, which can carry what you said
    /// (HARNESS.md §8).
    @discardableResult
    public func run(_ call: ToolCall) -> ActionOutcome {
        let outcome = call.name == name ? perform(call) : .dropped("sent to \(name)")
        if case .dropped(let why) = outcome { context.log("\(name): dropped: \(why)") }
        return outcome
    }

    /// The call's arguments checked against this action's definition.
    func arguments(_ call: ToolCall) -> Result<[String: ToolValue], Refusal> {
        if let why = definition.check(call.arguments) { return .failure(Refusal(why)) }
        return .success(call.arguments)
    }
}

/// Boop's actions, built once at startup and handed to the harness as
/// (definition, handler) pairs.
public enum Actions {
    public static func all(context: ActionContext, voice: Voice, memory: MemoryStore) -> [Action] {
        [
            ReactAction(voice: voice, context: context),
            QuietAction(context: context),
            RememberAction(memory: memory, context: context),
        ]
    }
}
