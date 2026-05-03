import Foundation

struct RenderState: Encodable {
    var pet: String
    var species: String
    var desktop: String
    var total: Int
    var running: Int
    var waiting: Int
    var msg: String
    var entries: [String]
    var celebrate: Bool
    var prompt: RenderStatePrompt?
}

struct RenderStatePrompt: Encodable {
    var id: String
    var tool: String
    var hint: String
    var source: String?
    var approval: Bool
    var label: String?
}

private let encoder = JSONEncoder()

func renderState(from state: BuddyState) -> RenderState {
    RenderState(
        pet: state.pet.state.rawValue,
        species: UserDefaults.standard.string(forKey: "buddySpecies") ?? state.pet.species,
        desktop: state.desktop.status.rawValue,
        total: state.sessions.total,
        running: state.sessions.running,
        waiting: state.sessions.waiting,
        msg: String(state.msg.prefix(23)),
        entries: state.entries.prefix(6).map { String($0.prefix(80)) },
        celebrate: state.celebrateUntil != nil,
        prompt: state.prompt.map { p in
            RenderStatePrompt(
                id: p.id,
                tool: p.tool,
                hint: String(p.hint.prefix(60)),
                source: p.source,
                approval: p.isApproval,
                label: p.sessionLabel
            )
        }
    )
}

func renderStateData(from state: BuddyState) -> Data? {
    guard var data = try? encoder.encode(renderState(from: state)) else { return nil }
    data.append(0x0A)
    return data
}
