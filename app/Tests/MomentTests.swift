import Foundation
import XCTest
@testable import BoopCore

final class MomentTests: XCTestCase {
    private func working() -> InternalState {
        var s = InternalState.initial(staleMs: 10_000_000, celebrateDurationMs: 4000)
        s.memory.completedTurns = 1
        return reduce(s, .turnStarted(at: 0, sessionId: "s", source: "codex"))
    }
    private func complete(_ s: InternalState, at: Double = 1000) -> InternalState {
        reduce(s, .turnEnded(at: at, sessionId: "s", source: "codex", outcome: .completed))
    }
    func testHardWonBoundaryAndTuning() {
        var tally = GoalTally(firstAt: 0)
        tally.attempts = 5; tally.attemptsWithoutPass = 5; tally.failures = 4
        var s = reduce(working(), .goalRead(at: 900, sessionId: "s", goal: "p|swift test", outcome: .pass, tally: tally))
        XCTAssertNil(complete(s).buddy.creature.moment)
        tally.attempts = 6; tally.attemptsWithoutPass = 6; tally.failures = 5
        s = reduce(working(), .goalRead(at: 900, sessionId: "s", goal: "p|swift test", outcome: .pass, tally: tally))
        XCTAssertEqual(complete(s).buddy.creature.cheer, .dance)
        XCTAssertEqual(complete(s).buddy.creature.moment?.kind, .hardWonPass)
        var custom = working(); custom.momentThresholds.hardWonFailures = 6
        custom = reduce(custom, .goalRead(at: 900, sessionId: "s", goal: "p|swift test", outcome: .pass, tally: tally))
        XCTAssertNil(complete(custom).buddy.creature.moment)
    }
    func testRedStreakDurationBoundary() {
        var tally = GoalTally(firstAt: 0)
        tally.attempts = 4; tally.failures = 3; tally.consecutiveFailures = 3; tally.firstFailureAt = 0
        let early = reduce(working(), .goalRead(at: 599_999, sessionId: "s", goal: "g", outcome: .pass, tally: tally))
        XCTAssertNil(complete(early, at: 600_000).buddy.creature.moment)
        let ready = reduce(working(), .goalRead(at: 600_000, sessionId: "s", goal: "g", outcome: .pass, tally: tally))
        let finished = complete(ready, at: 600_001)
        XCTAssertEqual(finished.buddy.creature.moment?.kind, .redStreakEnded)
        XCTAssertEqual(finished.buddy.creature.cheer, .dance)
        XCTAssertEqual(finished.buddy.creature.giftLine, "green at last.")
    }
    func testAbsenceBoundary() {
        var s = working(); s.memory.projects["project"] = 0
        s = reduce(s, .sessionStarted(at: 14 * 86_400_000, sessionId: "back", source: "codex", cwd: "/tmp/project"))
        XCTAssertEqual(s.pendingMoments["back"]?.kind, .backAfterAbsence)
        XCTAssertEqual(s.pendingMoments["back"]?.facts["days"], "14")
        XCTAssertEqual(s.memory.projects["project"], 14 * 86_400_000)
    }
    func testSameFileAndLocalHourBoundaries() {
        let early = reduce(working(), .fileEdited(at: 1, sessionId: "s", path: "file.swift", count: 19))
        XCTAssertNil(complete(early).buddy.creature.moment)
        let ready = reduce(working(), .fileEdited(at: 1, sessionId: "s", path: "file.swift", count: 20))
        XCTAssertEqual(complete(ready).buddy.creature.giftLine, "file.swift again.")
        for hour in [0, 4] {
            let night = reduce(working(), .localTurnHour(at: 1, sessionId: "s", hour: hour))
            XCTAssertEqual(complete(night).buddy.creature.giftLine, "late one.")
        }
        for hour in [5, 23] {
            let day = reduce(working(), .localTurnHour(at: 1, sessionId: "s", hour: hour))
            XCTAssertNil(complete(day).buddy.creature.moment)
        }
    }
    func testFirstEverAndBackwardCompatibleMemory() throws {
        var s = working(); s.memory = try JSONDecoder().decode(PetMemory.self, from: Data("{}".utf8))
        s = complete(s)
        XCTAssertEqual(s.buddy.creature.moment?.kind, .firstEver)
        XCTAssertEqual(s.memory.completedTurns, 1)
        s = reduce(s, .staleTick(at: 20_000))
        s = reduce(s, .turnStarted(at: 21_000, sessionId: "s", source: "codex"))
        s = complete(s, at: 22_000)
        XCTAssertNil(s.buddy.creature.moment)
        XCTAssertEqual(s.memory.completedTurns, 2)
    }
    func testUnknownCannotCelebrateAndPassClearsStuck() {
        var tally = GoalTally(firstAt: 0); tally.attempts = 7; tally.attemptsWithoutPass = 7; tally.failures = 6
        var s = reduce(working(), .goalRead(at: 10, sessionId: "s", goal: "g", outcome: .unknown, tally: tally))
        XCTAssertEqual(s.buddy.creature.uhoh, .stuck)
        XCTAssertNil(s.pendingMoments["s"])
        s = reduce(s, .toolResulted(at: 11, sessionId: "s", source: "codex", tool: "Bash", ok: true, durationMs: nil))
        XCTAssertNil(s.buddy.creature.uhoh)
    }
    func testAgentEffortOverridesInference() {
        var s = reduce(working(), .effortReported(at: 1, sessionId: "s", level: .light))
        s = reduce(s, .effortObserved(at: 2, sessionId: "s", level: .grinding))
        XCTAssertEqual(s.buddy.creature.effort, .light)
    }
}
