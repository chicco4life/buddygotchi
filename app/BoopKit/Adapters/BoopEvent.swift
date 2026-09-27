import Foundation

/// The agents Boop listens to.
public enum Agent: String, Sendable {
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

/// The common event every adapter produces (ADAPTERS.md §1).
public struct BoopEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sessionStart = "session_start"
        case turnStart = "turn_start"
        case needsYou = "needs_you"
        case activity
        case turnEnd = "turn_end"
        case turnFailed = "turn_failed"
        /// The turn is over without finishing: you interrupted it, or the
        /// agent has sat at its prompt for a while. No reaction.
        case turnStopped = "turn_stopped"
        /// A Claude subagent finished (`SubagentStop`). It answers only that
        /// subagent's request, and isn't activity: it never sets a session
        /// working (ADAPTERS.md §4).
        case subagentEnd = "subagent_end"
        case sessionEnd = "session_end"
    }

    /// Small and event-specific. Never prompt text, commands or file contents.
    public struct Detail: Equatable, Sendable {
        public var tool: String?
        public var topic: String?
        public var error: String?
        /// Whether the tool call failed, where the agent says: Claude's
        /// `PostToolUse` (false) and `PostToolUseFailure` (true), but not a
        /// call you interrupted. Nil when unknown.
        public var failed: Bool?
        /// A failed tool call's error class: `exit_code`, `timeout`, `denied`
        /// or `other` (harness/EVENTS.md §4).
        public var toolError: String?
        /// The tool call's ID, pairing its `PreToolUse` with its result.
        public var toolUseID: String?
        /// The tool call has finished: `PostToolUse` or `PostToolUseFailure`.
        public var done = false
        /// Claude's `Notification`, by its type: an asking one
        /// (`permission_prompt`, `elicitation_dialog`) repeats a request
        /// the agent's own hook makes (`PermissionRequest`, `Elicitation`),
        /// and may arrive before or after it; `idle_prompt` is its idle
        /// notice. Nil for any other hook.
        public var notice: String?

        public init(tool: String? = nil, topic: String? = nil, error: String? = nil, failed: Bool? = nil,
                    toolError: String? = nil, toolUseID: String? = nil) {
            self.tool = tool
            self.topic = topic
            self.error = error
            self.failed = failed
            self.toolError = toolError
            self.toolUseID = toolUseID
        }
    }

    public var agent: Agent
    public var session: String
    /// The Claude subagent the event came from, which shares its parent's
    /// session; nil for the main agent and for Codex.
    public var subagent: String?
    /// That subagent's type, e.g. `Explore`.
    public var subagentType: String?
    public var project: String
    /// The worktree folder or git branch the session works in, cleaned to a
    /// name (harness/EVENTS.md §3); nil on the default branch or outside git.
    public var workspace: String?
    public var event: Kind
    public var detail: Detail
    /// Milliseconds.
    public var ts: Int64

    public init(agent: Agent, session: String, subagent: String? = nil, subagentType: String? = nil,
                project: String, workspace: String? = nil, event: Kind, detail: Detail = Detail(), ts: Int64) {
        self.agent = agent
        self.session = session
        self.subagent = subagent
        self.subagentType = subagentType
        self.project = project
        self.workspace = workspace
        self.event = event
        self.detail = detail
        self.ts = ts
    }

    /// The event on one line, for debug mode: `activity landing · tool Bash, topic tests`.
    public var summary: String {
        let parts = [workspace.map { "workspace \($0)" }, detail.tool.map { "tool \($0)" }, detail.topic.map { "topic \($0)" },
                     detail.failed == true ? "failed" : nil, detail.toolError.map { "tool error \($0)" },
                     detail.error.map { "error \($0)" }, detail.notice.map { "notice \($0)" },
                     subagent.map { "subagent \($0)" }].compactMap { $0 }
        return "\(event.rawValue) \(project)" + (parts.isEmpty ? "" : " · " + parts.joined(separator: ", "))
    }

    /// The event as one JSON line, in the shape of ADAPTERS.md §1.
    public var jsonLine: String {
        var detailObject: [String: Any] = [:]
        if let tool = detail.tool { detailObject["tool"] = tool }
        if let topic = detail.topic { detailObject["topic"] = topic }
        if let error = detail.error { detailObject["error"] = error }
        if let failed = detail.failed { detailObject["failed"] = failed }
        if let toolError = detail.toolError { detailObject["tool_error"] = toolError }
        if let toolUseID = detail.toolUseID { detailObject["tool_use_id"] = toolUseID }
        if let notice = detail.notice { detailObject["notice"] = notice }
        var object: [String: Any] = [
            "agent": agent.rawValue, "session": session, "project": project,
            "event": event.rawValue, "detail": detailObject, "ts": ts,
        ]
        if let subagent { object["subagent"] = subagent }
        if let subagentType { object["subagent_type"] = subagentType }
        if let workspace { object["workspace"] = workspace }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
