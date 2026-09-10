import Foundation
import XCTest
@testable import BoopCore

final class AgentDashboardTests: XCTestCase {
    func testCountsIncludeSessionsBeyondPopoverAndFollowLifecycle() {
        var s = InternalState.test()
        for i in 0..<9 {
            s = reduce(s, .sessionStarted(at: NOW, sessionId: "c\(i)", source: "codex", cwd: nil))
        }
        s = reduce(s, .turnStarted(at: NOW + 1, sessionId: "c0", source: "codex"))
        XCTAssertEqual(s.buddy.activeSessions.count, 6)
        XCTAssertEqual(s.buddy.agentCounts, [.init(source: "codex", working: 1, idle: 8)])
        s = reduce(s, .turnEnded(at: NOW + 70_000, sessionId: "c0", source: "codex", outcome: .completed))
        XCTAssertEqual(s.buddy.agentCounts.first?.idle, 9)
        XCTAssertEqual(renderState(from: s.buddy, now: NOW + 70_000).state, .idle)
        s = reduce(s, .sessionEnded(at: NOW + 70_001, sessionId: "c0"))
        XCTAssertEqual(s.buddy.agentCounts.first?.idle, 8)
        s = reduce(s, .staleTick(at: NOW + TEST_STALE_MS + 100_000))
        XCTAssertTrue(s.buddy.agentCounts.isEmpty)
    }

    func testWaitingIsNotIdleAndAttentionWins() {
        var s = applyEvents(.test(),
            .sessionStarted(at: NOW, sessionId: "a", source: "codex", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "b", source: "claude-code", cwd: nil),
            .turnStarted(at: NOW + 1, sessionId: "b", source: "claude-code"),
            .requestArrived(at: NOW + 2, sessionId: "a", requestId: "p", tool: "Bash", hint: "test", sessionLabel: nil))
        XCTAssertEqual(s.buddy.agentCounts, [.init(source: "codex"), .init(source: "claude-code", working: 1)])
        XCTAssertEqual(renderState(from: s.buddy, now: NOW + 2).state, .needsYou)
        s = reduce(s, .requestCleared(at: NOW + 3, sessionId: "a"))
        XCTAssertEqual(s.buddy.agentCounts.first?.idle, 0)
    }

    func testMixedFrameAndWireBounds() throws {
        var s = BuddyState.initial
        s.creature.state = .done
        s.agentCounts = [.init(source: "codex", working: 2, idle: 1), .init(source: "claude-code", working: 1)]
        let frame = renderState(from: s, now: NOW)
        XCTAssertEqual(frame.state, .working)
        XCTAssertNil(frame.cheer)
        let data = try XCTUnwrap(renderStateData(from: frame))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["agents"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["idle"] as? Int, 1)
        var bounded = frame
        bounded.agents = [.init(source: "unknown", working: 1234, idle: -1)]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(renderStateData(from: bounded))) as? [String: Any])
        let row = try XCTUnwrap((object["agents"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["source"] as? String, "other")
        XCTAssertEqual(row["working"] as? Int, 99)
        XCTAssertEqual(row["idle"] as? Int, 0)
        XCTAssertLessThanOrEqual(data.count, maxHeartbeatBytes)
        // Retain counts even when escaped request text forces optional fields out.
        bounded.state = .needsYou
        bounded.agents = ["codex", "claude-code", "cursor", "other"].map {
            AgentCounts(source: $0, working: 99, idle: 99)
        }
        let escaped = String(repeating: "\u{01}", count: 63)
        bounded.card = .needsYou(id: escaped, tool: escaped, gloss: escaped,
                                stakes: .careful, n: 1, of: 99, approval: false)
        bounded.bubble = escaped
        bounded.snap = .init(name: escaped)
        let capped = try XCTUnwrap(renderStateData(from: bounded))
        XCTAssertLessThanOrEqual(capped.count, maxHeartbeatBytes)
        let cappedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: capped) as? [String: Any])
        XCTAssertEqual((cappedJSON["agents"] as? [[String: Any]])?.count, 4)

    }
}
