import Foundation
import XCTest
@testable import BoopCore

final class RecapTests: XCTestCase {
    func testReplayedTenthTryFactsHaveExactCounts() async throws {
        let url = try XCTUnwrap(hookFixtureURLs().first { $0.lastPathComponent == "tenth-try.jsonl" })
        let extractor = Extractor()
        var state = InternalState.initial(staleMs: 10_000_000, celebrateDurationMs: 4000)
        var facts: [StoredFact] = []
        for (i, line) in try String(contentsOf: url, encoding: .utf8).split(separator: "\n").enumerated() {
            let payload = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: "claude-code", at: Double(i) * 1000))
            let result = await extractor.ingest(payload, localHour: 12)
            facts += result.facts.map { StoredFact(fact: $0, sessionId: payload.sessionId, project: "p", at: payload.timestamp, day: "2026-09-09") }
            for event in result.events {
                state = reduce(state, event)
                facts += state.pendingFacts.map { StoredFact(fact: $0.fact, sessionId: $0.sessionId, project: $0.project, at: $0.at, day: "2026-09-09") }
            }
        }
        let recap = RecapFacts.build(facts)
        XCTAssertEqual(recap.turns, 1); XCTAssertEqual(recap.tasks, 1); XCTAssertEqual(recap.openGoals, 0)
        XCTAssertEqual(recap.biggestMoment?.kind, .hardWonPass)
        XCTAssertGreaterThan(recap.hours, 0)
        let line = await Voice().line(for: VoiceRequest(occasion: .recap(recap), language: "ko", byteCap: 63))
        XCTAssertFalse(line.text.isEmpty); XCTAssertLessThanOrEqual(line.text.utf8.count, 63)
    }
    func testLatestGoalOutcomeAndSummaryDoNotDoubleCount() {
        let inputs: [Fact] = [.goalOutcome(goalKey: "a", runner: "pytest", outcome: .fail, attempts: 1, elapsedMs: 0), .goalOutcome(goalKey: "a", runner: "pytest", outcome: .pass, attempts: 2, elapsedMs: 1), .goalOutcome(goalKey: "b", runner: "pytest", outcome: .unknown, attempts: 1, elapsedMs: 0), .turnCompleted(elapsedMs: 3_600_000), .sessionSummary(turns: 1, tasks: 1, elapsedMs: 3_600_000)]
        let facts = inputs.enumerated().map { StoredFact(fact: $0.element, sessionId: "s", project: "p", at: Double($0.offset), day: "2026-09-09") }
        let recap = RecapFacts.build(facts)
        XCTAssertEqual(recap.turns, 1); XCTAssertEqual(recap.tasks, 1); XCTAssertEqual(recap.hours, 1); XCTAssertEqual(recap.openGoals, 1)
    }
    @MainActor func testEngineRecapSleepLanguageAndOncePerDay() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let clock = MockClock()
        let suite = "voice-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ko", forKey: DefaultsKey.language)
        let engine = BuddyEngine(clock: clock, store: store, voiceRuntime: NullRuntime(), defaults: defaults)
        engine.sessionStarted(sessionId: "s", source: "codex", cwd: nil)
        XCTAssertEqual(engine.state.language, "ko")
        let result = try await engine.makeRecap()
        let recap = try XCTUnwrap(result)
        XCTAssertFalse(recap.line.isEmpty); XCTAssertLessThanOrEqual(recap.line.utf8.count, 63)
        XCTAssertEqual(engine.state.creature.bubble, recap.line)
        clock.advance(by: 4001); engine.triggerStaleTick()
        XCTAssertEqual(engine.state.creature.state, .asleep)
        XCTAssertNil(engine.state.creature.bubble)
        let same = try await engine.makeRecap(force: false)
        XCTAssertEqual(same, recap); XCTAssertNil(engine.state.creature.bubble)
    }
}

extension RecapTests {
    @MainActor func testEngineTenthTryVoiceAndUsualStopFallback() async throws {
        let url = try XCTUnwrap(hookFixtureURLs().first { $0.lastPathComponent == "tenth-try.jsonl" })
        let clock = MockClock()
        let engine = BuddyEngine(clock: clock, voiceRuntime: NullRuntime())
        XCTAssertEqual(engine.usualStopHour(at: clock.now()), 18)
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let payload = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: "claude-code", at: clock.now()))
            await engine.ingest(payload)
            clock.advance(by: 1000)
        }
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.creature.moment?.kind, .hardWonPass)
        XCTAssertFalse(engine.state.creature.giftLine?.isEmpty ?? true)
        XCTAssertNotNil(VoiceFilter.check(engine.state.creature.giftLine ?? "", language: "en", byteCap: 40))
    }
    func testRecapDoesNotCoverWorkOrPromptAndActivityWakesSleeper() {
        var state = InternalState.initial(staleMs: 100000, celebrateDurationMs: 4000)
        state = reduce(state, .sessionStarted(at: 0, sessionId: "s", source: "codex", cwd: nil))
        let recap = Recap(line: "a day to keep", paragraph: "one turn.")
        state = reduce(state, .recapReady(at: 1, recap: recap))
        state = reduce(state, .staleTick(at: 4001))
        XCTAssertEqual(state.buddy.creature.state, .asleep)
        state = reduce(state, .turnStarted(at: 4002, sessionId: "s", source: "codex"))
        XCTAssertEqual(state.buddy.creature.state, .working)
        state = reduce(state, .recapReady(at: 4003, recap: recap))
        XCTAssertNil(state.buddy.creature.bubble)
        XCTAssertEqual(state.buddy.creature.state, .working)
    }
}

extension RecapTests {
    @MainActor func testHistogramStopHourCrossesMidnight() async throws {
        struct UTC: DayCalendar {
            func localDay(at: Double) -> String { "2026-01-20" }
            func previousDay(at: Double) -> String { "2026-01-19" }
            func localHour(at: Double) -> Int { PetMemory.utcHour(ofMs: at) }
        }
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        var memory = PetMemory.empty
        memory.firstSampleAt = 0; memory.histogramSamples = 25
        for hour in [22, 23, 0, 1, 2] { memory.hourHistogram[hour] = 5 }
        try await store.saveMemory(memory)
        let clock = MockClock(); clock.advance(by: 20 * 86_400_000)
        let engine = BuddyEngine(clock: clock, store: store, dayCalendar: UTC(), voiceRuntime: NullRuntime())
        engine.start(); defer { engine.stop() }
        await engine.flushStore()
        XCTAssertEqual(engine.usualStopHour(at: clock.now()), 3)
    }
}
