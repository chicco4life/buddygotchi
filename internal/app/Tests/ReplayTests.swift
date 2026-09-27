import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// `boopdev replay` on the fixtures prints the expected `state` snapshots.
final class ReplayTests: XCTestCase {
    /// Each snapshot as `+time base attn wait`, e.g. `+3.0s idle claude/jetpack 1`.
    func summary(_ fixture: String, agent: String) throws -> [String] {
        let path = HookWireTests.fixtures.appendingPathComponent(fixture).path
        let lines = Replay(agent: agent).run(try Replay.steps(fromFile: path), statesOnly: true)
        return try lines.map { line in
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            XCTAssertEqual(parts[1], "state")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: Any])
            let attn = (object["attn"] as? [String: Any]).map { "\($0["agent"]!)/\($0["project"]!)" } ?? "-"
            return "\(parts[0]) \(object["base"]!) \(attn) \(object["wait"]!)"
        }
    }

    /// ADAPTERS.md §4: Claude has no hook for the moment you approve, so
    /// "needs you" clears when the approved two-minute build finishes.
    func testClaudePermissionShowsAtOnceAndClearsWhenTheApprovedToolFinishes() throws {
        let got = try summary("claude-code/synthetic/permission.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+1.0s working - 0",
            "+3.0s idle claude/jetpack 1",
            "+125.0s working - 0",
            "+526.0s idle - 0",
        ])
    }

    /// ADAPTERS.md §4: two parallel subagents in one session; a1 waits on
    /// a permission prompt while a2 keeps reading and editing. "Needs you"
    /// stays until a1's call runs.
    func testASiblingSubagentKeepsWorkingWhileOneWaits() throws {
        let got = try summary("claude-code/synthetic/subagents.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+1.0s working - 0",
            "+3.0s idle claude/landing 1",
            "+71.0s working - 0",
            "+72.0s idle - 0",
        ])
    }

    func testCodexRequestItsReviewerHandlesNeverShows() throws {
        let got = try summary("codex/synthetic/approval-reviewed.jsonl", agent: "codex")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+1.0s working - 0",
            "+25.5s idle - 0",
        ])
    }

    func testCodexRequestThatWaitsShowsAfterTwoSeconds() throws {
        let got = try summary("codex/synthetic/approval-asked.jsonl", agent: "codex")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+1.0s working - 0",
            "+5.0s idle codex/landing 1",
            "+14.0s working - 0",
            "+55.0s idle - 0",
        ])
    }

    func testRecordedClaudeSession() throws {
        let path = HookWireTests.fixtures.appendingPathComponent("claude-code/2026-09-08/tenth-try.jsonl").path
        var replay = Replay(agent: "claude")
        replay.gapMs = 5000
        let lines = replay.run(try Replay.steps(fromFile: path))
        let effects = lines.filter { $0.hasPrefix("+") }.map { $0.split(separator: " ", maxSplits: 1)[1] }
        XCTAssertTrue(effects.contains("moment cheer"))
        XCTAssertTrue(effects.contains(#"event turn_end · claude finished turn 1 on "fixture-project": done after 1 min, a very long turn, 10 tools. Tests passing. · Boop cheered on its own."#), "\(effects)")
        XCTAssertEqual(effects.filter { $0.hasPrefix("state") }.count, 3)
        XCTAssertFalse(lines.joined().contains("PRIVATE"))
    }

    /// The J1 fixtures carry boopctl e2e checkpoints; replay skips them and
    /// treats a clock jump as time passing.
    func testE2ECheckpointsAreSkipped() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hooks/e2e/claude/session.jsonl").path
        let steps = try Replay.steps(fromFile: path)
        XCTAssertTrue(steps.contains(.advance(400_000)))
        let lines = Replay(agent: "claude").run(steps)
        XCTAssertFalse(lines.contains { $0.hasPrefix("# skipped") })
        XCTAssertTrue(lines.contains { $0.hasSuffix("moment cheer") })
        XCTAssertTrue(lines.contains { $0.contains("failed (rate limit)") })
        XCTAssertFalse(lines.contains { $0.contains("moment oops") }, "a failed turn has no moment")
    }
}
