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
    var promptApproval: Bool?
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
        celebrate: state.celebrateUntil != nil,
        promptId: state.prompt?.id,
        promptTool: state.prompt.map { String($0.tool.prefix(20)) },
        promptApproval: state.prompt?.isApproval
    )
}

func renderStateData(from state: BuddyState) -> Data? {
    guard var data = try? encoder.encode(renderState(from: state)) else { return nil }
    data.append(0x0A)
    return data
}
