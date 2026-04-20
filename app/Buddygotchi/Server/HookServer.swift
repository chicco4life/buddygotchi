import Foundation
import Hummingbird
import NIOCore

private struct HookEventBody: Decodable, Sendable {
    var session_id: String?
    var hook_event_name: String?
    var cwd: String?
    var tool_name: String?
    var tool_input: ToolInput?
    var notification_type: String?
    var message: String?

    struct ToolInput: Decodable, Sendable {
        var command: String?
        var file_path: String?
        var path: String?
        var url: String?
        var query: String?
        var description: String?
    }
}

private struct SignalRequestBody: Decodable, Sendable {
    var agent_id: String?
    var session_id: String?
    var conversation_id: String?
    var signal: String?
    var cwd: String?
}

func buildHookServer(engine: BuddyEngine, config: BuddyConfig) -> Application<RouterResponder<BasicRequestContext>> {
    let router = Router()

    router.get("/healthz") { _, _ -> Response in
        let state = await engine.state
        return jsonResponse([
            "ok": true,
            "stateVersion": state.version,
            "desktop": state.desktop.status.rawValue,
        ] as [String: Any])
    }

    router.post("/hook/event") { request, _ -> Response in
        let source = request.uri.queryParameters["source"].map(String.init) ?? "claude-code"
        let body = try await decodeBody(HookEventBody.self, from: request)
        let hookPid: Int32? = (body.hook_event_name == "SessionStart")
            ? request.uri.queryParameters["pid"].flatMap({ Int32(String($0)) })
            : nil
        await handleAgentEvent(body: body, source: source, hookPid: hookPid, engine: engine)
        return emptyOK()
    }

    router.post("/hook/signal") { request, _ -> Response in
        let body = try await decodeBody(SignalRequestBody.self, from: request)
        let source = body.agent_id ?? "claude-code"
        let sessionId = body.session_id ?? body.conversation_id ?? "\(source)_default"
        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd)
        if let signalStr = body.signal, let signal = ActivitySignalKind(rawValue: signalStr) {
            await engine.activitySignal(sessionId: sessionId, source: source, signal: signal)
        }
        return emptyOK()
    }

    return Application(
        router: router,
        configuration: .init(address: .hostname("127.0.0.1", port: config.httpPort))
    )
}

// MARK: - Agent Event Handler

private func handleAgentEvent(body: HookEventBody, source: String, hookPid: Int32?, engine: BuddyEngine) async {
    let sessionId = body.session_id ?? "\(source)_\(hashCwd(body.cwd))"
    let event = body.hook_event_name ?? ""
    let sessionLabel = cwdLabel(body.cwd)

    if event != "SessionEnd" {
        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd, hookPid: hookPid)
    }

    switch event {
    case "SessionStart":
        break

    case "UserPromptSubmit":
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .startWorking)

    case "Stop", "StopFailure":
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .stopWorking)

    case "PostToolUse":
        await engine.clearRequest(sessionId: sessionId)
        await engine.activitySignal(sessionId: sessionId, source: source, signal: .keepWorking)

    case "SessionEnd":
        await engine.sessionEnded(sessionId: sessionId)

    case "PermissionRequest":
        let tool = body.tool_name ?? "Permission"
        let hint = extractHint(from: body)
        let requestId = "\(sessionId)_\(shortUUID())"
        await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)

    case "Notification":
        switch body.notification_type {
        case "permission_prompt", "elicitation_dialog":
            let tool = body.notification_type ?? "Notification"
            let hint = body.message ?? ""
            let requestId = "\(sessionId)_\(shortUUID())"
            await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)
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

// MARK: - Helpers

private func extractHint(from body: HookEventBody) -> String {
    if let ti = body.tool_input {
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

private func hashCwd(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "unknown" }
    return String(cwd.hashValue, radix: 36)
}

private func shortUUID() -> String {
    String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
}

private let sharedDecoder = JSONDecoder()

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

