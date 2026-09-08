import Foundation

struct RenderState: Encodable {
    var pet: String
    var species: String
    var desktop: String
    var total: Int
    var running: Int
    var waiting: Int
    var msg: String
    var celebrate: Bool
    var mute: Bool?
    var promptId: String?
    var promptTool: String?
    var promptHint: String?
    var promptSource: String?
    var promptLabel: String?
    var promptApproval: Bool?
    var lastCompletedTool: String?
    var lastCompletedHint: String?
    var lastCompletedSource: String?
    var lastCompletedDurationMs: Int?
    var errorTool: String?
    var errorSource: String?
    var activity: String?
    var entries: [String]?
    var sessions: [SessionSummary]?

    // Personality (System P). All optional and short — absent keys cost no
    // budget, and old firmware ignores unknown keys.
    var greet: Bool?
    var greetLevel: Int?
    var mood: String?
    var effort: String?
    var celebrateLevel: Int?

    // Agent embodiment overlay (System E). Only present while an expression
    // lease is live; never present while a prompt is pending (S1, upstream).
    var agentSrc: String?
    var agentColor: String?
    var agentEmotion: String?
    var agentIntensity: String?
    var agentMotion: String?
    var agentSay: String?
    var agentDelivery: String?

    struct SessionSummary: Encodable {
        var src: String
        var st: String
        var tool: String?
        var lbl: String?
    }
}

private let encoder = JSONEncoder()

func renderState(from state: BuddyState, defaults: UserDefaults = .standard) -> RenderState {
    // In the error state the reducer encodes the failing tool into msg as
    // "Error: <tool>" (or a bare "Error" when no tool is known). errorTool is
    // extracted from that msg so the device can name what failed; errorSource
    // rides along on the last signal.
    let isError = state.pet.state == .error
    let soundsEnabled = defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true
    return RenderState(
        pet: state.pet.state.rawValue,
        species: defaults.string(forKey: DefaultsKey.buddySpecies) ?? state.pet.species,
        desktop: state.desktop.status.rawValue,
        total: state.sessions.total,
        running: state.sessions.running,
        waiting: state.sessions.waiting,
        // Byte budgets, not character counts — they must match the firmware's
        // fixed char[N] buffers (msg[24], promptTool[24], promptHint[64],
        // lines[81]), which strncpy fills by byte. See prefix(utf8Bytes:).
        msg: state.msg.prefix(utf8Bytes: 23),
        celebrate: state.celebrateUntil != nil,
        mute: soundsEnabled ? nil : true,
        promptId: state.prompt?.id,
        promptTool: state.prompt.map { $0.tool.prefix(utf8Bytes: 23) },
        promptHint: state.prompt.map { $0.hint.prefix(utf8Bytes: 63) },
        promptSource: state.prompt?.source,
        // Which project is asking. With several agent sessions sharing one
        // buddy, source+tool alone ("claude-code: Bash") cannot tell you
        // whose request you are approving.
        promptLabel: state.prompt?.sessionLabel.map { $0.prefix(utf8Bytes: 23) },
        promptApproval: state.prompt?.isApproval,
        lastCompletedTool: state.lastCompleted?.tool.map { $0.prefix(utf8Bytes: 20) },
        lastCompletedHint: state.lastCompleted?.hint.map { $0.prefix(utf8Bytes: 40) },
        lastCompletedSource: state.lastCompleted?.source,
        lastCompletedDurationMs: state.lastCompleted?.durationMs.map { Int($0) },
        errorTool: isError ? extractTool(fromMsg: state.msg).map { $0.prefix(utf8Bytes: 20) } : nil,
        errorSource: isError ? state.lastSignal : nil,
        activity: state.currentActivityKind?.rawValue
            ?? state.prompt?.activityKind.rawValue
            ?? state.lastCompleted?.activityKind.rawValue,
        entries: state.entries.isEmpty ? nil : state.entries.prefix(6).map { $0.prefix(utf8Bytes: 80) },
        sessions: state.activeSessions.count > 1
            ? state.activeSessions.prefix(6).map { snap in
                RenderState.SessionSummary(
                    src: snap.source,
                    st: snap.state.rawValue,
                    tool: snap.currentTool.map { $0.prefix(utf8Bytes: 16) },
                    lbl: snap.sessionLabel.map { $0.prefix(utf8Bytes: 16) }
                )
            }
            : nil,
        greet: state.greetUntil != nil ? true : nil,
        greetLevel: state.greetUntil != nil ? state.greetLevel : nil,
        mood: state.mood?.rawValue,
        effort: state.effortTier?.rawValue,
        celebrateLevel: state.celebrateUntil != nil ? state.celebrateIntensity : nil,
        agentSrc: state.agentOverlay?.agentId,
        agentColor: state.agentOverlay?.color,
        agentEmotion: state.agentOverlay?.emotion,
        agentIntensity: state.agentOverlay?.intensity,
        agentMotion: state.agentOverlay?.motion,
        // say/greeting were byte-capped at the MCP boundary (S5); the prefix
        // here is the same defense the other free-text fields get.
        agentSay: state.agentOverlay?.say.map { $0.prefix(utf8Bytes: 40) },
        agentDelivery: state.agentOverlay?.delivery
    )
}

