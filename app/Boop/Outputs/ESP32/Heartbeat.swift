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

    struct SessionSummary: Encodable {
        var src: String
        var st: String
        var tool: String?
        var lbl: String?
    }
}

private let encoder = JSONEncoder()

func renderState(from state: BuddyState) -> RenderState {
    // In the error state the reducer encodes the failing tool into msg as
    // "Error: <tool>" (or a bare "Error" when no tool is known). errorTool is
    // extracted from that msg so the device can name what failed; errorSource
    // rides along on the last signal.
    let isError = state.pet.state == .error
    let soundsEnabled = UserDefaults.standard.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true
    return RenderState(
        pet: state.pet.state.rawValue,
        species: UserDefaults.standard.string(forKey: DefaultsKey.buddySpecies) ?? state.pet.species,
        desktop: state.desktop.status.rawValue,
        total: state.sessions.total,
        running: state.sessions.running,
        waiting: state.sessions.waiting,
        msg: String(state.msg.prefix(23)),
        celebrate: state.celebrateUntil != nil,
        mute: soundsEnabled ? nil : true,
        promptId: state.prompt?.id,
        promptTool: state.prompt.map { String($0.tool.prefix(20)) },
        promptHint: state.prompt.map { String($0.hint.prefix(60)) },
        promptSource: state.prompt?.source,
        promptApproval: state.prompt?.isApproval,
        lastCompletedTool: state.lastCompleted?.tool.map { String($0.prefix(20)) },
        lastCompletedHint: state.lastCompleted?.hint.map { String($0.prefix(40)) },
        lastCompletedSource: state.lastCompleted?.source,
        lastCompletedDurationMs: state.lastCompleted?.durationMs.map { Int($0) },
        errorTool: isError ? extractTool(fromMsg: state.msg).map { String($0.prefix(20)) } : nil,
        errorSource: isError ? state.lastSignal : nil,
        activity: state.currentActivityKind?.rawValue
            ?? state.prompt?.activityKind.rawValue
            ?? state.lastCompleted?.activityKind.rawValue,
        entries: state.entries.isEmpty ? nil : state.entries.prefix(6).map { String($0.prefix(48)) },
        sessions: state.activeSessions.count > 1
            ? state.activeSessions.prefix(6).map { snap in
                RenderState.SessionSummary(
                    src: snap.source,
                    st: snap.state.rawValue,
                    tool: snap.currentTool.map { String($0.prefix(16)) },
                    lbl: snap.sessionLabel.map { String($0.prefix(16)) }
                )
            }
            : nil
    )
}

private func extractTool(fromMsg msg: String) -> String? {
    // Reducer encodes the error line as "Error: <tool>" (BuddyReducer.swift);
    // a bare "Error" carries no tool. Extract the tool half for the wire.
    let prefix = "Error: "
    guard msg.hasPrefix(prefix) else { return nil }
    let tool = String(msg.dropFirst(prefix.count))
    return tool.isEmpty ? nil : tool
}

func renderStateData(from state: BuddyState) -> Data? {
    guard var data = try? encoder.encode(renderState(from: state)) else { return nil }
    data.append(0x0A)
    assertionFailureIfOversize(data)
    return data
}

private func assertionFailureIfOversize(_ data: Data) {
    assert(data.count <= 1536, "ESP32 heartbeat exceeded 1.5 KB: \(data.count) bytes")
}
