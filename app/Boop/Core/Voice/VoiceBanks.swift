import Foundation

enum VoiceBanks {
    static let occasions = ["share"]

    private static func load<T: Decodable>(_ name: String, language: String, as: T.Type) -> T? {
        guard let url = BuddyResources.moduleResourceURL(forResource: name, withExtension: "json", subdirectory: "voice/" + language),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static let banks: [String: [String: [String]]] = {
        var result: [String: [String: [String]]] = [:]
        for language in ["en", "ko"] {
            for occasion in occasions {
                result[language + "/" + occasion] = load(occasion, language: language, as: [String: [String]].self)
            }
        }
        return result
    }()
    static func lines(language: String, occasion: String, register: VoiceRegister) -> [String] {
        banks[language + "/" + occasion]?[register.rawValue] ?? []
    }
}
