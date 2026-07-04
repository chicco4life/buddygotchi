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
    // Pull error-context fields from the (currently-stale) prompt source if the
    // pet is showing error; the actual session-level errored fields would require
    // exposing more of internal state, but the msg already encodes "Stalled: <tool>"
    // so device parity is preserved. errorTool/errorSource are populated lazily
    // from the lastCompleted/prompt fields when relevant.
    let isError = state.pet.state == .error
    return RenderState(
        pet: state.pet.state.rawValue,
        species: UserDefaults.standard.string(forKey: DefaultsKey.buddySpecies) ?? state.pet.species,
        desktop: state.desktop.status.rawValue,
        total: state.sessions.total,
        running: state.sessions.running,
        waiting: state.sessions.waiting,
        msg: String(state.msg.prefix(23)),
        celebrate: state.celebrateUntil != nil,
        promptId: state.prompt?.id,
        promptTool: state.prompt.map { String($0.tool.prefix(20)) },
        promptHint: state.prompt.map { String($0.hint.prefix(60)) },
        promptSource: state.prompt?.source,
        promptApproval: state.prompt?.isApproval,
        lastCompletedTool: state.lastCompleted?.tool.map { String($0.prefix(20)) },
        lastCompletedHint: state.lastCompleted?.hint.map { String($0.prefix(40)) },
        lastCompletedSource: state.lastCompleted?.source,
        lastCompletedDurationMs: state.lastCompleted?.durationMs.map { Int($0) },
        errorTool: isError ? extractTool(fromMsg: state.msg) : nil,
        errorSource: isError ? state.lastSignal : nil,
        activity: state.currentActivityKind?.rawValue
            ?? state.prompt?.activityKind.rawValue
            ?? state.lastCompleted?.activityKind.rawValue,
        entries: state.entries.isEmpty ? nil : Array(state.entries.prefix(6)),
        sessions: state.activeSessions.count > 1
            ? state.activeSessions.map { snap in
                RenderState.SessionSummary(
                    src: snap.source,
                    st: snap.state.rawValue,
                    tool: snap.currentTool,
                    lbl: snap.sessionLabel
                )
            }
            : nil
    )
}

private func extractTool(fromMsg msg: String) -> String? {
    // Reducer encodes "Stalled: <tool>" — extract the tool half for the wire.
    guard msg.hasPrefix("Stalled: ") else { return nil }
    return String(msg.dropFirst("Stalled: ".count))
}

func renderStateData(from state: BuddyState) -> Data? {
    guard var data = try? encoder.encode(renderState(from: state)) else { return nil }
    data.append(0x0A)
    return data
}
