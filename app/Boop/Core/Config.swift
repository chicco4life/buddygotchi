import Foundation
import Security

struct BuddyConfig: Sendable {
    var httpPort: Int
    var staleTimeoutMs: Double
    /// Lifetime of a passive attention request; name retained for compatibility.
    var approvalTimeoutMs: Double = 290_000
    var celebrateDurationMs: Double
    var stateDir: String
    var approvalMode: Bool
    var token: String
    var headless: Bool = false

    static let `default`: BuddyConfig = {
        // BOOP_STATE_DIR lets headless/e2e runs use a scratch store instead of
        // the owner's real one; the hook token still comes from that dir's config.
        let stateDir = ProcessInfo.processInfo.environment["BOOP_STATE_DIR"] ?? defaultStateDir()
        let (port, approvalMode, token) = readOrCreateConfig(stateDir: stateDir)
        return BuddyConfig(httpPort: port, staleTimeoutMs: 600_000, approvalTimeoutMs: 290_000, celebrateDurationMs: 4000, stateDir: stateDir, approvalMode: approvalMode, token: token, headless: CommandLine.arguments.contains("--headless") || ProcessInfo.processInfo.environment["BOOP_HEADLESS"] == "1")
    }()

    nonisolated(unsafe) private(set) static var recreatedCorruptConfig = false

    private static let defaultPort = 21321

    private static func defaultStateDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.boop"
    }

    private static var configPath: String {
        "\(ProcessInfo.processInfo.environment["BOOP_STATE_DIR"] ?? defaultStateDir())/config.json"
    }

    private static func readOrCreateConfig(stateDir: String) -> (Int, Bool, String) {
        let fm = FileManager.default
        let path = "\(stateDir)/config.json"

        try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        if let data = fm.contents(atPath: path) {
            if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let port = json["port"] as? Int ?? defaultPort
                let hadApprovalSettings = json.removeValue(forKey: "approvalMode") != nil
                let hadCodexSettings = json.removeValue(forKey: "codexApprovalMode") != nil
                let token = (json["token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? makeToken()
                if json["token"] as? String != token || hadApprovalSettings || hadCodexSettings {
                    json["token"] = token
                    writeConfigJSON(json, to: path)
                }
                return (port, false, token)
            }
            recreatedCorruptConfig = true
        }

        let token = makeToken()
        let defaultConfig: [String: Any] = ["port": defaultPort, "token": token]
        writeConfigJSON(defaultConfig, to: path)
        return (defaultPort, false, token)
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
