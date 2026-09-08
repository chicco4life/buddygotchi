import Foundation
import XCTest
@testable import BoopCore

final class GrowthTests: XCTestCase {
    func testEverySourceAndFormulaRereadsHistory() {
        let rows = XPSource.allCases.map { LedgerRow(at: 0, source: $0, amount: $0 == .tokens ? 100_000 : 1, day: "2026-01-01") }
        let formula = GrowthFormula()
        let awards = Dictionary(uniqueKeysWithValues: formula.awards(rows).map { ($0.0.source, $0.1) })
        XCTAssertEqual(awards, [.turn:3,.task:8,.hardWonPass:12,.activeDay:10,.streakBonus:1,.session:2,.checkIn:1,.tokens:1])
        var tuned = formula; tuned.turn = 7
        XCTAssertEqual(tuned.snapshot(rows, localDay: "2026-01-01").xp - formula.snapshot(rows, localDay: "2026-01-01").xp, 4)
    }
    func testDailyCapsAndTokenRemainders() {
        var rows = (0..<25).map { LedgerRow(at: Double($0), source: .checkIn, day: "2026-01-01") }
        rows += (0..<25).map { LedgerRow(at: Double($0), source: .tokens, amount: 50_000, day: "2026-01-01") }
        rows.append(LedgerRow(at: 100, source: .checkIn, day: "2026-01-02"))
        rows.append(LedgerRow(at: 100, source: .tokens, amount: 100_000, day: "2026-01-02"))
        rows.append(LedgerRow(at: 100, source: .streakBonus, amount: 99, day: "2026-01-02"))
        XCTAssertEqual(GrowthFormula().snapshot(rows, localDay: "2026-01-02").xp, 42)
        XCTAssertEqual(GrowthFormula().snapshot(rows, localDay: "2026-01-02").today, 12)
    }
    func testRollingHourLimitIsPerSession() {
        var rows = (0..<61).map { LedgerRow(at: Double($0), source: .turn, sessionId: "a", day: "2026-01-01") }
        rows.append(LedgerRow(at: 61, source: .turn, sessionId: "b", day: "2026-01-01"))
        rows.append(LedgerRow(at: 3_600_000, source: .turn, sessionId: "a", day: "2026-01-01"))
        XCTAssertEqual(GrowthFormula().snapshot(rows, localDay: "2026-01-01").xp, 62 * 3)
    }
    func testLevelCurveBoundaries() {
        let formula = GrowthFormula()
        for (level,xp) in [(2,150),(5,1200),(10,4950),(20,19950),(30,44950)] {
            XCTAssertEqual(GrowthFormula.threshold(level), xp)
            XCTAssertEqual(formula.level(for: xp), level)
            XCTAssertEqual(formula.level(for: xp-1), level-1)
            XCTAssertEqual(formula.xpToNext(for: xp-1), 1)
            XCTAssertEqual(formula.xpToNext(for: xp), GrowthFormula.threshold(level+1)-xp)
        }
        XCTAssertEqual(formula.level(for: -10), 1)
    }
    func testThirtyDayCalendarAndRestBank() {
        var days: [String] = []
        for day in 1...30 {
            if ![8,16,17,25].contains(day) { days.append(String(format:"2026-01-%02d",day)) }
            let result = Streak.calculate(days: days, through: String(format:"2026-01-%02d",day))
            if day == 7 { XCTAssertEqual(result, Streak(current:7,best:7,rest:1)) }
            if day == 9 { XCTAssertEqual(result, Streak(current:8,best:8,rest:0)) }
            if day == 18 { XCTAssertEqual(result, Streak(current:1,best:14,rest:0)) }
            if day == 30 { XCTAssertEqual(result, Streak(current:12,best:14,rest:0)) }
        }
        let uninterrupted = (1...28).map { String(format:"2026-02-%02d",$0) }
        XCTAssertEqual(Streak.calculate(days: uninterrupted, through:"2026-02-28").rest, 3)
        XCTAssertEqual(Streak.calculate(days:["2026-03-07","2026-03-08","2026-03-09"], through:"2026-03-09").current, 3)
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
        XCTAssertEqual(engine.state.growth.xp, 16)
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
        XCTAssertEqual(engine.state.growth.xp, 24)
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
            XCTAssertEqual(engine.state.growth.xp,36,source)
            XCTAssertEqual(engine.state.growth.tasks,1,source)
            XCTAssertEqual(engine.state.growth.biggest,.dance)
            let frame = renderState(from:engine.state,now:clock.now())
            XCTAssertEqual(frame.snap?.growth.xp,36)
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
            XCTAssertEqual(output.facts.contains(.tokens(output:125000)),["claude-code","codex"].contains(source))
        }
        let extractor = Extractor()
        for (count,expected) in [(100_000,100_000),(100_000,0),(140_000,40_000)] {
            let data = try JSONSerialization.data(withJSONObject:["hook_event_name":"Stop","session_id":"s","info":["total_token_usage":["output_tokens":count]]])
            let payload = try XCTUnwrap(RawHookPayload.parse(data,source:"codex",at:0))
            let result = await extractor.ingest(payload)
            let tokens = result.facts.compactMap { f -> Int? in if case .tokens(let n) = f { return n }; return nil }
            XCTAssertEqual(tokens.reduce(0,+),expected)
        }
    }
}

extension GrowthTests {
    @MainActor func testUnchangedCollectProjectionStillDrainsEachAward() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        let (engine, _) = makeEngine(store: store)
        engine.collectArrived()
        await engine.flushStore()
        engine.collectArrived()
        await engine.flushStore()
        let rows = try await store.ledger()
        XCTAssertEqual(rows.filter { $0.source == .checkIn }.count, 2)
        XCTAssertEqual(engine.state.growth.xp, 13)
        let facts = try await store.facts()
        XCTAssertEqual(facts.filter { $0.fact == .checkIn(collected: false) }.count, 2)
    }
}
