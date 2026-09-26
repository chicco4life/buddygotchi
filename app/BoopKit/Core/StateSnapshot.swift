import Foundation

/// The `state` message: the whole picture the device draws (PROTOCOL.md §3).
public struct StateSnapshot: Equatable, Sendable {
    public struct Attention: Equatable, Sendable {
        public var agent: String
        public var project: String
        public var more: Int

        public init(agent: String, project: String, more: Int) {
            self.agent = agent
            self.project = project
            self.more = more
        }
    }

    public static let version = 1
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

    /// Unix seconds.
    public var time: Int64
    public var name: String
    /// `asleep`, `idle` or `working`.
    public var base: String
    public var attn: Attention?
    public var busy: Int
    public var idle: Int
    public var wait: Int
    /// Minutes of quiet left.
    public var quiet: Int
    public var vol: Int

    public init(time: Int64, name: String, base: String, attn: Attention?, busy: Int, idle: Int, wait: Int,
                quiet: Int, vol: Int) {
        self.time = time
        self.name = name
        self.base = base
        self.attn = attn
        self.busy = busy
        self.idle = idle
        self.wait = wait
        self.quiet = quiet
        self.vol = vol
    }

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
        parts += ["\"busy\":\(busy)", "\"idle\":\(idle)", "\"wait\":\(wait)", "\"quiet\":\(quiet)", "\"vol\":\(vol)"]
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func json(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
