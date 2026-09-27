import Foundation

/// A `moment` message: something for the device to play once (PROTOCOL.md §3).
/// A rule moment has an `anim`; a mumble has only `say`, which plays over
/// whatever face is showing. The empty moment has neither: it ends a
/// `listening` face and nothing else.
public struct DeviceMoment: Equatable, Sendable {
    public var anim: String?
    public var say: VoiceLine?
    /// Seconds; the device skips it if it can't start in time.
    public var ttl: Int

    public init(anim: String? = nil, say: VoiceLine? = nil, ttl: Int = 5) {
        self.anim = anim
        self.say = say
        self.ttl = ttl
    }

    /// `{"t":"moment","ttl":5}`: ends `listening` when no reply came.
    public static let empty = DeviceMoment()

    public var isEmpty: Bool { anim == nil && say == nil }

    /// Bubble time after the last syllable (firmware `kBubbleReadMs`).
    static let bubbleReadMs: Int64 = 1200

    /// How long the device plays it, worked out as
    /// firmware/src/app/behaviour.cpp's `onMoment` and `play` do: the
    /// animation's length (`animDuration` in firmware/src/render/anim.cpp),
    /// and a mumble lasts its syllables, plus two beats for a word, at
    /// 60–400 ms each, then 1.2 s for the bubble, when that's longer.
    /// `listening` counts as 0: the device holds it until the reply or the
    /// empty moment, which is 0 too.
    public var playMs: Int64 {
        var ms: Int64 = switch anim {
        case nil, "listening": 0
        case "cheer": 2000
        case "wiggle": 700
        default: 2500
        }
        if let say, say.syllableCount > 0 {
            let beats = Int64(say.syllableCount + (say.word?.isEmpty == false ? 2 : 0))
            ms = Swift.max(ms, beats * Int64(Swift.max(60, Swift.min(400, say.ms))) + DeviceMoment.bubbleReadMs)
        }
        return ms
    }

    public var jsonLine: String {
        var parts = ["\"t\":\"moment\""]
        if let anim { parts.append("\"anim\":\"\(anim)\"") }
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
    /// False in quiet mode, while something needs you, and while you talk
    /// until your words arrive (`Core.canMumble`).
    public var mumblesAllowed: () -> Bool
    /// `Core.setQuiet`; the app routes the effects it returns.
    public var setQuiet: (Int) -> Void
    /// Whether the last thing you said asked for quiet (`Core.quietAsked`).
    public var quietAsked: () -> Bool
    /// Where dropped calls are explained.
    public var log: (String) -> Void

    public init(send: @escaping (DeviceMoment) -> Void,
                mumblesAllowed: @escaping () -> Bool = { true }, setQuiet: @escaping (Int) -> Void = { _ in },
                quietAsked: @escaping () -> Bool = { true }, log: @escaping (String) -> Void = { _ in }) {
        self.send = send
        self.mumblesAllowed = mumblesAllowed
        self.setQuiet = setQuiet
        self.quietAsked = quietAsked
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
