import Foundation

enum SettingsSection: String, CaseIterable {
    case sounds, focus, language, voice, quick, leaderboard, profile, retire
    case general, buddy, agents, displays, about
    static let companion = allCases.filter { !standard.contains($0) }
    static let standard: [Self] = [.general, .buddy, .agents, .displays, .about]
}
