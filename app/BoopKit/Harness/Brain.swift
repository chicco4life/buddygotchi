import Foundation

/// Whatever decides Boop's reactions (HARNESS.md §7): a language model, a
/// "system one" model or plain rules. The harness hands every brain the same
/// typed situation and menu and gets back tool calls from that menu:
///
///     decide(situation, menu) → [say(feeling: proud, word: finally)]
///
/// No calls means staying quiet. How the situation reaches a model (a text
/// prompt, JSON state, questions) is the brain's own business; the harness
/// checks the calls against the menu whatever the brain is.
public protocol Brain: Sendable {
    /// e.g. `apple:26.4`, `jev:jev-latest`, `cloud:<model>`, `rules@1`.
    var id: String { get }
    /// May throw; the harness drops the call and logs why.
    func decide(_ situation: Situation, _ menu: Menu, deadline: Duration) async throws -> Decision
}

/// What one brain call is about (HARNESS.md §4): what just happened, the
/// memory text, and this conversation's earlier turns.
public struct Situation: Equatable, Sendable {
    public var trigger: Trigger
    public var memory: Prompt.Memory
    /// Oldest first. None for reflection, which is a call on its own.
    public var recent: [Turn]

    public init(trigger: Trigger, memory: Prompt.Memory, recent: [Turn] = []) {
        self.trigger = trigger
        self.memory = memory
        self.recent = recent
    }
}

/// One earlier call in the conversation, as it happened: the trigger, the
/// limits named then, and the calls that actually ran. The transcript is a
/// list of these; each brain renders it its own way.
public struct Turn: Equatable, Sendable {
    public var trigger: Trigger
    public var limits: [String]
    public var did: [ToolCall]

    public init(trigger: Trigger, limits: [String] = [], did: [ToolCall] = []) {
        self.trigger = trigger
        self.limits = limits
        self.did = did
    }
}

/// What Boop may do on one call (HARNESS.md §5): the tools offered, in order,
/// and a line for each one past its limit (`say limit: once every 5 min on
/// tap, next in 3 min`). A call to a limited tool is dropped.
public struct Menu: Equatable, Sendable {
    public var tools: [ToolDefinition]
    public var limits: [String]

    public init(tools: [ToolDefinition], limits: [String] = []) {
        self.tools = tools
        self.limits = limits
    }

    public func limited(_ tool: String) -> Bool { limits.contains { $0.hasPrefix(tool + " limit: ") } }

    /// The tools that may run now.
    public var open: [ToolDefinition] { tools.filter { !limited($0.name) } }
}

/// A brain's answer: the calls, in order, and what the brain got back from
/// its model (a model's JSON, Jev's answers) for the debug log (§8).
public struct Decision: Equatable, Sendable {
    public var calls: [ToolCall]
    public var raw: String?

    public init(calls: [ToolCall], raw: String? = nil) {
        self.calls = calls
        self.raw = raw
    }
}

/// A language model: answers the text prompt (HARNESS.md §4) with the answer
/// JSON (§3). The situation becomes the prompt and the JSON becomes calls
/// here, so the model only has to answer.
///
/// A text brain sends `system`, each exchange in `history` and then `user`,
/// in that order and unchanged, so the start of every request repeats the
/// last one's.
public protocol TextBrain: Brain {
    func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition], deadline: Duration) async throws -> String
}

extension TextBrain {
    public func decide(_ situation: Situation, _ menu: Menu, deadline: Duration) async throws -> Decision {
        try await decideAsText(situation, menu, deadline: deadline)
    }

    /// The prompt, the model's answer, then the answer's shape check; a bad
    /// shape drops the whole answer.
    public func decideAsText(_ situation: Situation, _ menu: Menu, deadline: Duration) async throws -> Decision {
        let prompt = Prompt(situation, menu)
        let raw = try await complete(system: prompt.system, history: prompt.history, user: prompt.user, tools: menu.tools,
                                     deadline: deadline)
        switch Answer.check(raw, tools: menu.tools) {
        case .success(let calls): return Decision(calls: calls, raw: raw)
        case .failure(let why): throw BrainError("shape: \(why)", raw: raw)
        }
    }
}

