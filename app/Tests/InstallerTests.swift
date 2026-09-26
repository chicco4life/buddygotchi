import Foundation
import XCTest
@testable import BoopKit

/// Every test runs on a temporary HOME; the owner's `~/.claude` and
/// `~/.codex` are never touched.
final class InstallerTests: XCTestCase {
    var home: URL!
    var installer: HookInstaller!
    var hook = ""

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("boop-home-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        hook = placeClient("Library/Application Support/Boop/bin/boop-hook")
        installer = HookInstaller(home: home, hookPath: hook)
    }

    /// An executable stand-in for `boop-hook` under HOME; returns its path.
    func placeClient(_ path: String) -> String {
        let url = home.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("#!/bin/sh\n".utf8).write(to: url)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func write(_ agent: HookInstaller.Agent, _ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        try! data.write(to: installer.configURL(agent))
    }

    func read(_ agent: HookInstaller.Agent) -> [String: Any] {
        let data = try! Data(contentsOf: installer.configURL(agent))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func commands(_ agent: HookInstaller.Agent, _ event: String) -> [String] {
        let groups = (read(agent)["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    /// A user's own hooks, plus the previous generation's Boop entries.
    let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "PreToolUse": [
                ["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/local/bin/audit.sh"]]],
                ["hooks": [["type": "command", "command": "/Users/x/.boop/boop-hook.sh claude-code", "timeout": 310]]],
            ],
            "Stop": [
                ["hooks": [
                    ["type": "command", "command": "say done"],
                    ["type": "command", "command": "/Users/x/.boop/boop-hook.sh claude-code"],
                ]],
            ],
            "UserPromptSubmit": [["hooks": [["type": "command", "command": "/Users/x/.boop/boop-hook.sh claude-code"]]]],
        ],
    ]

    func testInstallsEveryClaudeHookAndKeepsOthers() throws {
        write(.claude, existing)
        XCTAssertEqual(installer.health(.claude), .outdated)  // old-generation entries
        try installer.install(.claude)
        XCTAssertEqual(installer.health(.claude), .installed)
        let root = read(.claude)
        XCTAssertEqual(root["model"] as? String, "opus")
        let ours = "\"\(hook)\" claude"
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                      "PermissionRequest", "Notification", "Elicitation", "ElicitationResult", "Stop", "StopFailure",
                      "SessionEnd"] {
            XCTAssertEqual(commands(.claude, event).filter(HookInstaller.isBoopCommand), [ours], event)
        }
        XCTAssertEqual(commands(.claude, "PreToolUse"), ["/usr/local/bin/audit.sh", ours])
        XCTAssertEqual(commands(.claude, "Stop"), ["say done", ours])
        try XCTAssertFalse(String(decoding: try Data(contentsOf: installer.configURL(.claude)), as: UTF8.self).contains("boop-hook.sh"))
        let notification = (root["hooks"] as! [String: Any])["Notification"] as! [[String: Any]]
        XCTAssertEqual(notification.first?["matcher"] as? String, "permission_prompt|elicitation_dialog|idle_prompt")
    }

    /// ADAPTERS.md §5: Claude runs a `Notification` hook only for the types
    /// its matcher lists, so the matcher lists every type the adapter maps,
    /// `idle_prompt` included, and an install with the old matcher is
    /// repaired at the next launch.
    func testTheNotificationMatcherListsEveryTypeTheAdapterMaps() throws {
        let matcher = HookInstaller.events[.claude]!.first { $0.event == "Notification" }!.matcher!
        let types = Set(matcher.split(separator: "|").map(String.init))
        XCTAssertEqual(types, Adapter.askingNotifications.union([Adapter.idleNotification]))

        try installer.install(.claude)
        var root = read(.claude)
        var hooks = root["hooks"] as! [String: Any]
        hooks["Notification"] = [["matcher": "permission_prompt|elicitation_dialog",
                                  "hooks": [["type": "command", "command": installer.command(.claude), "timeout": 5]]]]
        root["hooks"] = hooks
        write(.claude, root)
        XCTAssertEqual(installer.health(.claude), .outdated)
        XCTAssertEqual(installer.repair(), [.claude])
        let notification = (read(.claude)["hooks"] as! [String: Any])["Notification"] as! [[String: Any]]
        XCTAssertEqual(notification.map { $0["matcher"] as? String }, [matcher])
    }

