import Foundation
import XCTest
@testable import BoopCore

private actor EssentialRuntime: VoiceRuntime {
    private(set) var calls = 0
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        calls += 1
        return "SILENT"
    }
}

final class EssentialBehaviorTests: XCTestCase {
    func testShortCompletionEarnsXPWithoutCelebratingAndDuplicateEarnsNothing() {
        var state = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        state = reduce(state, .turnStarted(at: 0, sessionId: "s", source: "codex"))
        state.pendingAwards = []
        state = reduce(state, .turnEnded(at: 59_999, sessionId: "s", source: "codex", outcome: .completed))
        XCTAssertEqual(state.buddy.creature.state, .idle)
        XCTAssertNil(state.buddy.celebrateUntil)
        XCTAssertEqual(state.buddy.lastTaskDurationMs, 59_999)
        XCTAssertEqual(state.memory.completedTurns, 1)
        XCTAssertEqual(state.pendingAwards.flatMap(\.sources), [.turn])
        XCTAssertNil(state.pendingAwards.last?.cheer)
        state.pendingAwards = []
        state = reduce(state, .turnEnded(at: 60_000, sessionId: "s", source: "codex", outcome: .completed))
        XCTAssertTrue(state.pendingAwards.isEmpty)
    }

    func testShortCompletionDoesNotInterruptLargerCelebration() {
        var state = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4000)
        state = reduce(state, .turnStarted(at: 0, sessionId: "long", source: "codex"))
        state = reduce(state, .turnStarted(at: 299_000, sessionId: "short", source: "codex"))
        state = reduce(state, .turnEnded(at: 300_000, sessionId: "long", source: "codex", outcome: .completed))
        state = reduce(state, .turnEnded(at: 301_000, sessionId: "short", source: "codex", outcome: .completed))
        XCTAssertEqual(state.buddy.creature.cheer, .dance)
        XCTAssertEqual(state.buddy.celebrateUntil, 304_000)
        XCTAssertEqual(state.memory.completedTurns, 2)
    }

    @MainActor func testMaintenanceNeverCreatesPeriodicDialogue() async {
        let runtime = EssentialRuntime(), clock = MockClock()
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        let engine = BuddyEngine(clock: clock, voiceRuntime: runtime, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        for _ in 0..<4 {
            clock.advance(by: 300_000)
            engine.maintenance()
            await engine.finishPendingWork()
        }
        let calls = await runtime.calls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(engine.state.creature.bubble)
        XCTAssertEqual(engine.state.creature.state, .working)
    }

    @MainActor func testLegacyApprovalCallsCannotHoldOrDecideRequests() async {
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        var config = BuddyConfig.default; config.approvalMode = true
        defaults.set(true, forKey: DefaultsKey.codexApprovalMode)
        let engine = BuddyEngine(config: config, clock: MockClock(), defaults: defaults)
        for source in ["claude-code", "cursor", "codex"] {
            XCTAssertFalse(engine.acceptsBuddyApprovals(source: source))
            let decision = await engine.submitApproval(sessionId: source, requestId: source, tool: "Bash", hint: "rm -rf build", sessionLabel: nil, source: source)
            XCTAssertEqual(decision, .passthrough)
        }
        XCTAssertEqual(engine.state.sessions.total, 0)
        engine.submitRequest(sessionId: "s", requestId: "passive", tool: "Question", hint: "Check editor", sessionLabel: nil)
        engine.handleDeviceCommand(.decision(id: "passive", decision: .allow))
        XCTAssertEqual(engine.state.creature.card?.id, "passive")
        XCTAssertEqual(engine.state.creature.card?.isApproval, false)
    }
}
