import Foundation
import Security

struct BuddyConfig: Sendable {
    var httpPort: Int
    var staleTimeoutMs: Double
    var approvalTimeoutMs: Double = 300_000
    var celebrateDurationMs: Double
    var workStallTimeoutMs: Double
    var stateDir: String
    var approvalMode: Bool
    var token: String

    static let `default`: BuddyConfig = {
        let stateDir = defaultStateDir()
        let (port, approvalMode, token) = readOrCreateConfig(stateDir: stateDir)
        return BuddyConfig(httpPort: port, staleTimeoutMs: 600_000, approvalTimeoutMs: 300_000, celebrateDurationMs: 4000, workStallTimeoutMs: 300_000, stateDir: stateDir, approvalMode: approvalMode, token: token)
    }()

    nonisolated(unsafe) private(set) static var recreatedCorruptConfig = false

    private static let defaultPort = 21321

    private static func defaultStateDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.boop"
    }

    private static var configPath: String {
        "\(defaultStateDir())/config.json"
    }

    private static func readOrCreateConfig(stateDir: String) -> (Int, Bool, String) {
        let fm = FileManager.default
        let path = configPath

        try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        if let data = fm.contents(atPath: path) {
            if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let port = json["port"] as? Int ?? defaultPort
                let approval = json["approvalMode"] as? Bool ?? false
                let token = (json["token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? makeToken()
                if json["token"] as? String != token {
                    json["token"] = token
                    writeConfigJSON(json, to: path)
                }
                return (port, approval, token)
            }
            recreatedCorruptConfig = true
        }

        let token = makeToken()
        let defaultConfig: [String: Any] = ["port": defaultPort, "token": token]
        writeConfigJSON(defaultConfig, to: path)
        return (defaultPort, false, token)
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
        if json["token"] == nil { json["token"] = makeToken() }
        writeConfigJSON(json, to: path)
    }

    private static func writeConfigJSON(_ json: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = URL(fileURLWithPath: path)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
