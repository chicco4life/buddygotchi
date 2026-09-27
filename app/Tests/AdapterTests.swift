import Foundation
import HookWire
import XCTest
@testable import BoopKit

final class AdapterTests: XCTestCase {
    func line(_ agent: String, _ hook: String, tool: String? = nil, topic: String? = nil, error: String? = nil,
              kind: String? = nil, cwd: String? = "/w/landing") -> HookLine {
        HookLine(agent: agent, hook: hook, session: "s1", cwd: cwd, tool: tool, topic: topic, error: error, kind: kind, ts: 7)
    }

    func kind(_ agent: String, _ hook: String, kind k: String? = nil) -> BoopEvent.Kind? {
        Adapter.event(from: line(agent, hook, kind: k))?.event
    }

    func testClaudeMapping() {
        let table: [(String, BoopEvent.Kind?)] = [
            ("SessionStart", .sessionStart), ("UserPromptSubmit", .turnStart), ("PreToolUse", .activity),
            ("PostToolUse", .activity), ("PostToolUseFailure", .activity), ("PermissionRequest", .needsYou),
            ("Elicitation", .needsYou), ("ElicitationResult", .activity), ("Stop", .turnEnd),
            ("StopFailure", .turnFailed), ("SessionEnd", .sessionEnd), ("SubagentStop", nil), ("PreCompact", nil),
        ]
        for (hook, expected) in table {
            XCTAssertEqual(kind("claude", hook), expected, hook)
        }
        XCTAssertEqual(kind("claude", "Notification", kind: "permission_prompt"), .needsYou)
        XCTAssertEqual(kind("claude", "Notification", kind: "elicitation_dialog"), .needsYou)
        XCTAssertEqual(kind("claude", "Notification", kind: "idle_prompt"), .turnStopped, "sat at its prompt")
        XCTAssertNil(kind("claude", "Notification"))
        var interrupted = line("claude", "PostToolUseFailure", tool: "Bash")
        interrupted.interrupt = true
        XCTAssertEqual(Adapter.event(from: interrupted)?.event, .turnStopped, "Esc sends no Stop")
        XCTAssertEqual(Adapter.event(from: interrupted)?.detail.tool, "Bash", "an interrupted call keeps its tool")
        XCTAssertNil(Adapter.event(from: line("claude", "Notification", kind: "idle_prompt"))?.detail.tool)
    }

