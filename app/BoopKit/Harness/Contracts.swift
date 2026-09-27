import Foundation

/// A JSON value, for what the harness logs but never reads: an event's
/// facts (harness/HARNESS.md §3).
public enum JSONValue: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }

    /// An optional string, as a value or `null`.
    public static func of(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }

    /// Plain Foundation objects, for `JSONSerialization`.
    public var foundation: Any {
        switch self {
        case .string(let s): s
        case .int(let n): NSNumber(value: n)
        case .double(let d): NSNumber(value: d)
        case .bool(let b): NSNumber(value: b)
        case .object(let o): o.mapValues(\.foundation)
        case .null: NSNull()
        }
    }
}
