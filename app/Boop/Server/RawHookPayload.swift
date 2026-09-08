import Foundation

/// Ephemeral input. Deliberately neither Codable nor printable.
struct RawHookPayload: Sendable {
    enum Kind: String, Sendable { case sessionStart, sessionEnd, turnStart, toolCall, toolResult, needsYou, turnEnd }
    var source: String
    var sessionId: String
    var kind: Kind
    var toolName: String
    var toolInput: String?
    var exitStatus: Int?
    var errorClass: String?
    var outputHead: String?
    var outputTail: String?
    var promptText: String?
    var closingMessage: String?
    var cwd: String?
    var timestamp: Double
    var closingOnly: Bool = false
    var callId: String?
    var eventName: String = ""

    static func claudeCode(_ data: Data, at: Double) throws -> Self? { try parse(data, source: "claude-code", at: at) }
    static func codex(_ data: Data, at: Double) throws -> Self? { try parse(data, source: "codex", at: at) }
    static func cursor(_ data: Data, at: Double) throws -> Self? { try parse(data, source: "cursor", at: at) }
    static func parse(_ data: Data, source: String, at: Double) throws -> Self? {
        guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func text(_ v: Any?) -> String? {
            guard let v, !(v is NSNull) else { return nil }
            if let s = v as? String { return s }
            return (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) }
        }
        let event = d["hook_event_name"] as? String ?? d["hookEventName"] as? String ?? d["event_name"] as? String ?? ""
        let kind: Kind
        switch event {
        case "SessionStart", "sessionStart": kind = .sessionStart
        case "SessionEnd", "sessionEnd": kind = .sessionEnd
        case "UserPromptSubmit", "beforeSubmitPrompt": kind = .turnStart
        case "PreToolUse", "preToolUse", "beforeShellExecution", "beforeMCPExecution": kind = .toolCall
        case "PostToolUse", "PostToolUseFailure", "postToolUse", "postToolUseFailure", "afterShellExecution", "afterMCPExecution", "afterFileEdit": kind = .toolResult
        case "PermissionRequest", "Elicitation": kind = .needsYou
        case "Stop", "StopFailure", "stop", "afterAgentResponse": kind = .turnEnd
        default: return nil
        }
        let response = d["tool_response"] ?? d["tool_output"] ?? d["output"]
        let object = response as? [String: Any] ?? [:]
        let output = text(response)
        let tool = d["tool_name"] as? String ?? d["toolName"] as? String ?? (d["tool"] as? [String: Any])?["name"] as? String ?? (d["command"] != nil || event == "afterShellExecution" ? "Shell" : event == "afterFileEdit" ? "Edit" : "")
        let input = text(d["tool_input"] ?? d["input"] ?? d["command"] ?? (event == "afterFileEdit" ? ["file_path": d["file_path"] as? String ?? d["path"] as? String ?? ""] : nil))
        let error = (d["status"] as? String == "error" ? "tool_error" : nil) ?? d["error_class"] as? String ?? d["error"] as? String ?? object["error_class"] as? String
        return Self(source: source, sessionId: d["session_id"] as? String ?? d["conversation_id"] as? String ?? "\(source)_default", kind: kind, toolName: tool, toolInput: input,
                    exitStatus: d["exit_status"] as? Int ?? d["exit_code"] as? Int ?? object["exit_code"] as? Int ?? object["exit_status"] as? Int,
                    errorClass: error ?? (event.lowercased().contains("failure") ? "tool_error" : nil),
                    outputHead: (d["output_head"] as? String ?? output).map { capUTF8($0, 1024) },
                    outputTail: (d["output_tail"] as? String ?? output.map { String(decoding: $0.utf8.suffix(1024), as: UTF8.self) }).map { capUTF8($0, 1024) },
                    promptText: kind == .turnStart ? text(d["prompt"] ?? d["prompt_text"]) : nil,
                    closingMessage: kind == .turnEnd ? text(d["last_assistant_message"] ?? d["text"] ?? d["closing_message"]).map { capUTF8($0, 2048) } : nil,
                    cwd: d["cwd"] as? String ?? (d["workspace_roots"] as? [String])?.first, timestamp: at, closingOnly: event == "afterAgentResponse", callId: d["tool_use_id"] as? String ?? d["tool_call_id"] as? String, eventName: event)
    }
}

func capUTF8(_ text: String, _ bytes: Int) -> String {
    var result = ""
    var count = 0
    for c in text { let n = String(c).utf8.count; if count + n > bytes { break }; result.append(c); count += n }
    return result
}
