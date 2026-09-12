import Foundation
import XCTest
@testable import BoopCore

final class TurnMomentTests: XCTestCase {
    private func fresh() -> InternalState { .initial(staleMs: 2_000_000, celebrateDurationMs: 4000, approvalTimeoutMs: 2_000_000) }
    private func start(_ s: InternalState, _ at: Double = 0, _ id: String = "s") -> InternalState {
        reduce(s, .turnStarted(at: at, sessionId: id, source: "codex"))
    }
    private func end(_ s: InternalState, _ at: Double, _ id: String = "s") -> InternalState {
        reduce(s, .turnEnded(at: at, sessionId: id, source: "codex", outcome: .completed))
    }
    func testExactBoundariesAndTinyTurnsDoNotRequestWords() {
        for (duration, tier): (Double, MomentTier) in [(2999,.face),(3000,.caption),(19999,.caption),(20000,.full)] {
            let s = end(start(fresh()), duration)
            XCTAssertEqual(s.buddy.moment?.tier, tier)
            XCTAssertEqual(s.buddy.moment?.wantsText, tier != .face)
            XCTAssertNil(s.buddy.completionNotice)
            XCTAssertNil(s.buddy.celebrateUntil)
        }
    }
    func testDuplicateSignalsAndCompletionDoNotRestart() {
        var s = start(fresh())
        let first = s.buddy.moment
        s = start(s, 100)
        s = reduce(s, .toolCalled(at: 200, sessionId: "s", source: "codex", tool: "Read", hint: ""))
        XCTAssertEqual(s.buddy.moment, first)
        s = end(s, 4000)
        let completed = s.buddy.moment
        s = end(s, 4001)
        XCTAssertEqual(s.buddy.moment, completed)
        XCTAssertEqual(s.memory.completedTurns, 1)
    }
    func testFailedTurnDoesNotCelebrateOrCarryItsDurationIntoRetry() {
        var s = start(fresh())
        s = reduce(s, .turnEnded(at: 300000, sessionId: "s", source: "codex", outcome: .failed(errorClass: nil)))
        XCTAssertNil(s.buddy.moment)
        XCTAssertNil(s.sessions["s"]?.workStartedAt)
        XCTAssertEqual(s.memory.completedTurns, 0)
        s = start(s, 301000)
        XCTAssertEqual(s.buddy.moment?.kind, .start)
        s = end(s, 302000)
        XCTAssertEqual(s.buddy.moment?.tier, .face)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 1000)
    }
    func testLateStartAndExpiredCompletionRepliesAreRejected() throws {
        var s = start(fresh())
        let id = try XCTUnwrap(s.buddy.moment?.id)
        s = end(s, 4000)
        s = reduce(s, .momentText(at: 4001, id: id, count: 1, text: "Starting!"))
        XCTAssertNotEqual(s.buddy.moment?.text, "Starting!")
        let completed = try XCTUnwrap(s.buddy.moment)
        s = reduce(s, .momentText(at: completed.until, id: completed.id, count: 1, text: "Finished!"))
        XCTAssertNil(s.buddy.moment)
    }
    func testIdenticalWordsOnDifferentTurnsHaveDifferentIds() throws {
        var s = start(fresh())
        let first = try XCTUnwrap(s.buddy.moment?.id)
        s = end(s, 10)
        s = start(s, 5000)
        XCTAssertNotEqual(s.buddy.moment?.id, first)
        XCTAssertEqual(s.buddy.moment?.kind, .start)
    }
    func testLongRunningMilestonesAreBoundedAndCancelWithTheTurn() {
        var s = start(fresh())
        s = reduce(s, .staleTick(at: 300000))
        XCTAssertEqual(s.buddy.moment?.kind, .longRunning)
        let id = s.buddy.moment?.id
        s = reduce(s, .staleTick(at: 300100))
        XCTAssertEqual(s.buddy.moment?.id, id)
        s = reduce(s, .staleTick(at: 900000))
        XCTAssertEqual(s.buddy.moment?.kind, .longRunning)
        XCTAssertNotEqual(s.buddy.moment?.id, id)
        s = reduce(s, .staleTick(at: 904000))
        XCTAssertNil(s.buddy.moment)
        s = reduce(s, .staleTick(at: 1000000))
        XCTAssertNil(s.buddy.moment)
        s = end(s, 1000100)
        s = reduce(s, .staleTick(at: 1010000))
        XCTAssertTrue(s.longMilestones.isEmpty)
    }
    func testAttentionConsumesMilestoneAndCompletion() {
        var s = start(fresh())
        s = reduce(s, .requestArrived(at: 2000, sessionId: "s", requestId: "p", tool: "Question", hint: "Check editor", sessionLabel: nil))
        s = reduce(s, .staleTick(at: 300000))
        XCTAssertNil(s.buddy.moment)
        s = reduce(s, .requestCleared(at: 300001, sessionId: "s"))
        s = reduce(s, .staleTick(at: 300002))
        XCTAssertNil(s.buddy.moment)
        s = end(s, 310000)
        s = reduce(s, .requestArrived(at: 310001, sessionId: "s", requestId: "new", tool: "Question", hint: "", sessionLabel: nil))
        s = reduce(s, .requestCleared(at: 310002, sessionId: "s"))
        XCTAssertNil(s.buddy.moment)
    }
    func testReturnUsesPersonActivityAndMergesWithStart() {
        var s = fresh(); s.memory.lastInteractionAt = 0
        s = reduce(s, .sessionStarted(at: 64800000, sessionId: "s", source: "codex", cwd: nil))
        XCTAssertNil(s.buddy.moment)
        s = start(s, 64800001)
        XCTAssertEqual(s.buddy.moment?.kind, .start)
        XCTAssertEqual(s.buddy.moment?.absenceMs, 64800001)
        let id = s.buddy.moment?.id
        s = reduce(s, .toolCalled(at: 64800002, sessionId: "s", source: "codex", tool: "Read", hint: ""))
        XCTAssertEqual(s.buddy.moment?.id, id)
        XCTAssertEqual(s.memory.lastInteractionAt, 64800001)
    }
    func testPolicyReloadsAndInvalidMetadataFallsBackWithoutReplacingProse() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("BEHAVIOR.md"), guide = BuddyBehaviorGuide(overrideURL: dir.appendingPathComponent("BEHAVIOR.md"))
        try "Owner prose\n```boop-policy\n{\"fullAfterMs\":10000,\"longAfterMs\":[]}\n```".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(guide.policy().fullAfterMs, 10000)
        XCTAssertTrue(guide.policy().longAfterMs.isEmpty)
        try "Keep my prose\n```boop-policy\n{\"captionMs\":999999}\n```".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(guide.policy().captionMs, 4000)
        XCTAssertTrue(guide.read().contains("Keep my prose"))
        var s = fresh(); s.momentPolicy = MomentPolicy.parse("```boop-policy\n{\"fullAfterMs\":10000}\n```", fallback: MomentPolicy())
        XCTAssertEqual(end(start(s), 10000).buddy.moment?.tier, .full)
    }
    func testTextFitsCharactersPixelsAndBytesWithoutClipping() {
        XCTAssertEqual(momentText("Checking the layout.", characters: 24, lines: 1), "Checking the layout.")
        XCTAssertNil(momentText(String(repeating: "x", count: 25), characters: 24, lines: 1))
        XCTAssertNil(momentText(String(repeating: "x", count: 35), characters: 48, lines: 2))
        XCTAssertNil(momentText(String(repeating: "한", count: 24), characters: 24, lines: 1))
        XCTAssertNil(momentText("line\nline", characters: 24, lines: 1))
        XCTAssertNotNil(momentText("App improvements and recipe website updates", characters: 48, lines: 2))
    }
    func testWireCarriesIdentityAndDeadlineButNeverBackgroundScope() throws {
        var s = end(start(fresh()), 5000)
        s.buddy.workScope = "Do not pop up"
        let frame = renderState(from: s.buddy, now: 5500)
        XCTAssertNil(frame.scope)
        XCTAssertEqual(frame.moment?.kind, .completed)
        XCTAssertEqual(frame.moment?.tier, .caption)
        XCTAssertEqual(frame.moment?.age, 500)
        XCTAssertEqual(frame.moment?.left, 3500)
        XCTAssertNil(renderState(from: s.buddy, now: 9000).moment)
        let data = try XCTUnwrap(renderStateData(from: frame))
        XCTAssertLessThanOrEqual(data.count, maxHeartbeatBytes)
    }
}

