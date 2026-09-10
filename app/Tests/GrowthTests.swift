import Foundation
import XCTest
@testable import BoopCore

final class GrowthTests: XCTestCase {
    func testEverySourceAndFormulaRereadsHistory() {
        let rows = XPSource.allCases.map { LedgerRow(at: 0, source: $0, amount: $0 == .tokens ? 100_000 : 1, day: "2026-01-01") }
        let formula = GrowthFormula()
        let awards = Dictionary(uniqueKeysWithValues: formula.awards(rows).map { ($0.0.source, $0.1) })
        XCTAssertEqual(awards, [.turn:3,.task:0,.hardWonPass:0,.activeDay:10,.streakBonus:0,.session:0,.checkIn:0,.tokens:0])
        var tuned = formula; tuned.turn = 7
        XCTAssertEqual(tuned.snapshot(rows, localDay: "2026-01-01").xp - formula.snapshot(rows, localDay: "2026-01-01").xp, 4)
    }

    func testCompletedTurnsHaveNoRateLimit() {
        var rows = (0..<61).map { LedgerRow(at: Double($0), source: .turn, sessionId: "a", day: "2026-01-01") }
        rows.append(LedgerRow(at: 61, source: .turn, sessionId: "b", day: "2026-01-01"))
        rows.append(LedgerRow(at: 3_600_000, source: .turn, sessionId: "a", day: "2026-01-01"))
        XCTAssertEqual(GrowthFormula().snapshot(rows, localDay: "2026-01-01").xp, 63 * 3)
    }
    func testXPAccumulatesWithoutLevels() {
        let result = GrowthFormula().snapshot([LedgerRow(at: 0, source: .turn, amount: 100_000, day: "2026-01-01")], localDay: "2026-01-01")
        XCTAssertEqual(result.xp, 300_000)
        XCTAssertEqual(result.level, 1)
        XCTAssertEqual(result.xpNext, 0)
    }
    func testStreakBreaksWithoutRestCredits() {
        let days = (1...7).map { String(format: "2026-01-%02d", $0) }
        XCTAssertEqual(Streak.calculate(days: days, through: "2026-01-08").current, 7)
        XCTAssertEqual(Streak.calculate(days: days, through: "2026-01-09").current, 0)
        let resumed = Streak.calculate(days: days + ["2026-01-09"], through: "2026-01-09")
        XCTAssertEqual(resumed.current, 1)
        XCTAssertEqual(resumed.best, 7)
    }
    @MainActor func testEngineAwardsOnlyRealCompletionsAndNoApprovals() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        let (engine, clock) = makeEngine(store: store)
        clock.time = 1_000
        engine.sessionStarted(sessionId:"s", source:"codex", cwd:nil)
        engine.turnStarted(sessionId:"s", source:"codex")
        clock.time += 100
        engine.turnEnded(sessionId:"s", source:"codex", outcome:.completed)
        engine.turnEnded(sessionId:"s", source:"codex", outcome:.completed)
        await engine.flushStore()
        XCTAssertEqual(engine.state.growth.xp, 13)
        let before = try await store.ledger()
        let waiting = Task { await engine.submitApproval(sessionId:"s",requestId:"r",tool:"Bash",hint:"run",sessionLabel:nil,source:"codex") }
        for _ in 0..<20 { if engine.state.prompt != nil { break }; await Task.yield() }
        engine.resolveAllPendingApprovals(decision:.deny)
        _ = await waiting.value
        await engine.flushStore()
        let after = try await store.ledger()
        XCTAssertEqual(after, before)
        engine.sessionEnded(sessionId:"s"); await engine.flushStore()
        XCTAssertEqual(engine.state.growth.tasks, 1)
        XCTAssertEqual(engine.state.growth.xp, 13)
    }
}

extension GrowthTests {
    @MainActor func testTenthTryFixturesAwardExactXPAndPersistSnapshot() async throws {
        for source in ["claude-code","codex","cursor"] {
            let (store, _, cleanup) = try makeStore()
            defer { cleanup() }
            let (engine, clock) = makeEngine(store: store)
            let fixtureSource = source == "codex" ? "claude-code" : source
            let url = try XCTUnwrap(hookFixtureURLs().first { $0.path.contains("/\(fixtureSource)/") && $0.lastPathComponent == "tenth-try.jsonl" })
            for line in try String(contentsOf:url,encoding:.utf8).split(separator:"\n") {
                let payload = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8),source:source,at:0))
                clock.advance(by:100)
                await engine.ingest(payload)
            }
            await engine.flushStore()
            XCTAssertEqual(engine.state.growth.xp,13,source)
            XCTAssertEqual(engine.state.growth.tasks,1,source)
            XCTAssertEqual(engine.state.growth.biggest,.hop)
            let frame = renderState(from:engine.state,now:clock.now())
            XCTAssertEqual(frame.snap?.growth.xp,13)
            XCTAssertEqual(frame.snap?.growth.level,1)
            let restarted = BuddyEngine(clock:clock,store:store)
            restarted.start(); await restarted.flushStore(); restarted.stop()
            XCTAssertEqual(restarted.state.growth,engine.state.growth)
            XCTAssertEqual(restarted.petMemory,engine.petMemory)
        }
    }
    func testTokenPayloadUsageAndCumulativeDelta() async throws {
        for source in ["claude-code","codex","cursor","unknown"] {
            let extractor = Extractor()
            let payload = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"Stop","session_id":"s","usage":{"output_tokens":125000}}"#.utf8),source:source,at:0))
            let output = await extractor.ingest(payload)
            XCTAssertEqual(output.facts.contains(.tokens(output:125000)),false)
        }
        let extractor = Extractor()
        for (count,_) in [(100_000,100_000),(100_000,0),(140_000,40_000)] {
            let data = try JSONSerialization.data(withJSONObject:["hook_event_name":"Stop","session_id":"s","info":["total_token_usage":["output_tokens":count]]])
            let payload = try XCTUnwrap(RawHookPayload.parse(data,source:"codex",at:0))
            let result = await extractor.ingest(payload)
            let tokens = result.facts.compactMap { f -> Int? in if case .tokens(let n) = f { return n }; return nil }
            XCTAssertEqual(tokens.reduce(0,+),0)
        }
    }
}

extension GrowthTests {
    @MainActor func testRepeatedBoopsStillDrainEachAward() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        let (engine, _) = makeEngine(store: store)
        engine.boop()
        await engine.flushStore()
        engine.boop()
        await engine.flushStore()
        let rows = try await store.ledger()
        XCTAssertEqual(rows.filter { $0.source == .checkIn }.count, 0)
        XCTAssertEqual(engine.state.growth.xp, 10)
        let facts = try await store.facts()
        XCTAssertEqual(facts.filter { $0.fact == .checkIn(collected: false) }.count, 2)
    }
}