extension String {
    /// Trim to at most `maxBytes` UTF-8 bytes, never splitting a character.
    ///
    /// The firmware stores these in fixed `char[N]` buffers and copies with
    /// `strncpy`, which counts BYTES. Bounding by `prefix(n)` counts Swift
    /// Characters, so a hint of 30 emoji is 30 "characters" and 120 bytes: the
    /// device kept the first 63 and left a dangling lead byte, which renders as
    /// garbage and makes the device's own `state` JSON invalid UTF-8 (enough to
    /// crash buddyctl and the HIL suite mid-prompt). Cutting on a Character
    /// boundary here keeps already-flashed devices correct without a reflash.
    func prefix(utf8Bytes maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var out = ""
        var used = 0
        for ch in self {
            let n = String(ch).utf8.count
            if used + n > maxBytes { break }
            out.append(ch)
            used += n
        }
        return out
    }
}

private func extractTool(fromMsg msg: String) -> String? {
    // Reducer encodes the error line as "Error: <tool>" (BuddyReducer.swift);
    // a bare "Error" carries no tool. Extract the tool half for the wire.
    let prefix = "Error: "
    guard msg.hasPrefix(prefix) else { return nil }
    let tool = String(msg.dropFirst(prefix.count))
    return tool.isEmpty ? nil : tool
}

/// Hard ceiling for one heartbeat, newline included.
///
/// The firmware reads frames into a 2048-byte `_LineBuf` and drops whatever
/// overflows, so an oversize frame is not truncated — the trailing bytes are
/// discarded, the JSON no longer parses, and the WHOLE heartbeat is lost. The
/// 10s keepalive then re-sends the same oversize state, so the device stops
/// hearing from a Mac that is working normally and naps after 30s. 1536 leaves
/// headroom under that buffer.
private let maxHeartbeatBytes = 1536

func renderStateData(from state: BuddyState) -> Data? {
    let full = renderState(from: state)
    guard var data = try? encoder.encode(full) else { return nil }
    if data.count + 1 > maxHeartbeatBytes {
        // Shed the two unbounded extras first — the firmware parses `entries`
        // for the glance card and ignores `sessions` entirely, so losing them
        // costs far less than losing the frame. Both are driven by agent text
        // (file paths, commands), which is what makes them unbounded.
        var trimmed = full
        trimmed.sessions = nil
        if let d = try? encoder.encode(trimmed), d.count + 1 <= maxHeartbeatBytes {
            data = d
        } else {
            trimmed.entries = nil
            if let d = try? encoder.encode(trimmed) { data = d }
        }
    }
    data.append(0x0A)
    assert(data.count <= maxHeartbeatBytes, "ESP32 heartbeat still oversize: \(data.count) bytes")
    return data
}
