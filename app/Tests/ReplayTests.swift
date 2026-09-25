import Foundation
import XCTest
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

    func testClaudePermissionShowsAtOnceAndClearsOnApproval() throws {
        let got = try summary("claude-code/synthetic/permission.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+1.0s working - 0",
            "+3.0s idle claude/jetpack 1",
            "+10.0s working - 0",
            "+411.0s idle - 0",
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
        XCTAssertTrue(effects.contains("moment cheer 1"))
        XCTAssertTrue(effects.contains("trigger event: turn finished · claude · fixture-project · topic: tests · took 1 min · 14:01 Wednesday"))
        XCTAssertEqual(effects.filter { $0.hasPrefix("state") }.count, 3)
        XCTAssertFalse(lines.joined().contains("PRIVATE"))
    }
}
