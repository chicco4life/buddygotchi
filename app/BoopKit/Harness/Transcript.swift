import Foundation

/// Boop's record of what happened and what it did (harness/HARNESS.md §5):
/// one append-only list of typed entries. The state's HISTORY and NOW are
/// built from it for each pass (`StateText`); `debug.jsonl` logs every entry.
/// Nothing in it is ever changed. Kept in memory only, touched only on the
/// harness's queue.
public final class Transcript: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public let seq: Int
        public let receivedAtMs: Int64
        public let body: Body
    }

    public enum Body: Equatable, Sendable {
        case event(Event)
        case pass(Pass)
        case action(ActionRecord)
    }

    /// What the brain was asked and answered for one event.
    public struct Pass: Equatable, Sendable {
        public var forSeq: Int
        public var answers: Answers
        /// Why nothing ran: Jev failed, was late, or had no answer.
        public var dropped: String?
        public var latencyMs: Int
    }

    /// What one action reported.
    public struct ActionRecord: Equatable, Sendable {
        public var forSeq: Int
        public var name: String
        public var result: ActionResult
        public var latencyMs: Int
    }

    /// Past this many entries the oldest are let go; nothing is summarised.
    public static let limit = 1000

    public private(set) var entries: [Entry] = []
    var nextSeq = 1

    public init() {}

    @discardableResult
    public func append(_ body: Body, at ms: Int64) -> Entry {
        let entry = Entry(seq: nextSeq, receivedAtMs: ms, body: body)
        nextSeq += 1
        entries.append(entry)
        if entries.count > Transcript.limit { entries.removeFirst(entries.count - Transcript.limit) }
        return entry
    }

    public func entry(_ seq: Int) -> Entry? { entries.first { $0.seq == seq } }

    /// The entry as one JSON line for `debug.jsonl` (§9).
    public static func json(_ entry: Entry, extra: [String: Any] = [:]) -> String {
        var o: [String: Any] = ["seq": entry.seq, "received_at_ms": entry.receivedAtMs]
        switch entry.body {
        case .event(let e):
            o["event"] = e.json
        case .pass(let p):
            var pass: [String: Any] = ["for": p.forSeq, "latency_ms": p.latencyMs, "dropped": p.dropped ?? NSNull(),
                                       "answers": Transcript.json(p.answers)]
            for (k, v) in extra { pass[k] = v }
            o["pass"] = pass
        case .action(let a):
            o["action"] = ["for": a.forSeq, "name": a.name, "ok": a.result.ok, "message": a.result.message,
                           "latency_ms": a.latencyMs] as [String: Any]
        }
        let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func json(_ answers: Answers) -> [String: Any] {
        answers.mapValues { a in
            ["choice": a.choice, "p": a.probabilities.mapValues { ($0 * 1000).rounded() / 1000 }] as [String: Any]
        }
    }
}
