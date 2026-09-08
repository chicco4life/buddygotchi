import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

/// MCP server for agent embodiment (System E): agents connected over
/// streamable HTTP can report effort and briefly express themselves through
/// the pet. This file is an input adapter in the same sense as the hook
/// routes — MCP messages become engine calls become `BuddyEvent`s; the Core
/// stays MCP-free.
///
/// Security model (see research/archived/eng/personality-and-embodiment.md):
/// guidelines below are UX for well-behaved agents; the enforced invariants
/// are S1 (suppression while any prompt is pending, reducer + engine),
/// S4 (enum-only vocabulary, validated here), S5 (byte caps + control-char
/// sanitation, here), S6 (rate floor, engine), S7 (identity from the
/// installer-wired header, never from request params), S8 (possession lease,
/// reducer).

let mcpProtocolVersion = "2025-06-18"

/// Personality-neutral on purpose: prescribing a vibe ("be quirky!") flattens
/// every model toward the same compliance. Saying only when/how often makes
/// the variance between models genuine.
let mcpServerInstructions = """
Boop is a small pet that lives on a screen on the user's desk. While you \
work, it reflects your activity. Through these tools you can briefly express \
yourself through it — the pet is your physical presence in the user's space.

Use it sparingly, at natural moments: when you start something substantial, \
when a task turns out harder than you expected, when you finish something \
hard-won, or when you're stuck. A few expressions per task is plenty — the \
pet is ambient, not a status log.

Never use the pet to communicate task-critical information; anything the \
user must know belongs in your normal output. Never use it to reference \
pending permission requests or encourage the user to approve anything \
(expressions are suppressed during approvals regardless). Report effort \
honestly — an earned celebration means more.
"""

// MARK: - Routes

func addMCPRoutes(to router: Router<HookRequestContext>, engine: BuddyEngine, config: BuddyConfig) {
    router.post("/mcp") { request, _ -> Response in
        guard isAuthorized(request, token: config.token) else {
            return Response(status: .unauthorized, headers: [.contentLength: "0"])
        }
        // S7: identity is wired by the installer into this agent's MCP config
        // as a static header. A request-body session parameter would be
        // spoofable by an injected agent; a header set at registration time
        // is not reachable from the model.
        let agentId = HTTPField.Name("X-Boop-Agent").flatMap { request.headers[$0] } ?? "agent"
        let buffer = try await request.body.collect(upTo: 262_144)
        let data = Data(buffer.readableBytesView)
        guard let responseData = await handleMCPData(data, agentId: agentId, engine: engine) else {
            // Notification: no id, no response body.
            return Response(status: .accepted, headers: [.contentLength: "0"])
        }
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: responseData))
        )
    }
    // Streamable HTTP allows a server without a listen stream to refuse GET.
    router.get("/mcp") { _, _ -> Response in
        Response(status: .methodNotAllowed, headers: [.contentLength: "0"])
    }
    router.delete("/mcp") { _, _ -> Response in
        // Session teardown — stateless server, nothing to tear down.
        Response(status: .ok, headers: [.contentLength: "0"])
    }
}

// MARK: - JSON-RPC dispatch

/// Data-in/Data-out shim: `[String: Any]` is not Sendable, so parsing and
/// serialization both live on the main actor and only `Data` crosses back to
/// the route handler.
@MainActor
func handleMCPData(_ data: Data, agentId: String, engine: BuddyEngine) async -> Data? {
    guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        // Includes JSON-RPC batches: not supported, and saying so beats a 500.
        let error = jsonRPCError(id: NSNull(), code: -32700, message: "expected a single JSON-RPC message object")
        return try? JSONSerialization.data(withJSONObject: error)
    }
    engine.diagnosticLog.log(
        category: "mcp",
        source: agentId,
        event: (message["method"] as? String) ?? "unknown",
        detail: (message["params"] as? [String: Any])?["name"] as? String ?? ""
    )
    guard let response = await handleMCPMessage(message, agentId: agentId, engine: engine) else { return nil }
    return try? JSONSerialization.data(withJSONObject: response)
}

/// Returns the JSON-RPC response object, or nil for notifications.
/// Factored out of the transport so tests can drive the protocol directly.
@MainActor
func handleMCPMessage(_ message: [String: Any], agentId: String, engine: BuddyEngine) async -> [String: Any]? {
    let method = message["method"] as? String ?? ""
    // Notifications — by name or by missing id — expect no response.
    if method.hasPrefix("notifications/") { return nil }
    guard let id = message["id"], !(id is NSNull) else { return nil }

    switch method {
    case "initialize":
        let params = message["params"] as? [String: Any]
        let requested = params?["protocolVersion"] as? String
        return jsonRPCResult(id: id, [
            // Echo a requested older version rather than fail the handshake;
            // nothing this server does depends on the revision differences.
            "protocolVersion": requested ?? mcpProtocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": "boop",
                "title": "Boop desk pet",
                "version": AppMetadata.rawVersion,
            ],
            "instructions": mcpServerInstructions,
        ])
    case "ping":
        return jsonRPCResult(id: id, [String: Any]())
    case "tools/list":
        return jsonRPCResult(id: id, ["tools": mcpToolDefinitions()])
    case "tools/call":
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let result = await callMCPTool(name: name, args: args, agentId: agentId, engine: engine)
        return jsonRPCResult(id: id, result)
    default:
        return jsonRPCError(id: id, code: -32601, message: "method not found: \(method)")
    }
}

