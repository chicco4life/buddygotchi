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
    var displayHint: String = ""

    static func parse(_ data: Data, source: String, at: Double) throws -> Self? {
        let body = try JSONDecoder().decode(HookEventBody.self, from: data)
        let event = body.effectiveEventName ?? ""
        let kind: Kind
        switch event {
        case "SessionStart", "sessionStart": kind = .sessionStart
        case "SessionEnd", "sessionEnd": kind = .sessionEnd
        case "UserPromptSubmit", "beforeSubmitPrompt": kind = .turnStart
        case "PreToolUse", "preToolUse", "beforeShellExecution", "beforeMCPExecution", "afterFileEdit": kind = .toolCall
        case "PostToolUse", "PostToolUseFailure", "postToolUse", "postToolUseFailure", "afterShellExecution", "afterMCPExecution": kind = .toolResult
        case "PermissionRequest", "Elicitation": kind = .needsYou
        case "Stop", "StopFailure", "stop", "afterAgentResponse": kind = .turnEnd
        default: return nil
        }
        let response = body.tool_response ?? body.tool_output ?? body.output
        // v6 transport retains response JSON as capped text; v5 supplied top-level status.
        let cappedObject = body.output_head.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(HookJSON.self, from: $0) }?.object
        let object = response?.object ?? cappedObject ?? [:]
        let output = response?.text
        let tool = body.effectiveToolName ?? (event == "afterShellExecution" ? "Shell" : event == "afterFileEdit" ? "Edit" : "")
        let input = body.effectiveInputText ?? (event == "afterFileEdit" ? HookJSON.object(["file_path": .string(body.file_path ?? body.path ?? "")]).text : nil)
        let error = body.error_class ?? body.error ?? object["error_class"]?.text ?? (body.status == "error" ? "tool_error" : nil)
        return Self(source: source, sessionId: body.effectiveSessionId ?? "\(source)_\(stableHashCwd(body.effectiveCwd))", kind: kind, toolName: tool, toolInput: input,
                    exitStatus: body.exit_status ?? body.exit_code ?? object["exit_code"]?.integer ?? object["exit_status"]?.integer ?? cappedExitStatus(head: body.output_head, tail: body.output_tail),
                    errorClass: error ?? (event.lowercased().contains("failure") ? "tool_error" : nil),
                    outputHead: (body.output_head ?? output).map { $0.prefix(utf8Bytes: 1024) },
                    outputTail: (body.output_tail ?? output.map { String(decoding: $0.utf8.suffix(1024), as: UTF8.self) }).map { $0.prefix(utf8Bytes: 1024) },
                    promptText: kind == .turnStart ? (body.prompt ?? body.prompt_text)?.text.map { $0.prefix(utf8Bytes: 2048) } : nil,
                    closingMessage: kind == .turnEnd ? (body.last_assistant_message ?? body.text ?? body.closing_message)?.text.map { $0.prefix(utf8Bytes: 2048) } : nil,
                    cwd: body.effectiveCwd, timestamp: at, closingOnly: event == "afterAgentResponse", callId: body.tool_use_id ?? body.tool_call_id, eventName: event, displayHint: safeDisplayHint(body, tool: tool))
    }
}

// Preserve authored descriptions while keeping raw command/path fallbacks out of UI history.
private func safeDisplayHint(_ body: HookEventBody, tool: String) -> String {
    if body.effectiveEventName == "PermissionRequest" {
        return approvalGloss(from: body, fallback: tool.isEmpty ? "Tool" : tool)
    }
    let hint = extractHint(from: body)
    if body.effectiveToolInput?.description == hint,
       GoalsReader.runner(hint) == nil, !hint.contains("/") { return hint }
    return tool.isEmpty ? "Tool" : tool
}

/// The boundary's arbitrary JSON values retain unknown tool-input keys without a second alias parser.
indirect enum HookJSON: Codable, Sendable {
    case object([String: HookJSON]), array([HookJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: HookJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([HookJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var text: String? {
        if case .null = self { return nil }
        if case .string(let v) = self { return v }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }
    var object: [String: HookJSON]? { if case .object(let v) = self { return v }; return nil }
    var integer: Int? { if case .number(let v) = self, v.isFinite, v >= Double(Int.min), v < Double(Int.max) { return Int(v) }; return nil }
}

// Recover only an intact first or last numeric member of the transport's
// capped response object. Missing/truncated metadata remains unknown.
private let leadingStatusPattern = try! NSRegularExpression(pattern: #"^\s*\{\s*"(?:exit_code|exit_status)"\s*:\s*(-?[0-9]+)\s*[,}]"#)
private let trailingStatusPattern = try! NSRegularExpression(pattern: #",\s*"(?:exit_code|exit_status)"\s*:\s*(-?[0-9]+)\s*\}\s*$"#)
private func cappedExitStatus(head: String?, tail: String?) -> Int? {
    guard let head, head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return nil }
    for (text, regex) in [(head, leadingStatusPattern), (tail ?? "", trailingStatusPattern)] {
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) { return Int(text[range]) }
    }
    return nil
}
