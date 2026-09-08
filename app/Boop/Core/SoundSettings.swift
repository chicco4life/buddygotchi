import Foundation

enum SoundSettings {
    static func volume(defaults: UserDefaults = .standard, respectingMute: Bool = true) -> Int {
        guard !respectingMute || (defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true) else { return 0 }
        return max(0, min(3, defaults.object(forKey: DefaultsKey.soundVolume) as? Int ?? 1))
    }
}