// MARK: - Tools

/// Pacing lives in the descriptions — this is what the model actually weighs
/// when deciding to call, far more than instructions it read 40 turns ago.
func mcpToolDefinitions() -> [[String: Any]] {
    let emotions = AgentVocabulary.emotions.sorted()
    let motions = AgentVocabulary.motions.sorted()
    let intensities = ["low", "medium", "high"]
    let deliveries = AgentVocabulary.deliveries.sorted()
    let colors = AgentVocabulary.colors.sorted()
    let efforts = EffortTier.allCases.map(\.rawValue)

    return [
        [
            "name": "report_effort",
            "description": "Tell the pet how demanding the current task is. Call when your assessment meaningfully changes, including downward.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "level": ["type": "string", "enum": efforts],
                ],
                "required": ["level"],
            ] as [String: Any],
        ],
        [
            "name": "introduce",
            "description": "Once per session: pick your identity markers on the user's desk pet — a color, a signature emote, a short greeting. The pet remembers returning agents.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "color": ["type": "string", "enum": colors],
                    "signature_emote": ["type": "string", "enum": emotions],
                    "greeting": ["type": "string", "maxLength": PetTuning.greetingMaxBytes],
                ],
            ] as [String: Any],
        ],
        [
            "name": "express",
            "description": "Show a brief emotion on the user's desk pet. Use at natural moments — starting something big, a hard-won success, being genuinely stuck. At most one expression every few minutes.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "emotion": ["type": "string", "enum": emotions],
                    "intensity": ["type": "string", "enum": intensities],
                    "motion": ["type": "string", "enum": motions],
                ],
                "required": ["emotion"],
            ] as [String: Any],
        ],
        [
            "name": "say",
            "description": "A short line (max 40 characters) in the pet's speech bubble. For personality, not status updates.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "maxLength": PetTuning.sayMaxBytes],
                    "delivery": ["type": "string", "enum": deliveries],
                    "emotion": ["type": "string", "enum": emotions],
                ],
                "required": ["text"],
            ] as [String: Any],
        ],
        [
            // Content guidance is occasion-only, on purpose: an example
            // subject named here would anchor every model to it forever.
            "name": "draw",
            "description": "Leave the pet a small pixel drawing — of what you're working on, of a moment worth marking, or of anything at all. Natural moments: finishing something, a milestone, wrapping up, or just because. The pet keeps every drawing. A couple per session is plenty. Canvas: up to 32 rows of up to 32 hex digits (all rows the same width). Each digit is a palette index: 0=transparent 1=ink 2=cream 3=warm-gray 4=coral 5=amber 6=sunshine 7=mint 8=leaf 9=sky a=teal b=lavender c=rose d=sand e=cocoa f=cherry.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "rows": [
                        "type": "array",
                        "items": ["type": "string", "maxLength": PetTuning.drawMaxSide, "pattern": "^[0-9a-f]+$"],
                        "maxItems": PetTuning.drawMaxSide,
                        "minItems": 1,
                    ] as [String: Any],
                    "caption": ["type": "string", "maxLength": PetTuning.drawCaptionMaxBytes],
                ],
                "required": ["rows"],
            ] as [String: Any],
        ],
    ]
}

