import Foundation

struct BuddyConfig: Sendable {
    var httpPort: Int
    var staleTimeoutMs: Double
    var stateDir: String

    static let `default`: BuddyConfig = {
        let stateDir = defaultStateDir()
        let port = readOrCreateConfigPort(stateDir: stateDir)
        return BuddyConfig(httpPort: port, staleTimeoutMs: 600_000, stateDir: stateDir)
    }()

    private static let defaultPort = 21321

    private static func defaultStateDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.buddygotchi"
    }

    private static func readOrCreateConfigPort(stateDir: String) -> Int {
        let fm = FileManager.default
        let configPath = "\(stateDir)/config.json"

        try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        if let data = fm.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let port = json["port"] as? Int {
            return port
        }

        let defaultConfig: [String: Any] = ["port": defaultPort]
        if let data = try? JSONSerialization.data(withJSONObject: defaultConfig, options: [.prettyPrinted]) {
            fm.createFile(atPath: configPath, contents: data)
        }
        return defaultPort
    }
}
