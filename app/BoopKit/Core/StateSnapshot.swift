import Foundation

/// The `state` message: the whole picture the device draws (PROTOCOL.md §3).
public struct StateSnapshot: Equatable, Sendable {
    public struct Attention: Equatable, Sendable {
        public var agent: String
        public var project: String
        public var more: Int
    }

    public static let version = 1
    public static let maxThreads = 8
    /// A protocol line is at most 512 bytes (PROTOCOL.md §2).
    public static let maxLine = 512
    /// The device keeps names in 24-byte fields.
    public static let maxNameBytes = 23

    /// `text` cut to at most `bytes` of UTF-8, on a character boundary.
    public static func clip(_ text: String, bytes: Int = maxNameBytes) -> String {
        guard text.utf8.count > bytes else { return text }
        var out = ""
        for ch in text {
            if out.utf8.count + String(ch).utf8.count > bytes { break }
            out.append(ch)
        }
        return out
    }

    /// Drops thread rows from the end until the line fits.
    public mutating func fit() {
        while jsonLine.utf8.count > StateSnapshot.maxLine && !threads.isEmpty {
            threads.removeLast()
        }
    }

    /// Unix seconds.
    public var time: Int64
    public var name: String
    /// `asleep`, `idle` or `working`.
    public var base: String
    public var attn: Attention?
    public var busy: Int
    public var idle: Int
    public var wait: Int
    public var mood: Mood
    /// Minutes of quiet left.
    public var quiet: Int
    public var focus: Bool
    public var vol: Int
    public var night: Bool
    public var level: Int
    public var prog: Int
    public var days: Int
    public var hungry: Int
    /// Agent, project, status (`wait`, `work` or `idle`).
    public var threads: [[String]]

    /// Equal apart from the clock, which changes every second.
    public func sameContent(as other: StateSnapshot?) -> Bool {
        guard var other else { return false }
        other.time = time
        return other == self
    }

    /// One JSON line, keys in the protocol's order.
    public var jsonLine: String {
        var parts: [String] = [
            "\"t\":\"state\"", "\"v\":\(StateSnapshot.version)", "\"time\":\(time)", "\"name\":\(json(name))",
            "\"base\":\(json(base))",
        ]
        if let attn {
            parts.append("\"attn\":{\"agent\":\(json(attn.agent)),\"project\":\(json(attn.project)),\"more\":\(attn.more)}")
        }
        parts += [
            "\"busy\":\(busy)", "\"idle\":\(idle)", "\"wait\":\(wait)",
            "\"mood\":{\"energy\":\(mood.energy),\"pace\":\(mood.pace),\"pitch\":\(mood.pitch)}",
            "\"quiet\":\(quiet)", "\"focus\":\(focus)", "\"vol\":\(vol)", "\"night\":\(night)",
            "\"level\":\(level)", "\"prog\":\(prog)", "\"days\":\(days)", "\"hungry\":\(hungry)",
            "\"threads\":[" + threads.map { "[" + $0.map(json).joined(separator: ",") + "]" }.joined(separator: ",") + "]",
        ]
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func json(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
