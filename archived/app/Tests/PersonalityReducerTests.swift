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

    func testCircadianColdStartStaysNeutral() {
        // A handful of samples is not a pattern: no surprise, no expectant.
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        s = applyEvents(s, .sessionStarted(at: NOW + hourMs, sessionId: "s2", source: "claude-code", cwd: nil))
        XCTAssertNil(s.buddy.mood)
        s = applyEvents(s, .sessionEnded(at: NOW + hourMs + 1, sessionId: "s2"))
        s = applyEvents(s, .staleTick(at: NOW + 2 * hourMs))
        XCTAssertNil(s.buddy.mood)
    }

    func testSessionAtUnusualHourSurprises() {
        let start = timestamp(atHour: 3)
        var s = applyEvents(.test(), .memoryLoaded(at: start - 1, memory: trainedMemory(activeHour: 12, now: start)))
        s = applyEvents(s, .sessionStarted(at: start, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertEqual(s.buddy.mood, .surprised)
        XCTAssertEqual(s.buddy.moodUntil, start + PetTuning.surpriseMoodMs)

        // Then it settles in with you.
        s = applyEvents(s, .staleTick(at: start + PetTuning.surpriseMoodMs + 100))
        XCTAssertNil(s.buddy.mood)
    }

    func testSessionAtTypicalHourDoesNotSurprise() {
        let start = timestamp(atHour: 12)
        var s = applyEvents(.test(), .memoryLoaded(at: start - 1, memory: trainedMemory(activeHour: 12, now: start)))
        s = applyEvents(s, .sessionStarted(at: start, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertNil(s.buddy.mood)
    }

    func testExpectantAtTypicalHourWhileDisconnected() {
        let tick = timestamp(atHour: 12)
        var s = applyEvents(.test(), .memoryLoaded(at: tick - 1, memory: trainedMemory(activeHour: 12, now: tick)))
        s = applyEvents(s, .staleTick(at: tick))
        XCTAssertEqual(s.buddy.mood, .expectant)
        // Expectant is the one thing that wakes the pet without a session.
        XCTAssertEqual(s.buddy.pet.state, .idle)

        // Off-hours: back to sleep, no anticipation.
        s = applyEvents(s, .staleTick(at: timestamp(atHour: 20)))
        XCTAssertNil(s.buddy.mood)
        XCTAssertEqual(s.buddy.pet.state, .sleep)
    }

    func testSessionStartClearsExpectant() {
        let tick = timestamp(atHour: 12)
        var s = applyEvents(.test(), .memoryLoaded(at: tick - 1, memory: trainedMemory(activeHour: 12, now: tick)))
        s = applyEvents(s, .staleTick(at: tick))
        XCTAssertEqual(s.buddy.mood, .expectant)
        s = applyEvents(s, .sessionStarted(at: tick + 1, sessionId: "s1", source: "claude-code", cwd: nil))
        XCTAssertNil(s.buddy.mood)
    }

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

    func testErrorsEscalateEffort() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(
            s,
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 3, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 4, sessionId: "s1", source: "claude-code", signal: .error, tool: "Bash", hint: "x"),
            .activitySignal(at: NOW + 5, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "x")
        )
        XCTAssertEqual(s.buddy.effortTier, .hard)
    }

    func testReportedEffortOverridesHeuristic() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x"))
        s = applyEvents(s, .effortReported(at: NOW + 2, sessionId: "s1", level: .grinding))
        XCTAssertEqual(s.buddy.effortTier, .grinding)
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

    func testLongStruggleEarnsTheBigCelebration() {
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
        XCTAssertEqual(s.buddy.celebrateIntensity, 3)
        XCTAssertEqual(s.memory.lifetimeCelebrations, 1)
        // The struggle is spent: the next task starts clean.
        XCTAssertEqual(s.sessions["s1"]?.errorCount, 0)
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

    // MARK: - System E in the reducer

    func testAgentExpressionSetsOverlayWithLease() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentExpressed(at: NOW + 1, agentId: "claude-code", emotion: "sheepish", intensity: "medium", motion: "tilt", say: nil, delivery: nil))
        XCTAssertEqual(s.buddy.agentOverlay?.emotion, "sheepish")
        XCTAssertEqual(s.buddy.agentOverlay?.until, NOW + 1 + PetTuning.agentExpressLeaseMs)

        // S8: the lease expires; the pet is itself again.
        s = applyEvents(s, .staleTick(at: NOW + 1 + PetTuning.agentExpressLeaseMs + 100))
        XCTAssertNil(s.buddy.agentOverlay)
    }

    func testS1ExpressionRefusedWhilePromptPending() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf", sessionLabel: nil, source: "claude-code")
        )
        s = applyEvents(s, .agentExpressed(at: NOW + 2, agentId: "claude-code", emotion: "happy", intensity: "high", motion: nil, say: "all good, press A!", delivery: "excited"))
        XCTAssertNil(s.buddy.agentOverlay)
        XCTAssertEqual(s.buddy.pet.state, .attention)
    }

    func testS1PromptArrivingMidLeaseEvictsOverlay() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentExpressed(at: NOW + 1, agentId: "claude-code", emotion: "happy", intensity: "low", motion: nil, say: nil, delivery: nil))
        XCTAssertNotNil(s.buddy.agentOverlay)
        s = applyEvents(s, .approvalArrived(at: NOW + 2, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil, source: "claude-code"))
        XCTAssertNil(s.buddy.agentOverlay)
    }

    func testIntroduceRecordsIdentityAndColorsExpressions() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentIntroduced(at: NOW + 1, agentId: "claude-code", color: "sky", signatureEmote: "zen", greeting: "hello!"))
        XCTAssertEqual(s.memory.agents["claude-code"]?.color, "sky")
        XCTAssertEqual(s.memory.agents["claude-code"]?.visits, 1)

        s = applyEvents(s, .agentIntroduced(at: NOW + 2, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        XCTAssertEqual(s.memory.agents["claude-code"]?.visits, 2)
        // Markers survive an introduce that doesn't restate them.
        XCTAssertEqual(s.memory.agents["claude-code"]?.color, "sky")

        s = applyEvents(s, .agentExpressed(at: NOW + 3, agentId: "claude-code", emotion: "proud", intensity: "medium", motion: nil, say: nil, delivery: nil))
        XCTAssertEqual(s.buddy.agentOverlay?.color, "sky")
    }

    // MARK: - E4 drawings

    func testDrawingIsKeptAndHeldUp() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentIntroduced(at: NOW + 1, agentId: "claude-code", color: "teal", signatureEmote: nil, greeting: nil))
        s = applyEvents(s, .agentDrew(at: NOW + 2, agentId: "claude-code", rows: ["4f", "f4"], caption: "us"))
        XCTAssertEqual(s.memory.keepsakes.count, 1)
        XCTAssertEqual(s.memory.keepsakes.first?.color, "teal")
        XCTAssertEqual(s.buddy.agentDrawing?.rows, ["4f", "f4"])
        XCTAssertEqual(s.buddy.agentDrawingUntil, NOW + 2 + PetTuning.drawShowMs)

        // The pet shelves it after the show window; the keepsake survives.
        s = applyEvents(s, .staleTick(at: NOW + 2 + PetTuning.drawShowMs + 100))
        XCTAssertNil(s.buddy.agentDrawing)
        XCTAssertEqual(s.memory.keepsakes.count, 1)
    }

    func testDrawingDuringApprovalIsKeptButNotShown() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil, source: "claude-code")
        )
        s = applyEvents(s, .agentDrew(at: NOW + 2, agentId: "claude-code", rows: ["1"], caption: nil))
        // S1: never next to a trust decision — but the gift is not lost.
        XCTAssertNil(s.buddy.agentDrawing)
        XCTAssertEqual(s.memory.keepsakes.count, 1)
        XCTAssertEqual(s.buddy.pet.state, .attention)
    }

    func testPromptArrivingMidShowEvictsDrawingDisplayOnly() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentDrew(at: NOW + 1, agentId: "claude-code", rows: ["1"], caption: nil))
        XCTAssertNotNil(s.buddy.agentDrawing)
        s = applyEvents(s, .approvalArrived(at: NOW + 2, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil, source: "claude-code"))
        XCTAssertNil(s.buddy.agentDrawing)
        XCTAssertEqual(s.memory.keepsakes.count, 1)
    }

    func testKeepsakesAreCappedFIFO() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        for i in 0..<(PetTuning.keepsakeCap + 5) {
            s = applyEvents(s, .agentDrew(at: NOW + Double(i) + 1, agentId: "claude-code", rows: ["1"], caption: "d\(i)"))
        }
        XCTAssertEqual(s.memory.keepsakes.count, PetTuning.keepsakeCap)
        XCTAssertEqual(s.memory.keepsakes.first?.caption, "d5")
        XCTAssertEqual(s.memory.keepsakes.last?.caption, "d\(PetTuning.keepsakeCap + 4)")
    }

    // MARK: - E4.1 resurfacing ("remember this?")

    func testReturningAgentGetsAnOldDrawingResurfaced() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentIntroduced(at: NOW + 1, agentId: "claude-code", color: "teal", signatureEmote: nil, greeting: nil))
        s = applyEvents(s, .agentDrew(at: NOW + 2, agentId: "claude-code", rows: ["1"], caption: "old times"))
        s = applyEvents(s, .staleTick(at: NOW + 2 + PetTuning.drawShowMs + 100))
        XCTAssertNil(s.buddy.agentDrawing)

        // Two days later the agent returns: the pet digs the drawing out.
        let back = NOW + 2 * dayMs
        s = applyEvents(s, .agentIntroduced(at: back, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        XCTAssertEqual(s.buddy.agentDrawing?.caption, "old times")
        XCTAssertEqual(s.buddy.agentDrawingIsMemory, true)
        XCTAssertEqual(s.memory.lastResurfacedAt, back)
    }

    func testResurfacingIsAtMostDailyAndNeedsOldDrawings() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentIntroduced(at: NOW + 1, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        s = applyEvents(s, .agentDrew(at: NOW + 2, agentId: "claude-code", rows: ["1"], caption: "fresh"))
        // A fresh drawing is not yet a memory: same-day reintroduce shows nothing.
        s = applyEvents(s, .staleTick(at: NOW + 2 + PetTuning.drawShowMs + 100))
        s = applyEvents(s, .agentIntroduced(at: NOW + 3 * 3_600_000, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        XCTAssertNil(s.buddy.agentDrawing)

        // Old enough two days later — resurfaces once…
        let day2 = NOW + 2 * dayMs
        s = applyEvents(s, .agentIntroduced(at: day2, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        XCTAssertEqual(s.buddy.agentDrawingIsMemory, true)
        s = applyEvents(s, .staleTick(at: day2 + PetTuning.drawShowMs + 100))

        // …but not again an hour later: at most one memory a day.
        s = applyEvents(s, .agentIntroduced(at: day2 + 3_600_000, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        XCTAssertNil(s.buddy.agentDrawing)
    }

    func testResurfacingDefersToPendingPrompt() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil))
        s = applyEvents(s, .agentIntroduced(at: NOW + 1, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        s = applyEvents(s, .agentDrew(at: NOW + 2, agentId: "claude-code", rows: ["1"], caption: nil))
        s = applyEvents(s, .staleTick(at: NOW + 2 + PetTuning.drawShowMs + 100))
        let back = NOW + 2 * dayMs
        s = applyEvents(s, .approvalArrived(at: back - 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil, source: "claude-code"))
        s = applyEvents(s, .agentIntroduced(at: back, agentId: "claude-code", color: nil, signatureEmote: nil, greeting: nil))
        // S1: no memory next to a trust decision — and no daily slot burned.
        XCTAssertNil(s.buddy.agentDrawing)
        XCTAssertNil(s.memory.lastResurfacedAt)
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
