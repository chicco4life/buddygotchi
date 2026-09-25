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
    /// False in quiet or focus mode, or while something needs you.
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

/// One of Boop's tools (ARCHITECTURE.md §3.4). It owns its definition and its
/// rules, and carries out a call the same way whether a rule or the brain
/// made it.
public protocol Action: AnyObject {
    var definition: ToolDefinition { get }
    func perform(_ call: ToolCall) -> ActionOutcome
    var context: ActionContext { get }
}

extension Action {
    public var name: String { definition.name }

    /// Runs a call and logs why it was dropped, if it was.
    @discardableResult
    public func run(_ call: ToolCall) -> ActionOutcome {
        let outcome = call.name == name ? perform(call) : .dropped("sent to \(name)")
        if case .dropped(let why) = outcome { context.log("\(name): dropped \(call): \(why)") }
        return outcome
    }

    /// The call's arguments checked against this action's definition: every
    /// required one present, no unknown ones, choices and lengths respected.
    func arguments(_ call: ToolCall) -> Result<[String: ToolValue], Refusal> {
        for key in call.arguments.keys where !definition.parameters.contains(where: { $0.name == key }) {
            return .failure(Refusal("unknown argument \(key)"))
        }
        for p in definition.parameters {
            guard let value = call.arguments[p.name] else {
                if p.optional { continue }
                return .failure(Refusal("\(p.name) is missing"))
            }
            switch p.kind {
            case .choice(let options):
                guard let s = value.string, options.contains(s) else {
                    return .failure(Refusal("\(p.name) \(value) isn't one of its choices"))
                }
            case .number(let options):
                guard let n = value.number, options.contains(n) else {
                    return .failure(Refusal("\(p.name) \(value) isn't one of its choices"))
                }
            case .text(let max):
                guard let s = value.string else { return .failure(Refusal("\(p.name) isn't text")) }
                if s.count > max { return .failure(Refusal("\(p.name) is longer than \(max) characters")) }
            }
        }
        return .success(call.arguments)
    }
}

/// Boop's actions, built once at startup and handed to the harness as
/// (definition, handler) pairs.
public enum Actions {
    public static func all(context: ActionContext, voice: Voice, memory: MemoryStore) -> [Action] {
        [
            SayAction(voice: voice, context: context),
            FaceAction(context: context),
            QuietAction(context: context),
            NoteAction(memory: memory, context: context),
            RememberAction(memory: memory, context: context),
            ForgetAction(memory: memory, context: context),
            TemperamentAction(memory: memory, context: context),
            MomentAction(memory: memory, context: context),
        ]
    }
}
