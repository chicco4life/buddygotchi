import Foundation
import XCTest
@testable import BoopCore

@MainActor
private final class HeldVoiceLine {
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var entered = false
    func produce() async -> String? {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ line: String) { continuation?.resume(returning: line); continuation = nil }
}

private actor HeldVoiceRuntime: VoiceRuntime {
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var entered = false
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: "a quiet little win"); continuation = nil }
}

final class TransientVoiceTests: XCTestCase {
    @MainActor private func waitFor(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Voice operation did not start")
        throw LeaderboardError.unavailable("test timeout")
    }

    @MainActor func testReplacementSuppressesOldLineAndKeepsOtherLane() async throws {
        let tasks = TransientVoiceTasks(), old = HeldVoiceLine(), gift = HeldVoiceLine(), latest = HeldVoiceLine()
        var delivered: [String] = []
        tasks.replace(.bubble, produce: { await old.produce() }, deliver: { delivered.append($0) })
        tasks.replace(.gift, produce: { await gift.produce() }, deliver: { delivered.append($0) })
        try await waitFor { old.entered && gift.entered }
        tasks.replace(.bubble, produce: { await latest.produce() }, deliver: { delivered.append($0) })
        try await waitFor { latest.entered }
        old.finish("old")
        gift.finish("gift")
        latest.finish("latest")
        await tasks.finish()
        XCTAssertEqual(Set(delivered), Set(["gift", "latest"]))
        XCTAssertEqual(delivered.count, 2)
    }

    @MainActor func testCancelAllRejectsUncooperativeLines() async throws {
        let tasks = TransientVoiceTasks(), bubble = HeldVoiceLine(), gift = HeldVoiceLine()
        var delivered: [String] = []
        tasks.replace(.bubble, produce: { await bubble.produce() }, deliver: { delivered.append($0) })
        tasks.replace(.gift, produce: { await gift.produce() }, deliver: { delivered.append($0) })
        try await waitFor { bubble.entered && gift.entered }
        tasks.cancelAll()
        bubble.finish("bubble"); gift.finish("gift")
        await tasks.finish()
        XCTAssertTrue(delivered.isEmpty)
    }

    @MainActor func testLanguageRuntimeAndStopSuppressPendingBubble() async throws {
        for action in ["language", "runtime", "stop"] {
            let suite = "voice-cancel-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let runtime = HeldVoiceRuntime()
            let engine = BuddyEngine(clock: MockClock(), voiceRuntime: runtime, defaults: defaults)
            engine.turnStarted(sessionId: "s", source: "codex")
            engine.turnEnded(sessionId: "s", source: "codex", outcome: .failed(errorClass: nil))
            try await waitFor { await runtime.entered }
            if action == "language" { await engine.setLanguage("ko") }
            else if action == "runtime" { await engine.setVoiceRuntime("off") }
            else { engine.stop() }
            let bubble = engine.state.creature.bubble
            await runtime.finish()
            await engine.finishPendingWork()
            XCTAssertEqual(engine.state.creature.bubble, bubble, action)
        }
    }

    @MainActor func testCollectedGiftRejectsPendingVoice() async throws {
        let suite = "gift-cancel-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = HeldVoiceRuntime(), clock = MockClock()
        let engine = BuddyEngine(clock: clock, voiceRuntime: runtime, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        try await waitFor { await runtime.entered }
        clock.time = try XCTUnwrap(engine.state.celebrateUntil)
        engine.triggerStaleTick()
        XCTAssertTrue(engine.state.creature.gift)
        engine.collectArrived()
        let line = engine.state.creature.giftLine
        await runtime.finish()
        await engine.finishPendingWork()
        XCTAssertFalse(engine.state.creature.gift)
        XCTAssertEqual(engine.state.creature.giftLine, line)
    }
}
