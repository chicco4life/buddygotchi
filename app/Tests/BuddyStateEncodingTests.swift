import Foundation
import XCTest
@testable import BoopCore

final class BuddyStateEncodingTests: XCTestCase {
    private func samples() -> [BuddyState] {
        var full = BuddyState.initial
        full.language = "ko"
        full.growth.xp = 200
        full.cosmetic = .init(skin: "mint", accessory: "sprout", silhouette: "round")
        full.version = 42; full.updatedAt = 1000
        full.desktop = .init(status: .connected, lastHeartbeatAt: 900)
        full.sessions = .init(total: 3, running: 2, waiting: 1)
        full.msg = "fixture"; full.entries = ["one", "둘"]
        full.prompt = .init(stakes: .careful, gloss: "Run tests", id: "p", tool: "Bash", hint: "test", arrivedAt: 700, sessionLabel: "project", source: "codex", isApproval: true, activityKind: .work)
        full.devicePosture = .perch; full.deviceBattery = .init(pct: 73, charging: true)
        full.creature = Creature(state: .done,
            effort: .grinding, cheer: .dance, uhoh: .error, overlay: .greet, greetLevel: 3,
            dots: 3, dotAlert: 1, card: .init(id: "p", tool: "Bash", gloss: "Run tests", stakes: .careful, index: 0, count: 2, isApproval: true),
            bubble: "반가워", focus: true, nudgeRung: 2)
        full.species = "custom"
        full.celebrateUntil = 2000; full.affectionUntil = 1800
        full.lastTaskDurationMs = 500; full.lastCompletionAt = 900
        full.lastCompleted = .init(id: "s", tool: "Bash", hint: "test", source: "codex", sessionLabel: "project", durationMs: 500, completedAt: 900)
        full.firstErrored = .init(id: "e", source: "cursor", sessionLabel: "project", tool: "Bash", hint: "build", workStartedAt: 600)
        full.activeSessions = [.init(cheer: .hop, effort: .hard, id: "s", source: "codex", state: .working, sessionLabel: "project", currentTool: "Bash")]
        full.currentActivityKind = .work
        full.greetUntil = 1600; full.greetLevel = 2
        full.effortTier = .hard
        var samples = [BuddyState.initial, full]
        for state in CreatureState.allCases {
            var sample = BuddyState.initial
            sample.creature.state = state
            if state == .done { sample.creature.cheer = .cheer }
            if state == .uhoh { sample.creature.uhoh = .error }
            samples.append(sample)
            sample.creature.overlay = .boop
            samples.append(sample)
        }
        return samples
    }

    func testDiagnosticEncodingMatchesPreMigrationBaseline() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/state/diagnostic-before-projections.json")
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! NSArray
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(samples())) as! NSArray
        XCTAssertEqual(actual, expected)
    }

    func testLegacyValuesFollowCreatureWithoutReducerResynchronization() {
        var state = BuddyState.initial
        state.species = "custom"
        state.creature.state = .working
        XCTAssertEqual(state.pet, Pet(state: .busy, species: "custom"))
        XCTAssertEqual(state.lastSignal, "busy")
        state.creature.overlay = .boop
        XCTAssertEqual(state.pet.state, .heart)
        XCTAssertEqual(state.lastSignal, "busy")
        state.creature.state = .done
        state.creature.cheer = .dance
        XCTAssertEqual(state.celebrateIntensity, 3)
        state.creature = .initial
        XCTAssertEqual(state.pet, Pet(state: .sleep, species: "custom"))
        XCTAssertNil(state.lastSignal)
        XCTAssertNil(state.celebrateIntensity)
    }
}
