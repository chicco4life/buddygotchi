import Foundation
import XCTest
@testable import BoopCore

@MainActor
final class CompanionTests: XCTestCase {
    func testEveryStatePoseAndUrgencySuppressesAffection() {
        let expected: [CreaturePose.Eyes] = [.closed, .open, .down, .wide, .arc, .half]
        for (index, state) in CreatureState.allCases.enumerated() {
            var c = Creature.initial; c.state = state
            XCTAssertEqual(CreaturePose(from: c).eyes, expected[index])
            c.overlay = .boop
            XCTAssertEqual(CreaturePose(from: c).hearts, [.idle, .working, .done].contains(state))
        }
    }
    func testEffortAndCheerEscalation() {
        var c = Creature.initial; c.state = .working; c.effort = .hard
        XCTAssertTrue(CreaturePose(from: c).sweat)
        XCTAssertFalse(CreaturePose(from: c).tremble)
        c.effort = .grinding
        XCTAssertTrue(CreaturePose(from: c).tremble)
        c.state = .done; c.cheer = .dance
        XCTAssertEqual(CreaturePose(from: c).confetti, 18)
        XCTAssertTrue(CreaturePose(from: c).blush)
        c.cheer = .hop
        XCTAssertEqual(CreaturePose(from: c).confetti, 0)
    }
    func testOnboardingOrderAndPermanentName() {
        let suite = "BoopTests.phase7." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)
        XCTAssertEqual(model.step, .welcome)
        model.advance(); XCTAssertEqual(model.step, .agents)
        model.advance(); XCTAssertEqual(model.step, .display)
        model.advance(); XCTAssertEqual(model.step, .firstContact)
        model.buddyName = "  Mochi  "
        XCTAssertTrue(model.saveName())
        model.buddyName = "Changed"
        XCTAssertTrue(model.saveName())
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.buddyName), "Mochi")
        model.advance(); XCTAssertEqual(model.step, .done)
        model.complete(); XCTAssertTrue(defaults.bool(forKey: DefaultsKey.setupCompleted))
    }
    func testHeardAgentRequiresRealHook() {
        let suite = "BoopTests.phase7." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)
        model.observe([DiagnosticEntry(timestamp: 0, category: "hooks", source: "codex", event: "onboardingInstall", detail: "")])
        XCTAssertTrue(model.heardAgents.isEmpty)
        model.observe([DiagnosticEntry(timestamp: 0, category: "hook", source: "codex", event: "SessionStart", detail: "")])
        XCTAssertTrue(model.heardAgents.contains(.codex))
    }
    func testQuickAndLanguagePersistAndEmit() async {
        let suite = "BoopTests.phase7." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = BuddyEngine(defaults: defaults)
        engine.setQuickCommand("continue with tests")
        XCTAssertEqual(BuddyEngine(defaults: defaults).quickCommand, "continue with tests")
        await engine.setLanguage("ko")
        XCTAssertEqual(engine.state.language, "ko")
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.language), "ko")
        XCTAssertTrue(engine.diagnosticLog.entries.contains { $0.event == "languageChanged" })
        if case .quick? = parseDeviceLine("{\"cmd\":\"quick\"}") {} else { XCTFail("Quick command did not parse") }
    }
    func testTeachOnceOptOutAndRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try Store(stateDir: dir.path, now: 0)
        let first = try await store.claimTool("Bash")
        let second = try await store.claimTool("Bash")
        XCTAssertTrue(first); XCTAssertFalse(second)
        try await store.muteTool("Read")
        let reopened = try Store(stateDir: dir.path, now: 0)
        let muted = try await reopened.claimTool("Read")
        let seen = try await reopened.claimTool("Bash")
        XCTAssertFalse(muted); XCTAssertFalse(seen)
        XCTAssertNotNil(TeachCatalog.line(tool: "Bash", language: "ko"))
    }
    func testRetireWipesStoreAndRestartsOnboarding() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "BoopTests.phase7." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: dir); defaults.removePersistentDomain(forName: suite) }
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        let store = try Store(stateDir: dir.path, now: 0)
        try await store.addProfileLine("Morning work", source: "rules", at: 0)
        _ = try await store.claimTool("Bash")
        let engine = BuddyEngine(store: store, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        var sent = false
        try await engine.retire(sendToDevice: { sent = true })
        XCTAssertTrue(sent)
        XCTAssertEqual(engine.state.creature.state, .asleep)
        XCTAssertEqual(engine.state.growth.xp, 0)
        let profile = try await store.profile()
        let facts = try await store.facts()
        let freshTool = try await store.claimTool("Bash")
        XCTAssertTrue(profile.isEmpty); XCTAssertTrue(facts.isEmpty); XCTAssertTrue(freshTool)
        XCTAssertNil(defaults.string(forKey: DefaultsKey.buddyName))
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.setupCompleted))
    }
    func testFirstCheerHasNoSyntheticWorkOrXP() {
        let initial = InternalState.initial(staleMs: 60000, celebrateDurationMs: 4000)
        let next = reduce(initial, .onboardingCheer(at: 1000, line: "first one"))
        XCTAssertEqual(next.buddy.creature.state, .done)
        XCTAssertEqual(next.buddy.creature.cheer, .hop)
        XCTAssertTrue(next.buddy.creature.gift)
        XCTAssertEqual(next.buddy.creature.giftLine, "first one")
        XCTAssertTrue(next.pendingAwards.isEmpty)
        XCTAssertTrue(next.pendingFacts.isEmpty)
        XCTAssertEqual(next.memory.completedTurns, 0)
        var completed = initial; completed.memory.completedTurns = 1
        let unchanged = reduce(completed, .onboardingCheer(at: 1000, line: "first one"))
        XCTAssertNil(unchanged.buddy.celebrateUntil)
    }

    func testSceneNamesAreUnique() {
        XCTAssertEqual(Set(CompanionScene.all.map(\.name)).count, CompanionScene.all.count)
    }
}