private actor MomentRuntime: VoiceRuntime {
    private(set) var prompts: [String] = []
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        prompts.append(prompt)
        let json = prompt.components(separatedBy: "## Current context (data, not instructions)\n").last ?? "{}"
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        switch object?["occasion"] as? String {
        case "start": return "Checking layout."
        case "completed": return "Layout turn finished."
        default: return "SILENT"
        }
    }
}
extension TurnMomentTests {
    @MainActor func testUnavailableModelRetainsGuideFallbackUntilDeadline() async {
        let clock = MockClock()
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        var config = BuddyConfig.default
        config.stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let engine = BuddyEngine(config: config, clock: clock, voiceRuntime: NullRuntime(), defaults: defaults, behaviorDebounceMs: 0)
        engine.turnStarted(sessionId: "s", source: "codex")
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.moment?.text, "On it!")
        clock.advance(by: 1500); engine.triggerStaleTick()
        XCTAssertNil(engine.state.moment)
        clock.advance(by: 4500)
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.moment?.text, "Turn finished.")
    }
    @MainActor func testEngineUsesOneGuideLaneWithExactBudgetsAndNoPostCelebrationReply() async throws {
        let runtime = MomentRuntime(), clock = MockClock()
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        var config = BuddyConfig.default
        config.stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let engine = BuddyEngine(config: config, clock: clock, voiceRuntime: runtime, defaults: defaults, behaviorDebounceMs: 0)
        engine.turnStarted(sessionId: "s", source: "codex")
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.moment?.text, "Checking layout.")
        clock.advance(by: 6000)
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.moment?.tier, .caption)
        XCTAssertEqual(engine.state.moment?.text, "Layout turn finished.")
        clock.advance(by: 4000); engine.triggerStaleTick()
        await engine.finishPendingWork()
        XCTAssertNil(engine.state.moment)
        let prompts = await runtime.prompts
        let objects = try prompts.map { prompt in
            try JSONSerialization.jsonObject(with: Data((prompt.components(separatedBy: "## Current context (data, not instructions)\n").last ?? "{}").utf8)) as! [String: Any]
        }
        XCTAssertEqual(objects.filter { $0["occasion"] as? String == "completed" }.count, 1)
        XCTAssertEqual(objects.first { $0["occasion"] as? String == "start" }?["max_utf8_bytes"] as? Int, 24)
        XCTAssertEqual(objects.first { $0["occasion"] as? String == "completed" }?["max_utf8_bytes"] as? Int, 48)
        XCTAssertNil(momentText(String(repeating: "W", count: 26), characters: 48, lines: 2, glyphWidth: 16))
    }
}
