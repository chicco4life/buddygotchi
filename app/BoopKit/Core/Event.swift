import Foundation

/// The agents Boop listens to.
public enum Agent: String, Sendable {
    case claudeCode = "claude_code"
    case codex

    /// The short name used on the device, in lines and as an event's
    /// `source`.
    public var short: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        }
    }

    /// The name `boop-hook` is called with.
    public init?(hookName: String) {
        switch hookName {
        case "claude", "claude_code": self = .claudeCode
        case "codex": self = .codex
        default: return nil
        }
    }
}

/// One thing that happened, as the transcript keeps it (harness/EVENTS.md
/// §1): the same metadata for every event, and `data` for what only its
/// type has. Agents' hooks, the device, the clock and Boop's own actions
/// all arrive as these. Nothing reads meaning into one but the core and
/// the view.
public struct Event: Equatable, Sendable {
    /// Where it came from.
    public enum Source: String, Sendable {
        case claude, codex, device, clock, boop
    }

    /// What it is, whatever agent it came from (EVENTS.md §2).
    public enum Kind: String, Sendable, CaseIterable {
        case session, turn, tool, subagent, poke, heartbeat, action
    }

    /// Where in its life a thing with a start and an end is: a tool call
    /// can also `wait` on you. Nil for one that just happens.
    public enum Phase: String, Sendable {
        case start, wait, end
    }

    /// Its place in the transcript, counting on across days and launches;
    /// 0 until it's recorded.
    public var seq: Int
    /// When it happened, in unix milliseconds.
    public var ts: Int64
    public var source: Source
    public var type: Kind
    public var phase: Phase?
    /// The source's own name for it: `PreToolUse`, `Interrupt`, `input`,
    /// an action's name.
    public var specificType: String
    /// The agent's session; for Boop's action about a session, that one.
    public var session: String?
    /// The Claude subagent it came from, by `agent_id`.
    public var subagent: String?
    public var cwd: String?
    /// What only this type has (EVENTS.md §2).
    public var data: [String: JSONValue]

    public init(seq: Int = 0, ts: Int64, source: Source, type: Kind, phase: Phase? = nil, specificType: String,
                session: String? = nil, subagent: String? = nil, cwd: String? = nil, data: [String: JSONValue] = [:]) {
        self.seq = seq
        self.ts = ts
        self.source = source
        self.type = type
        self.phase = phase
        self.specificType = specificType
        self.session = session
        self.subagent = subagent
        self.cwd = cwd
        self.data = data
    }

    /// The agent it came from, for an agent's event.
    public var agent: Agent? {
        switch source {
        case .claude: .claudeCode
        case .codex: .codex
        default: nil
        }
    }

    public subscript(_ key: String) -> JSONValue? { data[key] }

    /// The source for an agent's events.
    public static func source(_ agent: Agent) -> Source {
        agent == .claudeCode ? .claude : .codex
    }

    // MARK: The transcript's line

    /// The event as one JSON line, metadata first in a fixed order, then
    /// `data` with its keys sorted.
    public var jsonLine: String {
        var parts = ["\"seq\":\(seq)", "\"ts\":\(ts)", "\"source\":\(Event.quote(source.rawValue))",
                     "\"type\":\(Event.quote(type.rawValue))"]
        if let phase { parts.append("\"phase\":\(Event.quote(phase.rawValue))") }
        parts.append("\"specific_type\":\(Event.quote(specificType))")
        if let session { parts.append("\"session\":\(Event.quote(session))") }
        if let subagent { parts.append("\"subagent\":\(Event.quote(subagent))") }
        if let cwd { parts.append("\"cwd\":\(Event.quote(cwd))") }
        parts.append("\"data\":" + Event.encode(data.mapValues(\.foundation)))
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// The event a transcript line holds, or nil for a line that isn't one.
    public init?(jsonLine line: some StringProtocol) {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        self.init(json: o)
    }

    public init?(json o: [String: Any]) {
        guard let seq = (o["seq"] as? NSNumber)?.intValue, let ts = (o["ts"] as? NSNumber)?.int64Value,
              let source = (o["source"] as? String).flatMap(Source.init(rawValue:)),
              let type = (o["type"] as? String).flatMap(Kind.init(rawValue:)),
              let specific = o["specific_type"] as? String else { return nil }
        let data = (o["data"] as? [String: Any] ?? [:]).mapValues { JSONValue(foundation: $0) }
        self.init(seq: seq, ts: ts, source: source, type: type, phase: (o["phase"] as? String).flatMap(Phase.init(rawValue:)),
                  specificType: specific, session: o["session"] as? String, subagent: o["subagent"] as? String,
                  cwd: o["cwd"] as? String, data: data)
    }

    /// `12 tool end PostToolUse claude s1 · tool Bash, failed true`, for
    /// debug mode and replays.
    public var summary: String {
        let what = [type.rawValue, phase?.rawValue, specificType, source.rawValue, session].compactMap { $0 }
        let facts = data.keys.sorted().compactMap { key -> String? in
            guard let value = data[key] else { return nil }
            switch value {
            case .string(let s): return "\(key) \(s.count > 60 ? String(s.prefix(60)) + "…" : s)"
            case .int(let n): return "\(key) \(n)"
            case .bool(let b): return "\(key) \(b)"
            default: return nil
            }
        }
        return what.joined(separator: " ") + (facts.isEmpty ? "" : " · " + facts.joined(separator: ", "))
    }

    static func quote(_ s: String) -> String { encode([s]).dropFirst().dropLast().description }

    static func encode(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Numbers named, so no brain has to compare them (EVENTS.md §5).
public enum Band {
    /// A turn's length or a tool call's time, as the moods read it: short
    /// under a minute, long under 5 minutes, very long past that.
    public static func length(ms: Int64) -> String {
        ms < 60_000 ? "short" : ms < 5 * 60_000 ? "long" : "very long"
    }
}
