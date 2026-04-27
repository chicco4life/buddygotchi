import Foundation

struct BuddyConfig: Sendable {
    var httpPort: Int
    var staleTimeoutMs: Double
    var celebrateDurationMs: Double
    var stateDir: String
    var approvalMode: Bool

    static let `default`: BuddyConfig = {
        let stateDir = defaultStateDir()
        let (port, approvalMode) = readOrCreateConfig(stateDir: stateDir)
        return BuddyConfig(httpPort: port, staleTimeoutMs: 600_000, celebrateDurationMs: 4000, stateDir: stateDir, approvalMode: approvalMode)
    }()

    private static let defaultPort = 21321

    private static func defaultStateDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.buddygotchi"
    }

    private static var configPath: String {
        "\(defaultStateDir())/config.json"
    }

    private static func readOrCreateConfig(stateDir: String) -> (Int, Bool) {
        let fm = FileManager.default
        let path = configPath

        try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        if let data = fm.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let port = json["port"] as? Int ?? defaultPort
            let approval = json["approvalMode"] as? Bool ?? false
            return (port, approval)
        }

        let defaultConfig: [String: Any] = ["port": defaultPort]
        if let data = try? JSONSerialization.data(withJSONObject: defaultConfig, options: [.prettyPrinted]) {
            fm.createFile(atPath: path, contents: data)
        }
        return (defaultPort, false)
    }

    static func setApprovalMode(_ enabled: Bool) {
        let path = configPath
        let fm = FileManager.default
        var json: [String: Any] = [:]
        if let data = fm.contents(atPath: path),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = parsed
        }
        json["approvalMode"] = enabled
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: path, contents: data)
        }
    }
}
