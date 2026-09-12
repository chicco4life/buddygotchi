import Foundation
import XCTest
@testable import BoopCore

private actor DialogueCounter: VoiceRuntime {
    private(set) var calls = 0
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        calls += 1
        return "SILENT"
    }
}

final class HelpSimplificationTests: XCTestCase {
    func testApprovalFallbackUsesToolWithoutGeneratedExplanation() {
        let (stakes, label) = StakesReader.read(tool: "Bash", input: "rm -rf ./data")
        XCTAssertEqual(stakes, .careful)
        XCTAssertEqual(label, "Bash")
    }

    func testRepeatedWorkAndSilenceDoNotInventFailure() {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        s = reduce(s, .turnStarted(at: 0, sessionId: "s", source: "codex"))
        for i in 1...12 {
            s = reduce(s, .toolCalled(at: Double(i), sessionId: "s", source: "codex", tool: "Bash", hint: "test", goal: "same"))
            XCTAssertEqual(s.buddy.creature.state, .working)
            XCTAssertNil(s.buddy.creature.uhoh)
        }
        s = reduce(s, .staleTick(at: 300_100))
        XCTAssertEqual(s.buddy.creature.state, .working)
        s = reduce(s, .staleTick(at: 600_100))
        XCTAssertEqual(s.buddy.creature.state, .asleep, "Session expiry still works")
    }

    func testQuotaFailuresUseOrdinaryErrorsWithoutSpecialMoments() {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        for i in 1...4 {
            s = reduce(s, .turnStarted(at: Double(i * 10), sessionId: "s", source: "codex"))
            s = reduce(s, .turnEnded(at: Double(i * 10 + 1), sessionId: "s", source: "codex", outcome: .failed(errorClass: "rate_limit")))
            XCTAssertEqual(s.buddy.creature.uhoh, .error)
            XCTAssertNil(s.buddy.creature.cheer)
            XCTAssertFalse(s.pendingFacts.contains { $0.fact == .moment(.nthRateLimit) })
        }
        let historic = StoredFact(fact: .moment(.nthRateLimit), sessionId: "s", project: "p", at: 0, day: "2026-09-10")
        XCTAssertTrue(Reflection.evidence([historic]).isEmpty)
    }

    @MainActor func testCompletionDecisionCanStaySilentWithoutRestoringGifts() async throws {
        let runtime = DialogueCounter(), clock = MockClock()
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        let engine = BuddyEngine(clock: clock, voiceRuntime: runtime, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        clock.advance(by: 60_000)
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.moment?.tier, .full)
        let beforeCompletion = await runtime.calls
        clock.time = try XCTUnwrap(engine.state.moment?.until)
        engine.triggerStaleTick()
        engine.maintenance()
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.creature.state, .idle)
        XCTAssertNil(engine.state.creature.bubble)
        let calls = await runtime.calls
        XCTAssertEqual(calls, beforeCompletion)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(renderState(from: engine.state, defaults: defaults, now: clock.now()))) as? [String: Any])
        XCTAssertEqual(wire["gift"] as? Bool, false)
        XCTAssertNil(wire["giftLine"])
        XCTAssertNil(parseDeviceLine(#"{"cmd":"collect"}"#))
        XCTAssertNil(parseDeviceLine(#"{"cmd":"quick"}"#))
    }
}