/// A brain that can fill in words (System 2) for a call another brain has
/// already decided on (System 1, Jev): exactly one call to `tool`, or nil.
public protocol Writer: Sendable {
    func write(_ tool: ToolDefinition, _ situation: Situation, deadline: Duration) async throws -> ToolCall?
}

public struct BrainError: Error, Equatable, CustomStringConvertible {
    public var description: String
    /// What the model answered, when it answered something unusable.
    public var raw: String?
    public init(_ description: String, raw: String? = nil) {
        self.description = description
        self.raw = raw
    }

    /// The brain declined to answer (a model's guardrail). Dropped like any
    /// error, but L5 counts it apart from a badly shaped answer.
    public static func refused(_ why: String) -> BrainError { BrainError(refusedPrefix + why) }
    static let refusedPrefix = "refused: "
}

/// The answer format text brains use (HARNESS.md §3):
///
///     {"calls":[{"tool":"say","feeling":"proud","word":"finally"}]}
public enum Answer {
    /// At most this many tool calls in one answer.
    public static let maxCalls = 3

    /// Encodes calls as an answer, arguments sorted by name.
    public static func json(_ calls: [ToolCall]) -> String {
        let items = calls.map { call -> String in
            var fields = ["\"tool\":" + quote(call.name)]
            for (key, value) in call.arguments.sorted(by: { $0.key < $1.key }) {
                switch value {
                case .string(let s): fields.append(quote(key) + ":" + quote(s))
                case .number(let n): fields.append(quote(key) + ":\(n)")
                }
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
        return "{\"calls\":[" + items.joined(separator: ",") + "]}"
    }

    /// A text answer's shape check (HARNESS.md §3 step 5): valid JSON, then
    /// `check(calls:)`. One bad call drops the whole answer.
    public static func check(_ raw: String, tools: [ToolDefinition]) -> Result<[ToolCall], BrainError> {
        guard let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let items = object["calls"] as? [Any]
        else { return .failure(BrainError("not a JSON object with a calls list")) }
        if object.count > 1 { return .failure(BrainError("unexpected keys besides calls")) }
        if items.count > maxCalls { return .failure(BrainError("\(items.count) calls, more than \(maxCalls)")) }
        var calls: [ToolCall] = []
        for item in items {
            guard let fields = item as? [String: Any], let name = fields["tool"] as? String else {
                return .failure(BrainError("a call without a tool name"))
            }
            var arguments: [String: ToolValue] = [:]
            for (key, value) in fields where key != "tool" {
                switch value {
                case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID():
                    guard n.doubleValue == Double(n.intValue) else {
                        return .failure(BrainError("\(name): \(key) isn't a whole number"))
                    }
                    arguments[key] = .number(n.intValue)
                case let s as String:
                    arguments[key] = .string(s)
                case is NSNull:
                    continue // an optional argument left out
                default:
                    return .failure(BrainError("\(name): \(key) isn't text or a number"))
                }
            }
            calls.append(ToolCall(name, arguments))
        }
        if let why = check(calls: calls, tools: tools) { return .failure(BrainError(why)) }
        return .success(calls)
    }

    /// Every brain's calls (HARNESS.md §3 step 5): at most three, only the
    /// tools offered, arguments matching their definitions. Why not, or nil.
    public static func check(calls: [ToolCall], tools: [ToolDefinition]) -> String? {
        if calls.count > maxCalls { return "\(calls.count) calls, more than \(maxCalls)" }
        for call in calls {
            guard let definition = tools.first(where: { $0.name == call.name }) else { return "\(call.name) isn't offered" }
            if let why = definition.check(call.arguments) { return "\(call.name): \(why)" }
        }
        return nil
    }

    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
