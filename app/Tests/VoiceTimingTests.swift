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
        let voice = Voice(runtime: VoiceStubRuntime(delay: .seconds(3)), deadlineMs: 1_000)
        let start = ContinuousClock.now
        let line = await voice.line(for: VoiceRequest(occasion: .greet(1)))
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(1100))
        XCTAssertEqual(line.source, .authored)
        XCTAssertFalse(line.text.isEmpty)
    }
    func testInvalidDisplayFallsBackAndValidModelWins() async {
        let request = VoiceRequest(occasion: .greet(1))
        let bad = await Voice(runtime: VoiceStubRuntime(text: "line\nwith control")).line(for: request)
        XCTAssertEqual(bad.source, .authored)
        let good = await Voice(runtime: VoiceStubRuntime()).line(for: request)
        XCTAssertEqual(good.source, .model)
        XCTAssertEqual(good.text, "a quiet little win")
    }
    func testUncooperativeRuntimeCannotSuppressLaterLines() async {
        actor Runtime: VoiceRuntime {
            var calls = 0
            func generate(prompt: String, maxBytes: Int) async throws -> String? {
                calls += 1
                if calls > 1 { return "a fresh model line" }
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                return "late model line"
            }
        }
        let runtime = Runtime(), voice = Voice(runtime: runtime, deadlineMs: 1_000)
        let request = VoiceRequest(occasion: .greet(1))
        let start = ContinuousClock.now
        let first = await voice.line(for: request)
        let second = await voice.line(for: request)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(1100))
        XCTAssertEqual(first.source, .authored); XCTAssertEqual(second.source, .model)
        let calls = await runtime.calls; XCTAssertEqual(calls, 2)
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

extension VoiceTimingTests {
    func testModelWinDoesNotConsumeFallback() async {
        actor Once: VoiceRuntime {
            var first = true
            func generate(prompt: String, maxBytes: Int) async throws -> String? {
                defer { first = false }
                return first ? "a model visitor" : nil
            }
        }
        let request = VoiceRequest(occasion: .greet(1))
        let baseline = await Voice(localDay: { "day" }).line(for: request)
        let voice = Voice(runtime: Once(), localDay: { "day" })
        _ = await voice.line(for: request)
        let fallback = await voice.line(for: request)
        XCTAssertEqual(fallback, baseline)
    }
    func testExclusionsLoadOncePerLanguageAndDay() async throws {
        actor Day {
            var value = "2026-09-09"
            func advance() { value = "2026-09-10" }
        }
        let (base, _, cleanup) = try makeStore(); defer { cleanup() }
        let store = CountingVoiceStore(base: base), day = Day()
        let voice = Voice(store: store, localDay: { await day.value })
        for _ in 0..<10 { _ = await voice.line(for: VoiceRequest(occasion: .greet(1))) }
        var reads = await store.exclusionReads
        XCTAssertEqual(reads, 1)
        _ = await voice.line(for: VoiceRequest(occasion: .greet(1), language: "ko"))
        reads = await store.exclusionReads; XCTAssertEqual(reads, 2)
        await day.advance()
        _ = await voice.line(for: VoiceRequest(occasion: .greet(1)))
        reads = await store.exclusionReads; XCTAssertEqual(reads, 3)
        let remembered = await store.remembered
        XCTAssertEqual(remembered.count, 2)
        XCTAssertEqual(Set(remembered).count, 2)
    }
    func testParagraphAndProfileDoNotEnterHistory() async throws {
        let (base, _, cleanup) = try makeStore(); defer { cleanup() }
        let store = CountingVoiceStore(base: base)
        let voice = Voice(store: store)
        let paragraph = VoiceRequest(occasion: .profileLine("a familiar rhythm"), byteCap: VoiceCap.profile.rawValue)
        let first = await voice.line(for: paragraph), second = await voice.line(for: paragraph)
        XCTAssertFalse(first.text.isEmpty); XCTAssertEqual(first, second)
        _ = await voice.line(for: VoiceRequest(occasion: .profileLine("a familiar rhythm")))
        let reads = await store.exclusionReads, remembered = await store.remembered
        XCTAssertEqual(reads, 0); XCTAssertTrue(remembered.isEmpty)
    }
}
