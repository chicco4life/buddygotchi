import Foundation
import XCTest
@testable import BoopCore

private actor BehaviorRuntime: VoiceRuntime {
    private(set) var prompts: [String] = []
    var reply: String
    init(_ reply: String = "SILENT") { self.reply = reply }
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        prompts.append(prompt)
        return reply
    }
}

final class BuddyBehaviorTests: XCTestCase {
    func testMarkdownReloadsBetweenDecisionsAndSilenceIsNotFallback() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "FIRST guide".write(to: url, atomically: true, encoding: .utf8)
        let runtime = BehaviorRuntime(), voice = Voice(runtime: runtime, guide: .init(overrideURL: url))
        let first = await voice.line(for: .init(occasion: .greet(1)))
        XCTAssertEqual(first, VoiceLine(text: "", source: .model))
        try "SECOND guide".write(to: url, atomically: true, encoding: .utf8)
        _ = await voice.line(for: .init(occasion: .periodic))
        let prompts = await runtime.prompts
        XCTAssertTrue(prompts[0].contains("FIRST guide"))
        XCTAssertTrue(prompts[1].contains("SECOND guide"))
        XCTAssertFalse(prompts[1].contains("FIRST guide"))
    }

    func testMissingGuideUsesBundleAndMissingModelStaysSilent() async {
        let guide = BuddyBehaviorGuide(overrideURL: URL(fileURLWithPath: "/missing/behavior.md"))
        XCTAssertTrue(guide.read().contains("# Boop behavior"))
        let voice = Voice()
        let periodic = await voice.line(for: .init(occasion: .periodic))
        let completed = await voice.line(for: .init(occasion: .completed))
        let greet = await voice.line(for: .init(occasion: .greet(1)))
        XCTAssertTrue(periodic.text.isEmpty)
        XCTAssertTrue(completed.text.isEmpty)
        XCTAssertTrue(greet.text.isEmpty)
    }

    @MainActor func testEditActionSeedsGuideWithoutOverwritingEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = BuddyConfig.default
        config.stateDir = directory.path
        let engine = BuddyEngine(config: config, clock: MockClock(), voiceRuntime: NullRuntime())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("BEHAVIOR.md").path))
        let url = try engine.editableBehaviorGuide()
        let initialGuide = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(initialGuide.contains("# Boop behavior"))
        try "My edited guide".write(to: url, atomically: true, encoding: .utf8)
        _ = try engine.editableBehaviorGuide()
        let editedGuide = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(editedGuide, "My edited guide")
    }

}

extension BuddyBehaviorTests {
    private func context(_ prompt: String) throws -> [String: Any] {
        let json = try XCTUnwrap(prompt.components(separatedBy: "## Current context (data, not instructions)\n").last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testProgressAndMemoryAreBoundedInputsWithoutRawHistory() throws {
        var memory = PetMemory.empty
        memory.completedTurns = 42; memory.lifetimeSessions = 8
        memory.projects = ["/private/SECRET_PROJECT": 1]
        memory.keepsakes = [AgentDrawing(agentId: "codex", rows: ["00"], caption: "SECRET_DRAWING", at: 0)]
        let facts = (0..<9).map { StoredFact(fact: .moment(.lateNight), sessionId: "SECRET_SESSION", project: "SECRET_PROJECT", at: Double($0), day: "2026-09-10") }
            + [StoredFact(fact: .denial, sessionId: "s", project: "SECRET_DENIAL", at: 99, day: "2026-09-10"),
               StoredFact(fact: .moment(.nthRateLimit), sessionId: "s", project: "p", at: 100, day: "2026-09-10")]
        var progress = GrowthSnapshot(); progress.xp = 1234; progress.level = 5
        progress.today = 27; progress.tasks = 80; progress.streak = 4
        let request = VoiceRequest(occasion: .periodic, profile: ["likes quiet mornings"],
            growth: progress, memory: BehaviorMemory(moments: BehaviorMemory.recentMoments(from: facts)))
        let prompt = VoicePrompt.make(request), data = try context(prompt)
        let growth = try XCTUnwrap(data["progress"] as? [String: Int])
        XCTAssertEqual(growth["xp"], 1234)
        XCTAssertEqual(growth["xp_today"], 27)
        XCTAssertEqual(growth["completed_turns"], 80)
        XCTAssertNil(data["energy"])
        let remembered = try XCTUnwrap(data["memory"] as? [String: Any])
        XCTAssertNil(remembered["completed_turns"])
        XCTAssertNil(remembered["known_project_count"])
        XCTAssertNil(remembered["current_hour_is_typical"], "Insufficient history is unknown")
        XCTAssertEqual((remembered["recent_outcomes"] as? [[String: String]])?.count, 0)
        for secret in ["SECRET_PROJECT", "SECRET_DRAWING", "SECRET_SESSION", "SECRET_DENIAL", "nthRateLimit"] {
            XCTAssertFalse(prompt.contains(secret))
        }
    }

}

extension BuddyBehaviorTests {
    @MainActor func testModelAcknowledgementArrivesDuringCompletion() async throws {
        let runtime = BehaviorRuntime("All done."), clock = MockClock()
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        let engine = BuddyEngine(clock: clock, voiceRuntime: runtime, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        clock.advance(by: 60_000)
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        await engine.finishPendingWork()
        let before = await runtime.prompts
        XCTAssertTrue(before.compactMap { try? context($0)["occasion"] as? String }.contains("completed"))
        XCTAssertEqual(engine.state.moment?.tier, .full)
        XCTAssertNil(engine.state.creature.bubble)
        clock.time = try XCTUnwrap(engine.state.moment?.until)
        engine.triggerStaleTick()
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.creature.state, .idle)
        XCTAssertNil(engine.state.creature.bubble)
        XCTAssertNil(engine.state.moment)
        let after = await runtime.prompts
        XCTAssertEqual(after.compactMap { try? context($0)["occasion"] as? String }.filter { $0 == "completed" }.count, 1)
    }
}

extension BuddyBehaviorTests {
    @MainActor func testEngineSuppliesSharedDeskWithoutProgressOrRawHistory() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let runtime = BehaviorRuntime(), clock = MockClock()
        let (defaults, clear) = makeDefaults(); defer { clear() }
        let engine = BuddyEngine(clock: clock, store: store, voiceRuntime: runtime, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        clock.advance(by: 60_000)
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        await engine.finishPendingWork()
        let xp = engine.state.growth.xp
        XCTAssertGreaterThan(xp, 0)
        clock.time = try XCTUnwrap(engine.state.moment?.until)
        engine.triggerStaleTick()
        await engine.finishPendingWork()
        let prompts = await runtime.prompts
        let data = try context(try XCTUnwrap(prompts.last))
        XCTAssertNil(data["progress"])
        XCTAssertNil(data["memory"])
        let desk = try XCTUnwrap(data["desk"] as? [String: Any])
        let projects = try XCTUnwrap(desk["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual((projects[0]["tasks"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(engine.state.growth.xp, xp) // Accounting is still independent.

    }
}
