import Foundation

enum SettingsSection: String, CaseIterable {
    // Content cases also select the rows composed into the five sidebar sections.
    case sounds, focus, language, voice, quick, leaderboard, profile, retire
    case general, buddy, agents, displays, about, device, advanced
    static let sidebar: [Self] = [.buddy, .agents, .device, .focus, .advanced]
    static let companion: [Self] = [.language, .voice, .sounds, .focus, .quick, .leaderboard, .profile, .retire]
    var symbol: String {
        switch self {
        case .buddy: "face.smiling"
        case .agents: "terminal"
        case .device: "display"
        case .focus: "moon"
        default: "gearshape.2"
        }
    }
    static let standard: [Self] = [.general, .buddy, .agents, .displays, .about]
}
