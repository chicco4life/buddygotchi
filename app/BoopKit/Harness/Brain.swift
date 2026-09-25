import Foundation

/// A model behind the harness (HARNESS.md §7). Every brain gets the same
/// prompt and tools and answers with the same JSON:
///
///     {"calls":[{"tool":"say","feeling":"proud","word":"finally"}]}
///
/// An empty `calls` list means staying quiet. The harness checks the shape;
/// the brain only has to answer.
public protocol Brain: Sendable {
    /// e.g. `apple:26.4`, `cloud:<model>@<version>`, `rules@1`.
    var id: String { get }
    /// The raw answer. May throw; the harness drops the call and logs why.
    func complete(system: String, user: String, tools: [ToolDefinition], deadline: Duration) async throws -> String
}

public struct BrainError: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }

    /// The brain declined to answer (a model's guardrail). Dropped like any
    /// error, but L5 counts it apart from a badly shaped answer.
    public static func refused(_ why: String) -> BrainError { BrainError(refusedPrefix + why) }
    static let refusedPrefix = "refused: "
}

/// The answer format every brain uses.
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

    /// The shape check (HARNESS.md §3 step 5): valid JSON, at most three
    /// calls, only the tools offered, arguments matching their definitions.
    /// One bad call drops the whole answer.
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
            guard let definition = tools.first(where: { $0.name == name }) else {
                return .failure(BrainError("\(name) isn't offered"))
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
            if let why = definition.check(arguments) { return .failure(BrainError("\(name): \(why)")) }
            calls.append(ToolCall(name, arguments))
        }
        return .success(calls)
    }

    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
