import XCTest
@testable import BoopCore

/// System P (personality) and the reducer half of System E (embodiment).
/// Covers the plan's testable invariants: greet thresholds, circadian
/// cold-start neutrality, effort tiers and payoff scaling, S1 suppression,
/// S8 lease expiry, and S9 (approvals never feed the bond).
final class PersonalityReducerTests: XCTestCase {

    private let hourMs: Double = 3_600_000
    private let dayMs: Double = 24 * 3_600_000

    /// A memory with two weeks of history, all activity in `activeHour`.
    /// `now` anchors the age so circadianReady is true.
    private func trainedMemory(activeHour: Int, now: Double) -> PetMemory {
        var memory = PetMemory.empty
        memory.hourHistogram[activeHour] = 30
        memory.histogramSamples = 30
        memory.firstSampleAt = now - 15 * dayMs
        memory.lastSampleAt = now - hourMs
        memory.lastSeenAt = now - hourMs
        return memory
    }

    /// Timestamp at an exact UTC hour, later than NOW so events stay ordered.
    private func timestamp(atHour hour: Int) -> Double {
        // NOW (1_000_000 ms) sits inside hour 0 of day 0; jump to day 30.
        Double(30 * 24 + hour) * hourMs
    }

    // MARK: - P1 Absence-warmth

    func testFirstEverSessionDoesNotGreet() {
        let s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertNil(s.buddy.greetUntil)
    }

    func testShortGapDoesNotGreet() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        s = applyEvents(s, .sessionStarted(at: NOW + 2 * hourMs, sessionId: "s2", source: "claude-code", cwd: nil))
        XCTAssertNil(s.buddy.greetUntil)
    }

    func testReturnAfterAbsenceGreets() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        let back = NOW + 20 * hourMs
        s = applyEvents(s, .sessionStarted(at: back, sessionId: "s2", source: "claude-code", cwd: nil))
        XCTAssertEqual(s.buddy.greetLevel, 1)
        XCTAssertEqual(s.buddy.greetUntil, back + PetTuning.greetShortMs)
        // The greeting shows as affection over the calm base state.
        XCTAssertEqual(s.buddy.pet.state, .heart)
    }

    func testWeekAwayEarnsTheBigGreeting() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        let back = NOW + 9 * dayMs
        s = applyEvents(s, .sessionStarted(at: back, sessionId: "s2", source: "claude-code", cwd: nil))
        XCTAssertEqual(s.buddy.greetLevel, 2)
        XCTAssertEqual(s.buddy.greetUntil, back + PetTuning.greetBigMs)
    }

    func testGreetExpiresViaStaleTick() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        let back = NOW + 20 * hourMs
        s = applyEvents(s, .sessionStarted(at: back, sessionId: "s2", source: "claude-code", cwd: nil))
        s = applyEvents(s, .staleTick(at: back + PetTuning.greetShortMs + 100))
        XCTAssertNil(s.buddy.greetUntil)
        XCTAssertNil(s.buddy.greetLevel)
        XCTAssertEqual(s.buddy.pet.state, .idle)
    }

    func testGreetNeverOutranksAttention() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        let back = NOW + 20 * hourMs
        s = applyEvents(
            s,
            .sessionStarted(at: back, sessionId: "s2", source: "claude-code", cwd: nil),
            .requestArrived(at: back + 1, sessionId: "s2", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil)
        )
        XCTAssertEqual(s.buddy.pet.state, .attention)
    }

    // MARK: - P2 Circadian











    func testHistogramSamplesAtMostEveryHalfHour() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .activitySignal(at: NOW + 60_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"))
        XCTAssertEqual(s.memory.histogramSamples, 1)
        s = applyEvents(s, .activitySignal(at: NOW + 31 * 60_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"))
        XCTAssertEqual(s.memory.histogramSamples, 2)
    }

    func testLifetimeSessionsCountsNewSessionsOnly() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionStarted(at: NOW + 1, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertEqual(s.memory.lifetimeSessions, 1)
        s = applyEvents(s, .sessionStarted(at: NOW + 2, sessionId: "s2", source: "cursor", cwd: nil))
        XCTAssertEqual(s.memory.lifetimeSessions, 2)
    }

    // MARK: - P3 Effort & payoff

    func testFreshWorkIsLightEffort() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"))
        XCTAssertEqual(s.buddy.pet.state, .busy)
        XCTAssertEqual(s.buddy.effortTier, .light)
    }

    func testLongWorkEscalatesToHardThenGrinding() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"))
        s = applyEvents(s, .activitySignal(at: NOW + 11 * 60_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"))
        XCTAssertEqual(s.buddy.effortTier, .hard)
        s = applyEvents(s, .activitySignal(at: NOW + 26 * 60_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"))
        XCTAssertEqual(s.buddy.effortTier, .grinding)
    }

    func testErrorsDoNotEscalateEffort() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(
            s,
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 3, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 4, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 5, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x")
        )
        XCTAssertEqual(s.buddy.effortTier, .light)
    }


    func testQuickCleanTaskGetsModestCelebration() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(
            s,
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 30_000, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: "Bash", hint: "x")
        )
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.celebrateIntensity, 1)
    }

    func testShortStruggleStillGetsHop() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(
            s,
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 3, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 4, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 5, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 6, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: "Bash", hint: "x")
        )
        XCTAssertEqual(s.buddy.celebrateIntensity, 1)
        XCTAssertEqual(s.memory.lifetimeCelebrations, 1)
        // The struggle is spent: the next task starts clean.
    }

    func testCelebrateIntensityClearsWithTheWindow() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(
            s,
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: "Bash", hint: "x"),
            .staleTick(at: NOW + 2 + 4_001)
        )
        XCTAssertNil(s.buddy.celebrateIntensity)
    }

    // MARK: - S9: approvals never feed the bond

    func testApprovalResolutionLeavesMemoryAndJoyUntouched() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil, source: "claude-code")
        )
        let memoryBefore = s.memory
        s = applyEvents(s, .approvalResolved(at: NOW + 2, sessionId: "s1", requestId: "r1", decision: .allow))
        XCTAssertEqual(s.memory, memoryBefore)
        XCTAssertNil(s.buddy.celebrateIntensity)
        XCTAssertNotEqual(s.buddy.pet.state, .celebrate)
    }

    // MARK: - Persistence seed

    func testMemoryLoadedSeedsWithoutCountingAsPresence() {
        var memory = PetMemory.empty
        memory.lastSeenAt = NOW - 30 * dayMs
        memory.lifetimeSessions = 42
        let s = applyEvents(.test(), .memoryLoaded(at: NOW, memory: memory))
        XCTAssertEqual(s.memory.lifetimeSessions, 42)
        // Loading is not presence: no greet fires, lastSeenAt is untouched...
        XCTAssertNil(s.buddy.greetUntil)
        XCTAssertEqual(s.memory.lastSeenAt, NOW - 30 * dayMs)

        // ...so the FIRST real arrival after launch gets the month-away hug.
        let s2 = applyEvents(s, .sessionStarted(at: NOW + 1, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertEqual(s2.buddy.greetLevel, 2)
    }
}
