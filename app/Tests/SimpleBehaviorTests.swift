import Foundation
import BoopSQLite
import XCTest
@testable import BoopCore

final class SimpleBehaviorTests: XCTestCase {
    func testExistingXPIsNeverRepricedAndNewAwardsSurviveRestart() async throws {
        let (_, dir, cleanup) = try makeStore(); defer { cleanup() }
        let db = try Database(path: dir.path + "/boop.sqlite")
        try db.run("INSERT INTO ledger(at,source,amount,session_id,day) VALUES(0,'task',1,'old','2026-01-01')")
        try db.run("INSERT INTO growth_totals VALUES('2026-01-01','task',123,1)")
        let store = try Store(stateDir: dir.path, now: 0)
        let before = try await store.growth(localDay: "2026-01-01", at: 0)
        XCTAssertEqual(before.xp, 123)
        _ = try await store.award([.init(at: -1, source: .turn, day: "2026-01-01"), .init(at: 1, source: .tokens, amount: 1_000_000, day: "2026-01-01")], active: true, at: 1, localDay: "2026-01-01")
        _ = try await store.award([], active: true, at: 2, localDay: "2026-01-01")
        let reopened = try Store(stateDir: dir.path, now: 3)
        let after = try await reopened.growth(localDay: "2026-01-01", at: 3)
        XCTAssertEqual(after.xp, 136)
        XCTAssertEqual(after.tasks, 1)
        let rows = try await reopened.ledger()
        XCTAssertEqual(rows.count, 3)
    }

    func testLegacyLedgerOnlyMigratesOnce() async throws {
        let (_, dir, cleanup) = try makeStore(); defer { cleanup() }
        let db = try Database(path: dir.path + "/boop.sqlite")
        try db.run("INSERT INTO ledger(at,source,amount,session_id,day) VALUES(0,'activeDay',1,'old','2026-01-01'),(1,'task',1,'old','2026-01-01')")
        let store = try Store(stateDir: dir.path, now: 0)
        let old = try await store.growth(localDay: "2026-01-01", at: 0)
        XCTAssertEqual(old.xp, 19) // Old day included the one-point streak bonus.
        _ = try await store.award([.init(at: 2, source: .turn, day: "2026-01-01")], active: true, at: 2, localDay: "2026-01-01")
        let reopened = try Store(stateDir: dir.path, now: 3)
        let current = try await reopened.growth(localDay: "2026-01-01", at: 3)
        XCTAssertEqual(current.xp, 22)
    }

    func testTypicalHourCannotWakeDisconnectedBuddy() {
        var memory = PetMemory.empty
        memory.hourHistogram = Array(repeating: 10, count: 24)
        memory.histogramSamples = 240
        memory.firstSampleAt = 0
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        s = reduce(s, .memoryLoaded(at: 30 * 86_400_000, memory: memory))
        s = reduce(s, .staleTick(at: 30 * 86_400_000))
        XCTAssertEqual(s.buddy.creature.state, .asleep)
        XCTAssertNotNil(BehaviorMemory(memory: memory, at: 30 * 86_400_000).currentHourIsTypical)
    }

    func testRetiredSigningRepliesAreIgnored() {
        XCTAssertNil(parseDeviceLine(#"{"ack":"unit","ok":true}"#))
        XCTAssertNil(parseDeviceLine(#"{"ack":"sign","ok":true}"#))
        if case .ack("retire") = parseDeviceLine(#"{"ack":"retire"}"#) {} else { XCTFail("retire ack lost") }
    }
}

extension SimpleBehaviorTests {
    func testBothNudgesReachWireBeforePromptExpires() throws {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        s = reduce(s, .approvalArrived(at: 0, sessionId: "s", requestId: "r", tool: "Read", hint: "read", sessionLabel: nil, source: "codex"))
        for (at, rung): (Double, Int) in [(60_000, 1), (120_000, 2)] {
            s = reduce(s, .staleTick(at: at))
            let frame = renderState(from: s.buddy, now: at)
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as! [String: Any]
            XCTAssertEqual(json["nudgeRung"] as? Int, rung)
            XCTAssertNotNil(json["card"])
        }
        s = reduce(s, .staleTick(at: 290_001))
        XCTAssertNil(s.buddy.prompt)
        XCTAssertEqual(renderState(from: s.buddy, now: 290_001).nudgeRung, 0)
    }
}

extension SimpleBehaviorTests {
    func testSessionSummaryCountsCompletedTurnsNotToolResults() async {
        let extractor = Extractor()
        var payload = RawHookPayload(source: "codex", sessionId: "s", kind: .turnStart, toolName: "Bash", timestamp: 0)
        _ = await extractor.ingest(payload)
        for i in 1...5 {
            payload.kind = .toolResult; payload.exitStatus = i == 5 ? 0 : 1; payload.timestamp = Double(i)
            _ = await extractor.ingest(payload)
        }
        payload.kind = .turnEnd; payload.timestamp = 6
        _ = await extractor.ingest(payload)
        _ = await extractor.ingest(payload) // Duplicate completion cannot double-count.
        payload.kind = .sessionEnd; payload.timestamp = 7
        let result = await extractor.ingest(payload)
        XCTAssertTrue(result.facts.contains(.sessionSummary(turns: 1, tasks: 1, elapsedMs: 7)))
    }
}
