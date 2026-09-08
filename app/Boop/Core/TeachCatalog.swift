import Foundation

enum TeachCatalog {
    private static let lines: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "teach", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return decoded
    }()
    static func line(tool: String, language: String) -> String? { lines[tool]?[language] ?? lines[tool]?["en"] }
}
