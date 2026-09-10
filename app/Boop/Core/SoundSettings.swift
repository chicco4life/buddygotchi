import Foundation

enum SoundSettings {
    static let defaultVolume = 1
    static func volume(defaults: UserDefaults = .standard, respectingMute: Bool = true) -> Int {
        guard !respectingMute || (defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true) else { return 0 }
        return defaultVolume
    }
}
