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
        // Six soft dots on the dance only (UX-DEVICE.md §20); the app mirrors the device.
        XCTAssertEqual(CreaturePose(from: c).confetti, 6)
        XCTAssertTrue(CreaturePose(from: c).blush)
        c.cheer = .cheer
        XCTAssertEqual(CreaturePose(from: c).confetti, 0)
        c.cheer = .hop
        XCTAssertEqual(CreaturePose(from: c).confetti, 0)
    }
    func testOnboardingOrderAndPermanentName() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
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
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let model = OnboardingModel(defaults: defaults)
        model.observe([DiagnosticEntry(timestamp: 0, category: "hooks", source: "codex", event: "onboardingInstall", detail: "")])
        XCTAssertTrue(model.heardAgents.isEmpty)
        model.observe([DiagnosticEntry(timestamp: 0, category: "hook", source: "codex", event: "SessionStart", detail: "")])
        XCTAssertTrue(model.heardAgents.contains(.codex))
    }
    func testLegacyQuickIsIgnoredAndLanguagePersists() async {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let (engine, _) = makeEngine(defaults: defaults)
        let before = engine.state.version
        XCTAssertNil(parseDeviceLine(#"{"cmd":"quick"}"#))
        XCTAssertEqual(engine.state.version, before)
        await engine.setLanguage("ko")
        XCTAssertEqual(engine.state.language, "ko")
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.language), "ko")
        XCTAssertTrue(engine.diagnosticLog.entries.contains { $0.event == "languageChanged" })
        XCTAssertNil(parseDeviceLine(#"{"cmd":"collect"}"#))
    }
    func testRetireWipesStoreAndRestartsOnboarding() async throws {
        let (store, _, cleanupStore) = try makeStore()
        let (defaults, cleanupDefaults) = makeDefaults()
        defer { cleanupStore(); cleanupDefaults() }
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        try await store.addProfileLine("Morning work", source: "rules", at: 0)
        let (engine, _) = makeEngine(store: store, defaults: defaults)
        engine.turnStarted(sessionId: "s", source: "codex")
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .completed)
        var sent = false
        try await engine.retire(sendToDevice: { sent = true })
        XCTAssertTrue(sent)
        XCTAssertEqual(engine.state.creature.state, .asleep)
        XCTAssertEqual(engine.state.growth.xp, 0)
        let profile = try await store.profile()
        let facts = try await store.facts()
        XCTAssertTrue(profile.isEmpty); XCTAssertTrue(facts.isEmpty)
        XCTAssertNil(defaults.string(forKey: DefaultsKey.buddyName))
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.setupCompleted))
    }
    func testFirstCheerHasNoSyntheticWorkOrXP() {
        let initial = InternalState.initial(staleMs: 60000, celebrateDurationMs: 4000)
        let next = reduce(initial, .onboardingCheer(at: 1000))
        XCTAssertEqual(next.buddy.creature.state, .done)
        XCTAssertEqual(next.buddy.creature.cheer, .hop)
        XCTAssertTrue(next.pendingAwards.isEmpty)
        XCTAssertTrue(next.pendingFacts.isEmpty)
        XCTAssertEqual(next.memory.completedTurns, 0)
        var completed = initial; completed.memory.completedTurns = 1
        let unchanged = reduce(completed, .onboardingCheer(at: 1000))
        XCTAssertNil(unchanged.buddy.celebrateUntil)
    }

    func testDiagnosticCursorSurvivesRingWrapAndStopsAfterAllAgents() {
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        let model = OnboardingModel(defaults: defaults)
        let log = DiagnosticLog(capacity: 1)
        for agent in AgentKind.allCases {
            log.log(category: "hook", source: agent.rawValue, event: "SessionStart", detail: "")
            model.observe(log)
            model.observe(log)
        }
        XCTAssertTrue(model.heardEveryAgent)
        XCTAssertEqual(model.heardAgents.count, AgentKind.allCases.count)
    }

    func testQuietModeAndSoundIntentsUseEngineDefaults() throws {
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        defaults.set(true, forKey: DefaultsKey.focusHoursEnabled)
        defaults.set(0, forKey: DefaultsKey.focusStart)
        defaults.set(0, forKey: DefaultsKey.focusEnd)
        let (engine, _) = makeEngine(defaults: defaults)
        engine.maintenance()
        XCTAssertFalse(engine.quietMode, "Legacy Focus schedules must not activate quiet mode")
        defaults.set(3, forKey: DefaultsKey.soundVolume)
        let before = renderState(from: engine.state, defaults: defaults, now: 0)
        engine.setQuietMode(true)
        XCTAssertTrue(engine.state.creature.focus)
        XCTAssertEqual(SoundSettings.volume(defaults: defaults), 0)
        let quiet = renderState(from: engine.state, defaults: defaults, now: 0)
        XCTAssertEqual(quiet.mute, 0)
        var beforeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as? [String: Any])
        var quietJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(quiet)) as? [String: Any])
        for key in ["focus", "mute"] { beforeJSON.removeValue(forKey: key); quietJSON.removeValue(forKey: key) }
        XCTAssertTrue(NSDictionary(dictionary: beforeJSON).isEqual(to: quietJSON), "Quiet mode must not change any visual field")
        let (reopened, _) = makeEngine(defaults: defaults)
        XCTAssertTrue(reopened.quietMode)
        XCTAssertTrue(reopened.state.creature.focus)
        engine.setQuietMode(false)
        XCTAssertFalse(engine.state.creature.focus)
        XCTAssertEqual(renderState(from: engine.state, defaults: defaults, now: 0).mute, SoundSettings.defaultVolume)
        defaults.set(9, forKey: DefaultsKey.soundVolume)
        XCTAssertEqual(SoundSettings.volume(defaults: defaults), SoundSettings.defaultVolume)
        engine.setBoolSetting(DefaultsKey.soundsEnabled, false)
        XCTAssertTrue(engine.quietMode)
        XCTAssertTrue(engine.state.creature.focus)
    }


    func testWakeUsesCreatureStates() async {
        let (defaults, cleanup) = makeDefaults(); defer { cleanup() }
        let model = OnboardingModel(defaults: defaults)
        XCTAssertEqual(model.wakeCreature.state, .asleep)
        await model.firstWake(reduceMotion: true)
        XCTAssertEqual(model.wakeCreature.state, .idle)
        XCTAssertEqual(model.wakeCreature.overlay, .greet)
        XCTAssertEqual(model.step, .agents)
    }

    func testSceneNamesAreUnique() {
        XCTAssertEqual(Set(CompanionScene.all.map(\.name)).count, CompanionScene.all.count)
        print("PHASE7 SCENES: \(CompanionScene.all.count); chrome scenes: \(CompanionScene.all.filter(\.needsPopover).count); expected renders: \(SnapshotRenderer.expectedRenderCount)")
    }
}