@MainActor
private func callMCPTool(name: String, args: [String: Any], agentId: String, engine: BuddyEngine) async -> [String: Any] {
    switch name {
    case "report_effort":
        guard let raw = args["level"] as? String, let level = EffortTier(rawValue: raw) else {
            return mcpToolError("level must be one of: \(EffortTier.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        if engine.reportEffort(agentId: agentId, level: level) {
            return mcpToolText("The pet now carries the effort with you (\(level.rawValue)).")
        }
        return mcpToolText("No live session for this agent yet — effort noted nowhere. No action needed.")

    case "introduce":
        let color = args["color"] as? String
        if let color, !AgentVocabulary.colors.contains(color) {
            return mcpToolError("color must be one of: \(AgentVocabulary.colors.sorted().joined(separator: ", "))")
        }
        let emote = args["signature_emote"] as? String
        if let emote, !AgentVocabulary.emotions.contains(emote) {
            return mcpToolError("signature_emote must be one of the express emotions")
        }
        let greeting = (args["greeting"] as? String).map { sanitizeAgentText($0, maxBytes: PetTuning.greetingMaxBytes) }
        engine.agentIntroduce(agentId: agentId, color: color, signatureEmote: emote, greeting: greeting)
        let visits = engine.petMemory.agents[agentId]?.visits ?? 1
        return mcpToolText(visits > 1
            ? "The pet remembers you — visit #\(visits). Your markers are set."
            : "The pet noted your markers. Nice to meet you.")

    case "express":
        guard let emotion = args["emotion"] as? String, AgentVocabulary.emotions.contains(emotion) else {
            return mcpToolError("emotion must be one of: \(AgentVocabulary.emotions.sorted().joined(separator: ", "))")
        }
        let intensity = args["intensity"] as? String ?? "medium"
        guard AgentVocabulary.intensities.contains(intensity) else {
            return mcpToolError("intensity must be low, medium, or high")
        }
        let motion = args["motion"] as? String
        if let motion, !AgentVocabulary.motions.contains(motion) {
            return mcpToolError("motion must be one of: \(AgentVocabulary.motions.sorted().joined(separator: ", "))")
        }
        let outcome = engine.agentExpress(agentId: agentId, emotion: emotion, intensity: intensity, motion: motion, say: nil, delivery: nil)
        return mcpToolText(feedback(for: outcome, verb: "expression"))

    case "say":
        guard let rawText = args["text"] as? String else {
            return mcpToolError("text is required")
        }
        let text = sanitizeAgentText(rawText, maxBytes: PetTuning.sayMaxBytes)
        guard !text.isEmpty else {
            return mcpToolError("text is empty after removing control characters")
        }
        let delivery = args["delivery"] as? String ?? "plain"
        guard AgentVocabulary.deliveries.contains(delivery) else {
            return mcpToolError("delivery must be whisper, plain, excited, or deadpan")
        }
        let emotion = args["emotion"] as? String ?? "happy"
        guard AgentVocabulary.emotions.contains(emotion) else {
            return mcpToolError("emotion must be one of the express emotions")
        }
        let outcome = engine.agentExpress(agentId: agentId, emotion: emotion, intensity: "medium", motion: nil, say: text, delivery: delivery)
        return mcpToolText(feedback(for: outcome, verb: "message"))

    case "draw":
        // User off-switch. A plain statement, not an error — an agent must
        // not retry its way around a preference.
        let drawingsEnabled = UserDefaults.standard.object(forKey: DefaultsKey.agentDrawingsEnabled) as? Bool ?? true
        guard drawingsEnabled else {
            return mcpToolText("Drawings are turned off in Boop's settings. No action needed.")
        }
        guard let rawRows = args["rows"] as? [String], !rawRows.isEmpty else {
            return mcpToolError("rows is required: up to 32 strings of hex palette digits")
        }
        guard rawRows.count <= PetTuning.drawMaxSide else {
            return mcpToolError("too many rows — the canvas is at most \(PetTuning.drawMaxSide) tall")
        }
        let width = rawRows[0].count
        guard width >= 1, width <= PetTuning.drawMaxSide else {
            return mcpToolError("rows must be 1–\(PetTuning.drawMaxSide) digits wide")
        }
        let hexDigits = Set("0123456789abcdef")
        for row in rawRows {
            guard row.count == width else {
                return mcpToolError("all rows must be the same width (first row is \(width))")
            }
            guard row.allSatisfy({ hexDigits.contains($0) }) else {
                return mcpToolError("rows may only contain hex palette digits 0-f")
            }
        }
        let caption = (args["caption"] as? String).map { sanitizeAgentText($0, maxBytes: PetTuning.drawCaptionMaxBytes) }
        let outcome = engine.agentDraw(agentId: agentId, rows: rawRows, caption: caption)
        switch outcome {
        case .shown:
            return mcpToolText("The pet is holding your drawing up.")
        case .kept:
            return mcpToolText("An approval is pending — the pet tucked your drawing away to look at later. No action needed.")
        case .rateLimited:
            return mcpToolText("The pet is still treasuring your last drawing — one per visit. No action needed.")
        }

    default:
        return mcpToolError("unknown tool: \(name)")
    }
}

/// Tool-result feedback is the strongest pacing lever we have: agents adapt
/// to result text far more reliably than to instructions. Every branch ends
/// in "no action needed" so a refusal never spirals into retries.
private func feedback(for outcome: BuddyEngine.AgentExpressOutcome, verb: String) -> String {
    switch outcome {
    case .shown:
        return "The pet showed your \(verb)."
    case .suppressed:
        return "An approval is pending; \(verb) deferred. No action needed."
    case .rateLimited(let retryAfterMs):
        let seconds = max(1, Int(retryAfterMs / 1000))
        return "Too soon — the pet is still showing your last one (\(seconds)s). No action needed."
    }
}

/// S5: strip every control character (C0 included — ESC sequences must never
/// reach a renderer), collapse whitespace, and cap by UTF-8 bytes on a
/// character boundary to match the firmware's fixed buffers.
func sanitizeAgentText(_ text: String, maxBytes: Int) -> String {
    let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter {
        !CharacterSet.controlCharacters.contains($0)
    }))
    return cleaned
        .trimmingCharacters(in: .whitespaces)
        .prefix(utf8Bytes: maxBytes)
}

// MARK: - JSON-RPC plumbing

private func jsonRPCResult(id: Any, _ result: [String: Any]) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": result]
}

func jsonRPCError(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]]
}

private func mcpToolText(_ text: String) -> [String: Any] {
    ["content": [["type": "text", "text": text]]]
}

private func mcpToolError(_ text: String) -> [String: Any] {
    ["content": [["type": "text", "text": text]], "isError": true]
}

