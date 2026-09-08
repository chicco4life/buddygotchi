import Foundation
import XCTest
@testable import BoopCore

struct VoiceStubRuntime: VoiceRuntime {
    var text: String = "a quiet little win"
    var delay: Duration = .zero
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        try await Task.sleep(for: delay)
        return text
    }
}
final class VoiceTimingTests: XCTestCase {
    func testThreeSecondRuntimeMeetsOneSecondDeadline() async {
        let voice = Voice(runtime: VoiceStubRuntime(delay: .seconds(3)))
        let start = ContinuousClock.now
        let line = await voice.line(for: VoiceRequest(occasion: .greet(1)))
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(1100))
        XCTAssertEqual(line.source, .authored)
        XCTAssertFalse(line.text.isEmpty)
    }
    func testBannedModelFallsBackAndSafeModelWins() async {
        let request = VoiceRequest(occasion: .cheer(nil, .hop, nil))
        let bad = await Voice(runtime: VoiceStubRuntime(text: "you always break things")).line(for: request)
        XCTAssertEqual(bad.source, .authored)
        let good = await Voice(runtime: VoiceStubRuntime()).line(for: request)
        XCTAssertEqual(good.source, .model)
        XCTAssertEqual(good.text, "a quiet little win")
    }
    func testUncooperativeRuntimeCannotHoldDeadlineOrAccumulate() async {
        actor Runtime: VoiceRuntime {
            var calls = 0
            func generate(prompt: String, maxBytes: Int) async throws -> String? {
                calls += 1
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                return "late model line"
            }
        }
        let runtime = Runtime(), voice = Voice(runtime: runtime)
        let request = VoiceRequest(occasion: .greet(1))
        let start = ContinuousClock.now
        let first = await voice.line(for: request)
        let second = await voice.line(for: request)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(1100))
        XCTAssertEqual(first.source, .authored); XCTAssertEqual(second.source, .authored)
        let calls = await runtime.calls; XCTAssertEqual(calls, 1)
    }
}

extension VoiceTimingTests {
    func testRepeatedModelLineUsesNextAuthoredLine() async {
        let voice = Voice(runtime: VoiceStubRuntime())
        let request = VoiceRequest(occasion: .greet(1))
        let first = await voice.line(for: request)
        let second = await voice.line(for: request)
        XCTAssertEqual(first.source, .model)
        XCTAssertEqual(second.source, .authored)
        XCTAssertNotEqual(first.text, second.text)
    }
    @MainActor func testNewPromptSuppressesLateBubble() async throws {
        let clock = MockClock()
        let engine = BuddyEngine(clock: clock, voiceRuntime: VoiceStubRuntime(delay: .milliseconds(100)))
        engine.turnStarted(sessionId: "s", source: "codex")
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .failed(errorClass: nil))
        await Task.yield()
        engine.submitRequest(sessionId: "s", requestId: "p", tool: "Bash", hint: "check", sessionLabel: nil)
        await engine.finishPendingWork()
        XCTAssertNil(engine.state.creature.bubble)
        XCTAssertEqual(engine.state.creature.card?.id, "p")
    }
}
