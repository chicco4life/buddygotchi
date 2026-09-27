import Foundation

/// A JSON value, for what the harness logs but never reads: an event's
/// facts (harness/HARNESS.md §3).
public enum JSONValue: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case int(Int64)
    case object([String: JSONValue])
    case null

    public init(stringLiteral value: String) { self = .string(value) }
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
        case .object(let o): o.mapValues(\.foundation)
        case .null: NSNull()
        }
    }
}

// MARK: - Actions: the output contract (harness/HARNESS.md §4)

/// One option of a question, with its meaning: Jev's criterion.
public struct Option: Equatable, Sendable {
    public let name: String
    public let what: String
    /// What it isn't, when two options are easily confused.
    public let notFor: String?

    public init(_ name: String, _ what: String, notFor: String? = nil) {
        self.name = name
        self.what = what
        self.notFor = notFor
    }
}

/// A multiple-choice question an action asks Jev.
public struct Question: Equatable, Sendable {
    /// Unique across all actions: `react`, `word.feeling`.
    public let key: String
    public let text: String
    /// The part of the state it's about: `the NOW section`.
    public let about: String
    /// What to judge it by: `the PERSONALITY and MOOD sections, …`.
    public let judgeBy: String
    public let options: [Option]

    public init(key: String, text: String, about: String, judgeBy: String, options: [Option]) {
        self.key = key
        self.text = text
        self.about = about
        self.judgeBy = judgeBy
        self.options = options
    }
}

/// Jev's answer to one question: its pick, and every option's probability.
public struct Answer: Equatable, Sendable {
    public let choice: String
    public let probabilities: [String: Double]

    public init(choice: String, probabilities: [String: Double] = [:]) {
        self.choice = choice
        self.probabilities = probabilities
    }

    /// The pick's probability.
    public var p: Double { probabilities[choice] ?? 0 }
}

/// Answers by question key.
public typealias Answers = [String: Answer]

/// What an action did: its line in HISTORY when `ok`, the reason when not.
public struct ActionResult: Equatable, Sendable {
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }

    public static func done(_ message: String) -> ActionResult { ActionResult(ok: true, message: message) }
    public static func failed(_ why: String) -> ActionResult { ActionResult(ok: false, message: why) }
}

/// Something Boop can do when the brain wakes. It declares its questions,
/// reads Jev's answers to them, and reports what it did. Its body can call
/// anything; the harness asks, records and places the result.
public protocol Action: AnyObject {
    var name: String { get }
    /// Asked on every pass. Built fresh, so they can depend on live state.
    func questions() -> [Question]
    /// Jev's answers to this action's own questions. Nil means "do nothing".
    /// Called on the harness's queue; slow work is handed off.
    func run(_ answers: Answers) -> ActionResult?
}
