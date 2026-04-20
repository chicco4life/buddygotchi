import Foundation

struct Heartbeat: Encodable {
    var total: Int
    var running: Int
    var waiting: Int
    var msg: String
    var entries: [String]
    var tokens: Int
    var tokens_today: Int
    var prompt: HeartbeatPrompt?
}

struct HeartbeatPrompt: Encodable {
    var id: String
    var tool: String
    var hint: String
}

private let encoder = JSONEncoder()

func heartbeat(from state: BuddyState) -> Heartbeat {
    Heartbeat(
        total: state.sessions.total,
        running: state.sessions.running,
        waiting: state.sessions.waiting,
        msg: String(state.msg.prefix(23)),
        entries: state.entries,
        tokens: 0,
        tokens_today: 0,
        prompt: state.prompt.map { p in
            HeartbeatPrompt(id: p.id, tool: p.tool, hint: String(p.hint.prefix(43)))
        }
    )
}

func heartbeatData(from state: BuddyState) -> Data? {
    guard var data = try? encoder.encode(heartbeat(from: state)) else { return nil }
    data.append(0x0A)
    return data
}
