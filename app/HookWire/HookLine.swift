import Foundation

/// The one line `boop-hook` sends to the app: only the fields ADAPTERS.md §3
/// keeps. Prompt text, tool input and file contents never get this far; the
/// topic tag is worked out from the tool input in memory, then the input is
/// dropped with the rest of the payload.
public struct HookLine: Equatable, Sendable {
    /// `claude` or `codex`, from `boop-hook <agent>`.
    public var agent: String
    /// The agent's hook name, e.g. `PreToolUse`.
    public var hook: String
    public var session: String
    public var cwd: String?
    public var tool: String?
    public var topic: String?
    /// `StopFailure`'s error class, e.g. `rate_limit`.
    public var error: String?
    /// `Notification`'s type, e.g. `permission_prompt`.
    public var kind: String?
    /// `PostToolUseFailure` because you interrupted the call.
    public var interrupt: Bool
    /// Claude's `agent_id`: which subagent the hook fired in. Claude gives a
    /// subagent's hooks the parent's session, so this tells siblings apart;
    /// nil for the main agent.
    public var agentID: String?
    /// When the hook ran, in milliseconds.
    public var ts: Int64

    public init(agent: String, hook: String, session: String, cwd: String? = nil, tool: String? = nil,
                topic: String? = nil, error: String? = nil, kind: String? = nil, interrupt: Bool = false,
                agentID: String? = nil, ts: Int64) {
        self.agent = agent
        self.hook = hook
        self.session = session
        self.cwd = cwd
        self.tool = tool
        self.topic = topic
        self.error = error
        self.kind = kind
        self.interrupt = interrupt
        self.agentID = agentID
        self.ts = ts
    }

    /// Longest value kept for any field, so a strange payload can't make the
    /// line large.
    static let maxField = 200

    /// Picks the kept fields out of a raw hook payload. Returns nil when the
    /// payload has no hook name or session.
    public static func extract(agent: String, payload: Data, ts: Int64) -> HookLine? {
        if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            return extract(agent: agent, json: object, ts: ts)
        }
        return salvage(agent: agent, payload: payload, ts: ts)
    }

    public static func extract(agent: String, json: [String: Any], ts: Int64) -> HookLine? {
        guard let hook = string(json["hook_event_name"]) ?? string(json["hookEventName"]),
              let session = string(json["session_id"]) ?? string(json["thread_id"]) ?? string(json["conversation_id"])
        else { return nil }
        var line = HookLine(agent: agent, hook: hook, session: session, cwd: string(json["cwd"]),
                            agentID: string(json["agent_id"]), ts: ts)
        switch hook {
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest":
            line.tool = string(json["tool_name"])
            if hook != "PermissionRequest" {
                line.topic = Topic.tag(tool: line.tool, input: json["tool_input"])
            }
            line.interrupt = hook == "PostToolUseFailure" && json["is_interrupt"] as? Bool == true
        case "StopFailure":
            line.error = string(json["error"]) ?? string(json["error_type"])
        case "Notification":
            line.kind = string(json["notification_type"])
        default:
            break
        }
        return line
    }

    /// A payload over the 256 KB cap is cut off and won't parse. The fields we
    /// need come early, so pick them out of the prefix; the topic is lost.
    /// The cut can land inside a character, so bad bytes are replaced
    /// rather than losing the line.
    static func salvage(agent: String, payload: Data, ts: Int64) -> HookLine? {
        let text = String(decoding: payload, as: UTF8.self)
        func field(_ name: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\"\(name)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.){0,400})\"")
            else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let value = Range(match.range(at: 1), in: text) else { return nil }
            return string(String(text[value]))
        }
        guard let hook = field("hook_event_name"), let session = field("session_id") else { return nil }
        var line = HookLine(agent: agent, hook: hook, session: session, cwd: field("cwd"),
                            agentID: field("agent_id"), ts: ts)
        if ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"].contains(hook) {
            line.tool = field("tool_name")
        }
        return line
    }

    static func string(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s.count > maxField ? String(s.prefix(maxField)) : s
    }

    // MARK: Wire form

    public func encoded() -> Data {
        var object: [String: Any] = ["agent": agent, "hook": hook, "session": session, "ts": ts]
        if let cwd { object["cwd"] = cwd }
        if let tool { object["tool"] = tool }
        if let topic { object["topic"] = topic }
        if let error { object["error"] = error }
        if let kind { object["kind"] = kind }
        if interrupt { object["interrupt"] = true }
        if let agentID { object["agent_id"] = agentID }
        // No `.sortedKeys`: nothing reads the order, and sorting loads
        // locale-aware comparison, about half of a hook's few milliseconds.
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) -> HookLine? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = string(object["agent"]), let hook = string(object["hook"]),
              let session = string(object["session"]) else { return nil }
        let ts = (object["ts"] as? NSNumber)?.int64Value ?? 0
        return HookLine(agent: agent, hook: hook, session: session, cwd: string(object["cwd"]),
                        tool: string(object["tool"]), topic: string(object["topic"]),
                        error: string(object["error"]), kind: string(object["kind"]),
                        interrupt: object["interrupt"] as? Bool == true, agentID: string(object["agent_id"]), ts: ts)
    }
}
