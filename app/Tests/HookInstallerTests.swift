import Foundation
import XCTest
@testable import BoopCore

@MainActor
final class HookInstallerTests: XCTestCase {
    func testCodexRegistersSessionEnd() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .codex)
        let settings = try readJSON(harness.home.appendingPathComponent(".codex/hooks.json"))
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["SessionEnd"])
        XCTAssertNil(hooks["PermissionRequest"])
        XCTAssertEqual(harness.installer.verify(agent: .codex), .installed)
    }

    func testUnreadableClaudeSettingsIsNotOverwritten() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let claudeDir = harness.home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settings = claudeDir.appendingPathComponent("settings.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: settings)

        try XCTAssertThrowsError(try harness.installer.installOrThrow(agent: .claudeCode)) { error in
            guard case HookInstallError.configUnreadable(.claudeCode, _) = error else {
                XCTFail("expected configUnreadable, got \(error)")
            }
        }
        try XCTAssertEqual(Data(contentsOf: settings), broken)
    }

    func testClaudeInstallIsVerifiedAndIdempotent() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .claudeCode)
        try harness.installer.installOrThrow(agent: .claudeCode)

        XCTAssertEqual(harness.installer.verify(agent: .claudeCode), .installed)

        let settings = try readJSON(harness.home.appendingPathComponent(".claude/settings.json"))
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertNil(hooks["PermissionRequest"])
        XCTAssertNotNil(hooks["PostToolUseFailure"])
        let sessionGroups = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let buddyCount = sessionGroups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String)?.contains("boop-hook.sh claude-code") == true }
            .count
        XCTAssertEqual(buddyCount, 1)
    }

    func testUninstallUnreadableClaudeSettingsFailsWithoutChangingFile() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let claudeDir = harness.home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settings = claudeDir.appendingPathComponent("settings.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: settings)

        let outcome = harness.installer.uninstall(agent: .claudeCode)

        XCTAssertEqual(outcome, .failed(reason: "\(settings.path) is not valid JSON — Boop entries were not removed"))
        try XCTAssertEqual(Data(contentsOf: settings), broken)
    }

    func testUninstallClearsInstalledAgentsEntry() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .claudeCode)
        XCTAssertEqual(harness.defaults.stringArray(forKey: DefaultsKey.installedAgents), [AgentKind.claudeCode.rawValue])

        XCTAssertEqual(harness.installer.uninstall(agent: .claudeCode), .removed)

        XCTAssertNil(harness.defaults.object(forKey: DefaultsKey.installedAgents))
    }

    func testDeletedScriptCorruptsAndRepairRestores() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .claudeCode)
        let script = harness.state.appendingPathComponent("boop-hook.sh")
        try FileManager.default.removeItem(at: script)

        XCTAssertEqual(harness.installer.verify(agent: .claudeCode), .corrupted(reason: "hook script missing"))
        try harness.installer.repair(agent: .claudeCode)
        XCTAssertEqual(harness.installer.verify(agent: .claudeCode), .installed)
    }

    func testCorruptBuddyConfigJSONHealthIsRepairable() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .claudeCode)
        try Data("{broken".utf8).write(to: harness.state.appendingPathComponent("config.json"))

        let health = harness.installer.verify(agent: .claudeCode)

        XCTAssertEqual(health, .corrupted(reason: HookHealthReason.configNotJSON))
        XCTAssertTrue(health.repairable)
    }

    func testOlderScriptVersionIsOutdatedAndRepairRestores() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .claudeCode)
        let script = harness.state.appendingPathComponent("boop-hook.sh")
        var content = try String(contentsOf: script, encoding: .utf8)
        content = content.replacingOccurrences(of: "boop-hook v\(HookInstaller.hookSchemaVersion)", with: "boop-hook v4")
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        XCTAssertEqual(harness.installer.verify(agent: .claudeCode), .outdated(installed: 4, current: HookInstaller.hookSchemaVersion))
        try harness.installer.repair(agent: .claudeCode)
        XCTAssertEqual(harness.installer.verify(agent: .claudeCode), .installed)
    }

    func testCodexCommentedFeatureFlagDoesNotCountAsEnabled() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let codexDir = harness.home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try "[features]\n# codex_hooks = true\n".write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try harness.installer.installOrThrow(agent: .codex)
        let toml = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(toml.contains("codex_hooks = true"))
        XCTAssertEqual(harness.installer.verify(agent: .codex), .installed)
    }

    func testCursorUsesManagedHelperAndRepairsMissingHelper() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.installer.installOrThrow(agent: .cursor)
        let hooks = try readJSON(harness.home.appendingPathComponent(".cursor/hooks.json"))
        let rootHooks = try XCTUnwrap(hooks["hooks"] as? [String: Any])
        let sessionHooks = try XCTUnwrap(rootHooks["sessionStart"] as? [[String: Any]])
        XCTAssertEqual(sessionHooks.first?["command"] as? String, "\(harness.state.path)/bin/boop-signal --agent cursor")

        try FileManager.default.removeItem(at: harness.state.appendingPathComponent("bin/boop-signal"))
        XCTAssertEqual(harness.installer.verify(agent: .cursor), .corrupted(reason: "Cursor helper binary missing"))
        try harness.installer.repair(agent: .cursor)
        XCTAssertEqual(harness.installer.verify(agent: .cursor), .installed)
    }

    func testRetiredMCPCleanupPreservesOtherServers() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        for (agent, path) in [(AgentKind.claudeCode, ".claude.json"), (.cursor, ".cursor/mcp.json")] {
            let url = harness.home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original: [String: Any] = ["mcpServers": ["boop": ["url": "http://127.0.0.1:21321/mcp"], "other": ["command": "keep-me"]], "custom": true]
            try JSONSerialization.data(withJSONObject: original).write(to: url)
            harness.installer.unregisterMCP(for: agent)
            harness.installer.unregisterMCP(for: agent)
            let result = try readJSON(url)
            let servers = try XCTUnwrap(result["mcpServers"] as? [String: Any])
            XCTAssertNil(servers["boop"])
            XCTAssertEqual((servers["other"] as? [String: String])?["command"], "keep-me")
            XCTAssertEqual(result["custom"] as? Bool, true)
        }
    }

    private struct Harness {
        let tempRoot: URL
        let home: URL
        let state: URL
        let installer: HookInstaller
        let defaults: UserDefaults
        let defaultsSuiteName: String

        func cleanup() {
            try? FileManager.default.removeItem(at: tempRoot)
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
    }

    private func makeHarness() throws -> Harness {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("boop-hook-tests-\(UUID().uuidString)")
        let home = tempRoot.appendingPathComponent("home")
        let state = tempRoot.appendingPathComponent("state")
        let signal = tempRoot.appendingPathComponent("BoopSignal")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: signal)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: signal.path)
        try writeConfig(state: state)
        let defaultsSuiteName = "boop-hook-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        let installer = HookInstaller(homeDir: home.path, stateDir: state.path, bundledSignalURL: signal, userDefaults: defaults)
        return Harness(tempRoot: tempRoot, home: home, state: state, installer: installer, defaults: defaults, defaultsSuiteName: defaultsSuiteName)
    }

    private func writeConfig(state: URL) throws {
        let config: [String: Any] = [
            "port": 21321,
            "token": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: state.appendingPathComponent("config.json"), options: .atomic)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