    /// ADAPTERS.md §2: a Claude subagent's id rides on the event; Codex
    /// has none.
    func testASubagentsEventsSayWhichSubagent() {
        var sub = line("claude", "PreToolUse", tool: "Read")
        sub.agentID = "a1"
        XCTAssertEqual(Adapter.event(from: sub)?.subagent, "a1")
        XCTAssertEqual(Adapter.event(from: sub)?.session, "s1", "the parent's session")
        XCTAssertTrue(Adapter.event(from: sub)?.jsonLine.contains(#""subagent":"a1""#) == true)
        XCTAssertNil(Adapter.event(from: line("claude", "PreToolUse", tool: "Read"))?.subagent)
        var codex = line("codex", "PreToolUse", tool: "shell")
        codex.agentID = "a1"
        XCTAssertNil(Adapter.event(from: codex)?.subagent)
    }

    func testCodexMapping() {
        let table: [(String, BoopEvent.Kind?)] = [
            ("SessionStart", .sessionStart), ("UserPromptSubmit", .turnStart), ("PreToolUse", .activity),
            ("PostToolUse", .activity), ("PermissionRequest", .needsYou), ("Stop", .turnEnd),
            ("SessionEnd", .sessionEnd), ("StopFailure", nil), ("Notification", nil),
        ]
        for (hook, expected) in table {
            XCTAssertEqual(kind("codex", hook), expected, hook)
        }
        XCTAssertEqual(Adapter.event(from: line("codex", "Stop"))?.agent, .codex)
        XCTAssertNil(Adapter.event(from: line("cursor", "Stop")))
    }

    func testDetailCarriesToolTopicAndErrorClassOnly() throws {
        let activity = try XCTUnwrap(Adapter.event(from: line("claude", "PreToolUse", tool: "Bash", topic: "tests")))
        XCTAssertEqual(activity.detail, BoopEvent.Detail(tool: "Bash", topic: "tests"))
        let asking = try XCTUnwrap(Adapter.event(from: line("claude", "PermissionRequest", tool: "Bash")))
        XCTAssertEqual(asking.detail, BoopEvent.Detail(tool: "Bash"))
        let failed = try XCTUnwrap(Adapter.event(from: line("claude", "StopFailure", error: "rate_limit")))
        XCTAssertEqual(failed.detail.error, "rate_limit")
        XCTAssertEqual(Adapter.event(from: line("claude", "StopFailure", error: "weird thing"))?.detail.error, "other")
        XCTAssertEqual(activity.project, "landing")
        XCTAssertEqual(activity.ts, 7)
        XCTAssertEqual(Adapter.event(from: line("claude", "Stop"), receivedAt: 99)?.ts, 99)
    }

    /// ADAPTERS.md §3: Claude's PostToolUse and PostToolUseFailure say
    /// whether the call failed; an interrupted call and Codex say nothing.
    func testClaudeSaysWhetherACallFailed() throws {
        func failed(_ agent: String, _ hook: String, interrupt: Bool = false) -> Bool? {
            var l = line(agent, hook, tool: "Bash", topic: "tests")
            l.interrupt = interrupt
            return Adapter.event(from: l)?.detail.failed
        }
        XCTAssertEqual(failed("claude", "PostToolUse"), false)
        XCTAssertEqual(failed("claude", "PostToolUseFailure"), true)
        XCTAssertNil(failed("claude", "PostToolUseFailure", interrupt: true))
        XCTAssertNil(failed("claude", "PreToolUse"))
        XCTAssertNil(failed("codex", "PostToolUse"))
        let event = try XCTUnwrap(Adapter.event(from: line("claude", "PostToolUseFailure", tool: "Bash", topic: "tests")))
        XCTAssertEqual(event.event, .activity)
        XCTAssertTrue(event.jsonLine.contains(#""detail":{"failed":true,"tool":"Bash","topic":"tests"}"#), event.jsonLine)
    }

    /// ARCHITECTURE.md §5's example is this adapter output.
    func testEventJSONShape() throws {
        let line = HookLine(agent: "claude", hook: "PreToolUse", session: "a1b2", cwd: "/Users/me/src/landing",
                            tool: "Bash", topic: "tests", ts: 1_790_000_000_123)
        let event = try XCTUnwrap(Adapter.event(from: line))
        XCTAssertEqual(event.jsonLine, #"{"agent":"claude_code","detail":{"tool":"Bash","topic":"tests"},"event":"activity","project":"landing","session":"a1b2","ts":1790000000123}"#)
    }

    func testProjectNames() {
        XCTAssertEqual(Adapter.projectName(cwd: "/Users/me/src/landing"), "landing")
        XCTAssertEqual(Adapter.projectName(cwd: "/Users/me/src/landing/"), "landing")
        XCTAssertEqual(Adapter.projectName(cwd: "~/project"), "project")
        XCTAssertEqual(Adapter.projectName(cwd: "/Users/me/src/landing/.worktrees/fix-nav"), "landing")
        XCTAssertEqual(Adapter.projectName(cwd: "/Users/me/src/buddygotchi/.claude/worktrees/bridge-x"), "buddygotchi")
        XCTAssertEqual(Adapter.projectName(cwd: "/"), "unknown")
        XCTAssertEqual(Adapter.projectName(cwd: ""), "unknown")
    }

    func testAGitWorktreeAnywhereMapsToItsMainRepository() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-wt-\(UUID().uuidString)")
        let tree = root.appendingPathComponent("elsewhere/feature-x")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "gitdir: /Users/me/src/jetpack/.git/worktrees/feature-x\n"
            .write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Adapter.projectName(cwd: tree.path), "jetpack")
    }

    /// ADAPTERS.md §3: a worktree's `.git` is read once per folder, not on
    /// every hook, and the cache starts again past 512 folders. A line
    /// without a `cwd` is `unknown`; the core keeps the session's project.
    func testProjectNamesAreCachedPerFolder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-wt-\(UUID().uuidString)")
        let tree = root.appendingPathComponent("feature-x")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let git = tree.appendingPathComponent(".git")
        try "gitdir: /Users/me/src/jetpack/.git/worktrees/feature-x\n".write(to: git, atomically: true, encoding: .utf8)
        let names = Adapter.ProjectNames()
        XCTAssertEqual(names.name(cwd: tree.path), "jetpack")
        try FileManager.default.removeItem(at: git)
        XCTAssertEqual(names.name(cwd: tree.path), "jetpack", "not read again")
        for i in 0..<Adapter.ProjectNames.limit { _ = names.name(cwd: "/w/p\(i)") }
        XCTAssertEqual(names.name(cwd: tree.path), "feature-x", "read again once the cache starts over")
        XCTAssertLessThanOrEqual(names.names.count, Adapter.ProjectNames.limit)
        var line = line("claude", "PreToolUse", tool: "Bash")
        line.cwd = nil
        XCTAssertEqual(Adapter.event(from: line)?.project, "unknown")
    }

    func testRecordedClaudeSessionMapsInOrder() throws {
        let file = HookWireTests.fixtures.appendingPathComponent("claude-code/2026-09-08/tenth-try.jsonl")
        let events = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").compactMap { raw in
            HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0).flatMap { Adapter.event(from: $0) }
        }
        XCTAssertEqual(events.first?.event, .sessionStart)
        XCTAssertEqual(events[1].event, .turnStart)
        XCTAssertEqual(events.last?.event, .turnEnd)
        XCTAssertTrue(events.dropFirst(2).dropLast().allSatisfy { $0.event == .activity })
        XCTAssertEqual(events.filter { $0.detail.topic == "tests" }.count, 10)
        XCTAssertTrue(events.allSatisfy { $0.project == "fixture-project" && $0.session == "fixture-claude-code" })
        XCTAssertFalse(events.map(\.jsonLine).joined().contains("PRIVATE"))

        let failures = try String(contentsOf: HookWireTests.fixtures.appendingPathComponent("claude-code/2026-09-08/rate-limit.jsonl"), encoding: .utf8)
            .split(separator: "\n").compactMap { raw in
                HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0).flatMap { Adapter.event(from: $0) }
            }
        XCTAssertEqual(failures.map(\.event), [.sessionStart, .turnFailed, .turnFailed, .turnFailed])
        XCTAssertEqual(failures[1].detail.error, "rate_limit")
    }

    func testRecordedCodexSessionStart() throws {
        let data = try Data(contentsOf: HookWireTests.fixtures.appendingPathComponent("codex/2026-09-08/SessionStart-1.json"))
        let event = try XCTUnwrap(HookLine.extract(agent: "codex", payload: data, ts: 0).flatMap { Adapter.event(from: $0) })
        XCTAssertEqual(event.event, .sessionStart)
        XCTAssertEqual(event.agent, .codex)
        XCTAssertEqual(event.session, "abc123")
        XCTAssertEqual(event.project, "project")
    }

    func testHookServerReceivesWhatTheClientSends() throws {
        let path = NSTemporaryDirectory() + "boop-test-\(getpid()).sock"
        let received = Received()
        let server = HookServer(path: path) { line, _ in received.add(line) }
        try server.start()
        defer { server.stop() }
        let sent = HookLine(agent: "codex", hook: "Stop", session: "t1", cwd: "/w/x", ts: 5)
        XCTAssertTrue(HookSocket.send(sent.encoded(), to: path))
        XCTAssertTrue(HookSocket.send(HookLine(agent: "claude", hook: "Stop", session: "t2", ts: 6).encoded(), to: path))
        let deadline = Date().addingTimeInterval(2)
        while received.count < 2 && Date() < deadline { usleep(5000) }
        XCTAssertEqual(received.lines.first, sent)
        XCTAssertEqual(received.count, 2)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertFalse(HookSocket.send(sent.encoded(), to: path))
    }
}

final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [HookLine] = []
    func add(_ line: HookLine) { lock.withLock { stored.append(line) } }
    var lines: [HookLine] { lock.withLock { stored } }
    var count: Int { lines.count }
}