    func testInstallIsIdempotent() throws {
        write(.claude, existing)
        try installer.install(.claude)
        let url = installer.configURL(.claude)
        let first = try Data(contentsOf: url)
        let stamp = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        Thread.sleep(forTimeInterval: 0.02)
        try installer.install(.claude)
        try XCTAssertEqual(try Data(contentsOf: url), first)
        try XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, stamp)
        XCTAssertEqual(installer.repair(), [])
    }

    func testRemoveTakesOnlyBoopsEntries() throws {
        write(.claude, existing)
        try installer.install(.claude)
        try installer.remove(.claude)
        XCTAssertEqual(installer.health(.claude), .notInstalled)
        XCTAssertEqual(commands(.claude, "PreToolUse"), ["/usr/local/bin/audit.sh"])
        XCTAssertEqual(commands(.claude, "Stop"), ["say done"])
        XCTAssertNil((read(.claude)["hooks"] as! [String: Any])["UserPromptSubmit"])
        XCTAssertEqual(read(.claude)["model"] as? String, "opus")
    }

    func testRemovingTheOnlyHooksLeavesTheRestOfTheFile() throws {
        write(.claude, ["model": "opus"])
        try installer.install(.claude)
        try installer.remove(.claude)
        let root = read(.claude)
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertNil(root["hooks"])
    }

    func testCodexGetsItsHooksAndTheFeatureFlag() throws {
        try "model = \"gpt-5\"\n\n[features]\nweb_search = true\n".write(
            to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        try installer.install(.codex)
        XCTAssertEqual(installer.health(.codex), .installed)
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"] {
            XCTAssertEqual(commands(.codex, event), ["\"\(hook)\" codex"], event)
        }
        let toml = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        XCTAssertEqual(toml, "model = \"gpt-5\"\n\n[features]\ncodex_hooks = true\nweb_search = true\n")
        try installer.install(.codex)
        try XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8), toml)
    }

    /// ADAPTERS.md §5: "The app shows exactly what it will add", and for
    /// Codex that includes the switch in `config.toml`, until it's on.
    func testTheCodexPreviewShowsTheConfigChange() throws {
        let toml = home.appendingPathComponent(".codex/config.toml")
        let preview = installer.preview(.codex)
        XCTAssertTrue(preview.hasPrefix("SessionStart (startup|resume|clear) → \"\(hook)\" codex\n"), preview)
        XCTAssertTrue(preview.hasSuffix("SessionEnd → \"\(hook)\" codex\n\nIn \(toml.path), under [features]:\ncodex_hooks = true"),
                      preview)
        XCTAssertFalse(installer.preview(.claude).contains("codex_hooks"))
        try installer.install(.codex)
        try XCTAssertTrue(try String(contentsOf: toml, encoding: .utf8).contains("codex_hooks = true"))
        XCTAssertFalse(installer.preview(.codex).contains("codex_hooks"), "already on, so nothing to add")
    }

    func testFeatureFlagEdits() {
        XCTAssertEqual(HookInstaller.enablingCodexHooks(in: ""), "[features]\ncodex_hooks = true\n")
        XCTAssertEqual(HookInstaller.enablingCodexHooks(in: "a = 1"), "a = 1\n\n[features]\ncodex_hooks = true\n")
        XCTAssertNil(HookInstaller.enablingCodexHooks(in: "[features]\ncodex_hooks = true\n"))
        XCTAssertEqual(HookInstaller.enablingCodexHooks(in: "[features]\ncodex_hooks = false\n"), "[features]\ncodex_hooks = true\n")
        // A key of the same name in another table isn't ours.
        XCTAssertEqual(HookInstaller.enablingCodexHooks(in: "[other]\ncodex_hooks = true\n"),
                       "[other]\ncodex_hooks = true\n\n[features]\ncodex_hooks = true\n")
    }

    func testRepairRestoresMissingEntriesOnlyWhereBoopWasInstalled() throws {
        try installer.install(.claude)
        var root = read(.claude)
        var hooks = root["hooks"] as! [String: Any]
        hooks["Stop"] = nil
        root["hooks"] = hooks
        write(.claude, root)
        XCTAssertEqual(installer.health(.claude), .outdated)
        XCTAssertEqual(installer.health(.codex), .notInstalled)
        XCTAssertEqual(installer.repair(), [.claude])
        XCTAssertEqual(installer.health(.claude), .installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configURL(.codex).path))
    }

    func testMovedHookBinaryIsOutdated() throws {
        try installer.install(.claude)
        let moved = HookInstaller(home: home, hookPath: placeClient("Applications/Boop.app/Contents/MacOS/boop-hook"))
        XCTAssertEqual(moved.health(.claude), .outdated)
        try moved.install(.claude)
        XCTAssertEqual(commands(.claude, "Stop"), ["\"\(moved.hookPath)\" claude"])
    }

    /// `make run` once built the app without `boop-hook`, and launch repair
    /// replaced working entries with ones calling a file that wasn't there.
    func testMissingClientInstallsAndRepairsNothing() throws {
        write(.claude, existing)
        let before = try Data(contentsOf: installer.configURL(.claude))
        let unbuilt = HookInstaller(home: home, hookPath: home.appendingPathComponent("bin/boop-hook").path)
        XCTAssertFalse(unbuilt.clientInPlace)
        XCTAssertEqual(unbuilt.health(.claude), .clientMissing)
        XCTAssertEqual(unbuilt.health(.codex), .clientMissing)
        XCTAssertEqual(unbuilt.repair(), [])
        try XCTAssertThrowsError(try unbuilt.install(.claude))
        try XCTAssertThrowsError(try unbuilt.install(.codex))
        try XCTAssertEqual(try Data(contentsOf: installer.configURL(.claude)), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configURL(.codex).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.codexConfigURL.path))
        // Removing still works: it only takes Boop's entries out.
        try unbuilt.remove(.claude)
        XCTAssertEqual(commands(.claude, "Stop"), ["say done"])
    }

    func testUnreadableFileIsLeftAlone() throws {
        let url = installer.configURL(.claude)
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        guard case .unreadable = installer.health(.claude) else {
            XCTFail("expected unreadable")
            return
        }
        try XCTAssertThrowsError(try installer.install(.claude))
        try XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
    }

    func testRecognisesBoopCommands() {
        XCTAssertTrue(HookInstaller.isBoopCommand("\"/a b/boop-hook\" claude"))
        XCTAssertTrue(HookInstaller.isBoopCommand("/usr/local/bin/boop-hook codex"))
        XCTAssertTrue(HookInstaller.isBoopCommand("boop-hook claude"))
        XCTAssertTrue(HookInstaller.isBoopCommand("/Users/x/.boop/boop-hook.sh claude-code"))
        XCTAssertFalse(HookInstaller.isBoopCommand("/usr/local/bin/not-boop-hook claude"))
        XCTAssertFalse(HookInstaller.isBoopCommand("echo boop-hooked"))
        XCTAssertFalse(HookInstaller.isBoopCommand("say done"))
    }
}
