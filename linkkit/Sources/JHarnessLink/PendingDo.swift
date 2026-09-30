import JHarness
import LinkKit

extension Link {
    /// How a `do` reads as a JHarness `Pending`'s end by default: `done` is
    /// done; `cut` and `skipped` failed, with the device's why (`cut short:
    /// tap`, `skipped: late`); a failure here failed in its own words (`the
    /// device disconnected`, `no device connected`).
    public static func end(_ outcome: Outcome) -> Pending.End {
        switch outcome {
        case .ended(let ended):
            switch ended.how {
            case .done: .done
            case .cut: .failed("cut short" + (ended.why.map { ": " + $0 } ?? ""))
            case .skipped: .failed("skipped" + (ended.why.map { ": " + $0 } ?? ""))
            }
        case .failed(let failure):
            .failed(failure.description)
        }
    }

    /// `do`, finishing `pending` with how it came out: an output that asks
    /// the device to play something returns `.started(…, pending)`, and
    /// HISTORY shows it in progress until the device says it ended
    /// (jharness/SPEC.md §5.3). `map` makes the outcome an end, `Link.end`
    /// by default; nil leaves `pending` to the app to finish itself later.
    /// Call it on the harness's queue, which must be the link's.
    @discardableResult
    public func `do`(_ name: String, args: JSONObject = [:], play: Wire.Play = .next, ttl: Int = Wire.defaultTTL,
                     by sender: Sender = .rule, now: Int64, pending: Pending,
                     map: @escaping (Outcome) -> Pending.End? = { Link.end($0) }) -> Int? {
        self.do(name, args: args, play: play, ttl: ttl, by: sender, now: now) { outcome in
            if let end = map(outcome) { pending.finish(end) }
        }
    }
}

extension JSON {
    /// The value as JHarness's `JSONValue`, for an event's data. An
    /// object's keys lose their order.
    public var value: JSONValue {
        switch self {
        case .null: .null
        case .bool(let b): .bool(b)
        case .int(let n): .int(Int64(n))
        case .double(let d): .double(d)
        case .string(let s): .string(s)
        case .array(let items): .array(items.map(\.value))
        case .object(let object): .object(object.values)
        }
    }
}

extension JSONObject {
    /// The fields as an event's data.
    public var values: [String: JSONValue] {
        Dictionary(fields.map { ($0.key, $0.value.value) }, uniquingKeysWith: { $1 })
    }
}
