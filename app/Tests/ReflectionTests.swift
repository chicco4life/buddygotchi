import Foundation
import XCTest
@testable import BoopCore

final class ReflectionTests: XCTestCase {
    private let fact = StoredFact(fact: .toolOutcome(runner: "swift-test", outcome: .pass), sessionId: "PRIVATE_SESSION", project: "PRIVATE_PATH", at: 0, day: "2026-01-01")

    func testModelChoosesMemoryOncePerDayWithoutChangingLegacyTraits() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        try await store.appendFacts([fact])
        let text = #"{"memories":[{"line":"ran swift-test","evidence":[0]}],"traits":{"energy":-1,"bond":2}}"#
        await store.configureVoice(Voice(runtime: VoiceStubRuntime(text: text)), language: "en")
        let lines = try await store.reflect(localDay: fact.day, at: 1)
        XCTAssertEqual(lines.map(\.line), ["ran swift-test"])
        XCTAssertEqual(lines.first?.source, "model")
        let traits = try await store.traits()
        XCTAssertEqual(traits["energy"], 128)
        XCTAssertEqual(traits["bond"], 0)
        _ = try await store.reflect(localDay: fact.day, at: 2)
        let again = try await store.traits()
        XCTAssertEqual(again, traits)
    }

    func testUnavailableInvalidOrSilentModelDoesNotInventLearning() async throws {
        for text in [String?.none, "not JSON", "SILENT", #"{"memories":[{"line":"invented","evidence":[999]}],"traits":{"energy":1}}"#] {
            let (store, _, cleanup) = try makeStore(); defer { cleanup() }
            try await store.appendFacts([fact])
            let before = try await store.traits()
            let voice = text.map { Voice(runtime: VoiceStubRuntime(text: $0)) } ?? Voice()
            await store.configureVoice(voice, language: "en")
            let lines = try await store.reflect(localDay: fact.day, at: 1)
            let after = try await store.traits()
            XCTAssertTrue(lines.isEmpty)
            XCTAssertEqual(after, before)
        }
    }

    func testReflectionBoundaryExcludesPrivateAndApprovalData() throws {
        let denied = StoredFact(fact: .denial, sessionId: "PRIVATE_SESSION", project: "PRIVATE_PATH", at: 1, day: fact.day)
        let evidence = Reflection.evidence([fact, denied])
        XCTAssertEqual(evidence.count, 1)
        let prompt = Reflection.prompt(guide: "CUSTOM LEARNING POLICY", evidence: evidence, profile: [], day: fact.day, language: "en")
        XCTAssertTrue(prompt.contains("CUSTOM LEARNING POLICY"))
        for secret in ["PRIVATE_SESSION", "PRIVATE_PATH", "denial"] { XCTAssertFalse(prompt.contains(secret)) }
        for invalid in [ #"{"memories":[{"line":"unsupported","evidence":[]}],"traits":{}}"#] {
            XCTAssertNil(ReflectionUpdate.decode(invalid, evidenceCount: 1, language: "en"))
        }
    }

    func testGuideIsReadAgainForEachReflection() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("BEHAVIOR.md"), runtime = LearningGuideRuntime()
        let voice = Voice(runtime: runtime, guide: .init(overrideURL: file))
        for policy in ["learning-policy-one", "learning-policy-two"] {
            try policy.write(to: file, atomically: true, encoding: .utf8)
            _ = await voice.reflect(history: [fact], profile: [], day: fact.day, language: "en")
        }
        let prompts = await runtime.prompts
        XCTAssertTrue(prompts[0].contains("learning-policy-one"))
        XCTAssertTrue(prompts[1].contains("learning-policy-two"))
        XCTAssertFalse(prompts[1].contains("learning-policy-one"))
    }
}

private actor LearningGuideRuntime: VoiceRuntime {
    var prompts: [String] = []
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        prompts.append(prompt); return "SILENT"
    }
}

extension ReflectionTests {
    @MainActor func testMaintenanceUsesInjectedCalendarAndPower() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        struct CalendarStub: DayCalendar {
            func localDay(at: Double) -> String { "2026-01-02" }
            func localHour(at: Double) -> Int { 8 }
            func previousDay(at: Double) -> String { "2026-01-01" }
        }
        try await store.appendFacts([StoredFact(fact: .activity(hour: 8, tool: "Bash", firstGoal: "swift-test"), sessionId: "yesterday", project: "p", at: 0, day: "2026-01-01")])
        let clock = MockClock()
        let battery = BuddyEngine(clock: clock, store: store, dayCalendar: CalendarStub(), onACPower: { false }, voiceRuntime: VoiceStubRuntime(text: #"{"memories":[{"line":"used swift-test","evidence":[0]}],"traits":{}}"#))
        battery.sessionStarted(sessionId: "battery", source: "codex", cwd: nil)
        clock.advance(by: 1_200_000)
        battery.maintenance(); await battery.flushStore()
        let empty = try await store.profile()
        XCTAssertTrue(empty.isEmpty)
        let powered = BuddyEngine(clock: clock, store: store, dayCalendar: CalendarStub(), onACPower: { true }, voiceRuntime: VoiceStubRuntime(text: #"{"memories":[{"line":"used swift-test","evidence":[0]}],"traits":{}}"#))
        powered.sessionStarted(sessionId: "powered", source: "codex", cwd: nil)
        clock.advance(by: 1_200_000)
        powered.maintenance(); await powered.flushStore()
        let lines = try await store.profile()
        XCTAssertEqual(lines.map(\.line), ["used swift-test"])
        let facts = try await store.facts()
        XCTAssertTrue(facts.contains { $0.sessionId == "powered" && $0.day == "2026-01-02" && $0.fact == .activity(hour: 8, tool: nil, firstGoal: nil) })
    }
}
