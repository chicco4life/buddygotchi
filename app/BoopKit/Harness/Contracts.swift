import Foundation

/// A JSON value: a raw event's `data` and a view event's facts
/// (harness/EVENTS.md). The harness logs them but never reads them.
public enum JSONValue: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    case string(String)
    case int(Int64)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
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
        case .bool(let b): b
        case .array(let a): a.map(\.foundation)
        case .object(let o): o.mapValues(\.foundation)
        case .null: NSNull()
        }
    }

    /// A value from what `JSONSerialization` read. Fractions are cut to
    /// whole numbers: nothing Boop writes has any.
    public init(foundation value: Any?) {
        switch value {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .int(n.int64Value)
        case let a as [Any]: self = .array(a.map { JSONValue(foundation: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(foundation: $0) })
        default: self = .null
        }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int64? { if case .int(let n) = self { n } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
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
    /// Unique across all actions: `react`, `say.feeling`.
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
/// A started one finishes later: HISTORY shows it in progress until its
/// `pending` ends (harness/HARNESS.md §4).
public struct ActionResult: Equatable, Sendable {
    public let ok: Bool
    public let message: String
    /// How a started action tells the harness it ended; nil for one that
    /// finished when `run` returned.
    public let pending: Pending?

    public init(ok: Bool, message: String) {
        self.init(ok: ok, message: message, pending: nil)
    }

    init(ok: Bool, message: String, pending: Pending?) {
        self.ok = ok
        self.message = message
        self.pending = pending
    }

    public static func done(_ message: String) -> ActionResult { ActionResult(ok: true, message: message) }
    public static func failed(_ why: String) -> ActionResult { ActionResult(ok: false, message: why) }
    /// Started, and ends when `pending` is finished.
    public static func started(_ message: String, _ pending: Pending) -> ActionResult {
        ActionResult(ok: true, message: message, pending: pending)
    }

    /// The same handle, not just an equal one.
    public static func == (a: ActionResult, b: ActionResult) -> Bool {
        a.ok == b.ok && a.message == b.message && a.pending === b.pending
    }
}

/// A started action's end, still to come (harness/HARNESS.md §4): the
/// action, or whatever it hands this to, finishes it once it knows how
/// things went. Only the first `finish` counts, and one that comes before
/// the harness has recorded the result is kept until it has. Touched only
/// on the harness's queue.
public final class Pending: @unchecked Sendable {
    public enum End: Equatable, Sendable {
        case done
        /// It never happened, and why.
        case failed(String)
    }

    private var end: End?
    private var deliver: ((End) -> Void)?
    private var finished = false
    /// How it ended, once it has; nil until then.
    public private(set) var ended: End?

    public init() {}

    public func finish(_ end: End) {
        guard !finished else { return }
        finished = true
        ended = end
        if let deliver {
            self.deliver = nil
            deliver(end)
        } else {
            self.end = end
        }
    }

    /// The harness's: where the end goes. One that came first goes at once.
    func bind(_ deliver: @escaping (End) -> Void) {
        if let end {
            self.end = nil
            deliver(end)
        } else if !finished {
            self.deliver = deliver
        }
    }
}

/// Something Boop can do when the brain wakes. It declares its questions,
/// reads Jev's answers to them, and reports what it did, or what it
/// started. Its body can call anything; the harness asks, records and
/// places the result.
public protocol Action: AnyObject {
    var name: String { get }
    /// Asked on every pass but one whose event says this action sits it
    /// out. Built fresh, so they can depend on live state.
    func questions() -> [Question]
    /// Jev's answers to this action's own questions. Nil means "do nothing".
    /// Called on the harness's queue; slow work is handed off.
    func run(_ answers: Answers) -> ActionResult?
}
