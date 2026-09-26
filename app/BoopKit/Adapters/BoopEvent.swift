import Foundation

/// The agents Boop listens to.
public enum Agent: String, Sendable, CaseIterable {
    case claudeCode = "claude_code"
    case codex

    /// The short name used on the device and in input lines.
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

/// The common event every adapter produces (ARCHITECTURE.md §5).
public struct BoopEvent: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case sessionStart = "session_start"
        case turnStart = "turn_start"
        case needsYou = "needs_you"
        case activity
        case turnEnd = "turn_end"
        case turnFailed = "turn_failed"
        case sessionEnd = "session_end"
    }

    /// Small and event-specific. Never prompt text, commands or file contents.
    public struct Detail: Equatable, Sendable {
        public var durationS: Int?
        public var tool: String?
        public var topic: String?
        public var error: String?

        public init(durationS: Int? = nil, tool: String? = nil, topic: String? = nil, error: String? = nil) {
            self.durationS = durationS
            self.tool = tool
            self.topic = topic
            self.error = error
        }
    }

    public var agent: Agent
    public var session: String
    public var project: String
    public var event: Kind
    public var detail: Detail
    /// Milliseconds.
    public var ts: Int64

    public init(agent: Agent, session: String, project: String, event: Kind, detail: Detail = Detail(), ts: Int64) {
        self.agent = agent
        self.session = session
        self.project = project
        self.event = event
        self.detail = detail
        self.ts = ts
    }

    /// The event as one JSON line, in the shape of ARCHITECTURE.md §5.
    public var jsonLine: String {
        var detailObject: [String: Any] = [:]
        if let durationS = detail.durationS { detailObject["duration_s"] = durationS }
        if let tool = detail.tool { detailObject["tool"] = tool }
        if let topic = detail.topic { detailObject["topic"] = topic }
        if let error = detail.error { detailObject["error"] = error }
        let object: [String: Any] = [
            "agent": agent.rawValue, "session": session, "project": project,
            "event": event.rawValue, "detail": detailObject, "ts": ts,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
