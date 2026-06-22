import XCTest
@testable import Buddygotchi

let NOW: Double = 1_000_000
let TEST_STALE_MS: Double = 600_000

func applyEvents(_ state: InternalState, _ events: BuddyEvent...) -> InternalState {
    var s = state
    for e in events { s = reduce(s, e) }
    return s
}

extension InternalState {
    static func test() -> InternalState { .initial(staleMs: TEST_STALE_MS, celebrateDurationMs: 4000) }
}

final class ReducerTests: XCTestCase {

    func testInitialStateIsDisconnectedWithNoPrompt() {
        let s = InternalState.test()
        XCTAssertEqual(s.buddy.version, 0)
        XCTAssertEqual(s.buddy.desktop.status, .disconnected)
        XCTAssertNil(s.buddy.prompt)
        XCTAssertEqual(s.buddy.pet.state, .sleep)
    }

    func testSessionStartedBumpsVersion() {
        let s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: "/tmp"))
        XCTAssertEqual(s.buddy.version, 1)
        XCTAssertEqual(s.buddy.desktop.status, .connected)
        XCTAssertEqual(s.buddy.pet.state, .idle)
    }

    func testRequestArrivedSetsPromptAndAttention() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil))
        s = applyEvents(s, .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "req_1", tool: "Bash", hint: "ls -la", sessionLabel: "project"))
        XCTAssertNotNil(s.buddy.prompt)
        XCTAssertEqual(s.buddy.prompt?.id, "req_1")
        XCTAssertEqual(s.buddy.prompt?.tool, "Bash")
        XCTAssertEqual(s.buddy.pet.state, .attention)
    }

    func testRequestClearedRemovesPrompt() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil),
            .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "req_1", tool: "Bash", hint: "ls", sessionLabel: nil)
        )
        s = applyEvents(s, .requestCleared(at: NOW + 2, sessionId: "s1"))
        XCTAssertNil(s.buddy.prompt)
        XCTAssertEqual(s.buddy.pet.state, .busy)
    }

    func testSessionEndedRemovesSessionAndSleeps() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil))
        s = applyEvents(s, .sessionEnded(at: NOW + 1, sessionId: "s1"))
        XCTAssertEqual(s.buddy.desktop.status, .disconnected)
        XCTAssertEqual(s.buddy.pet.state, .sleep)
    }

    func testStaleTickRemovesExpiredSessions() {
        var s = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil))

        let before = reduce(s, .staleTick(at: NOW + 500_000))
        XCTAssertEqual(before.buddy.desktop.status, .connected)

        let after = reduce(s, .staleTick(at: NOW + 700_000))
        XCTAssertEqual(after.buddy.desktop.status, .disconnected)
        XCTAssertEqual(after.buddy.pet.state, .sleep)
    }

    func testVersionBumpsExactlyOncePerChange() {
        var s = InternalState.test()
        s = applyEvents(s, .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil))
        XCTAssertEqual(s.buddy.version, 1)
        s = applyEvents(s, .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "T", hint: "h", sessionLabel: nil))
        XCTAssertEqual(s.buddy.version, 2)
    }

    func testMultipleSessionsTrackedIndependently() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "cursor", cwd: nil),
            .sessionStarted(at: NOW + 1, sessionId: "s2", source: "claude-code", cwd: nil)
        )
        XCTAssertEqual(s.sessions.count, 2)
        XCTAssertEqual(s.buddy.desktop.status, .connected)

        s = applyEvents(s, .sessionEnded(at: NOW + 2, sessionId: "s1"))
        XCTAssertEqual(s.buddy.desktop.status, .connected)

        s = applyEvents(s, .sessionEnded(at: NOW + 3, sessionId: "s2"))
        XCTAssertEqual(s.buddy.desktop.status, .disconnected)
    }

    // MARK: - Multi-session aggregation

    func testAttentionPersistsWhenOtherSessionStops() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/a"),
            .sessionStarted(at: NOW, sessionId: "s2", source: "claude-code", cwd: "/b")
        )
        s = applyEvents(s, .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "req_1", tool: "Bash", hint: "rm -rf", sessionLabel: "a"))
        XCTAssertEqual(s.buddy.pet.state, .attention)

        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "claude-code", signal: .stopWorking, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .attention, "Session 1 still needs confirmation")
        XCTAssertNotNil(s.buddy.prompt)
    }

    func testBusyOverridesIdleAcrossSessions() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil))
        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "cursor", signal: .stopWorking, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .busy, "Session 1 is still working")
    }

    // MARK: - Celebrate

    func testCelebrateSignalSetsCelebrateState() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertNotNil(s.buddy.celebrateUntil)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 1, "Duration = celebrate time - work start time")
    }

    func testCelebrateExpiresOnStaleTick() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        s = applyEvents(s, .staleTick(at: NOW + 3000))
        XCTAssertEqual(s.buddy.pet.state, .celebrate, "Should still be celebrating before 4s")

        s = applyEvents(s, .staleTick(at: NOW + 5000))
        XCTAssertEqual(s.buddy.pet.state, .idle)
        XCTAssertNil(s.buddy.celebrateUntil)
    }

    func testAttentionOverridesCelebrate() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "claude-code", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        s = applyEvents(s, .requestArrived(at: NOW + 2, sessionId: "s2", requestId: "r1", tool: "Bash", hint: "rm", sessionLabel: nil))
        XCTAssertEqual(s.buddy.pet.state, .attention, "Attention takes priority over celebrate")
    }

    func testBusyOverridesCelebrate() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "claude-code", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "claude-code", signal: .startWorking, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .busy, "Busy takes priority over celebrate")
    }

    func testShortTaskDurationBelowThreshold() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1000, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 5000, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 4000, "4s task is below 30s threshold")
    }

    func testLongTaskDurationAboveThreshold() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1000, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 45_000, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 44_000, "44s task is above 30s threshold")
    }

    func testCelebrateWithoutWorkStartHasNilDuration() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertNil(s.buddy.lastTaskDurationMs, "No workStartedAt means nil duration")
    }

    // MARK: - Message (heartbeat) field

    func testMsgUsesDisplayedPromptSourceNotArbitrarySession() {
        // Two sessions from different agents both waiting. The oldest prompt
        // (cursor's) is the one shown; msg must label it "cursor", not whatever
        // session happens to come first in dictionary iteration order.
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil)
        )
        s = applyEvents(s, .approvalArrived(at: NOW + 1, sessionId: "s2", requestId: "r2", tool: "Bash", hint: "ls", sessionLabel: nil, source: "cursor"))
        s = applyEvents(s, .approvalArrived(at: NOW + 2, sessionId: "s1", requestId: "r1", tool: "Write", hint: "file", sessionLabel: nil, source: "claude-code"))

        XCTAssertEqual(s.buddy.prompt?.id, "r2", "Oldest request is shown")
        XCTAssertTrue(s.buddy.msg.hasPrefix("[cursor]"), "msg labels the displayed prompt's source, got: \(s.buddy.msg)")
    }

    func testMsgClearsWhenPromptResolves() {
        // After an approval is resolved the device should not keep showing the
        // stale prompt text while the pet is busy/idle.
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf", sessionLabel: nil, source: "claude-code")
        )
        XCTAssertFalse(s.buddy.msg.isEmpty, "Prompt sets a message")

        s = applyEvents(s, .approvalResolved(at: NOW + 2, sessionId: "s1", requestId: "r1", decision: .allow))
        XCTAssertEqual(s.buddy.pet.state, .busy)
        XCTAssertEqual(s.buddy.msg, "", "msg is cleared once no prompt is pending")
    }

    // MARK: - Default species

    func testDefaultSpeciesIsAKnownSpecies() {
        // The engine's default species must exist in the rendered species set,
        // otherwise outputs fall back to an arbitrary/stale species.
        XCTAssertNotNil(allBuddies[Pet.defaultSpecies], "default species '\(Pet.defaultSpecies)' must be a real species")
        XCTAssertTrue(buddyOrder.contains(Pet.defaultSpecies))
    }

    // MARK: - Gap A: Done / needs review

    func testKeepWorkingWithToolAndHintStashesOnSession() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/tmp"),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        )
        XCTAssertEqual(s.sessions["s1"]?.lastTool, "Bash")
        XCTAssertEqual(s.sessions["s1"]?.lastHint, "swift test")
    }

    func testCelebrateAfterKeepWorkingPopulatesLastCompletedWithCorrectTool() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/tmp/my-app"),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "BuddyState.swift")
        )
        s = applyEvents(s, .activitySignal(at: NOW + 5_000, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil))
        XCTAssertNotNil(s.buddy.lastCompleted)
        XCTAssertEqual(s.buddy.lastCompleted?.tool, "Edit")
        XCTAssertEqual(s.buddy.lastCompleted?.hint, "BuddyState.swift")
        XCTAssertEqual(s.buddy.lastCompleted?.source, "claude-code")
        XCTAssertEqual(s.buddy.lastCompleted?.sessionLabel, "my-app")
        // Duration is from startWorking (NOW + 1) to celebrate (NOW + 5000) = 4999ms.
        XCTAssertEqual(s.buddy.lastCompleted?.durationMs ?? 0, 4999, accuracy: 1)
    }

    func testLastCompletedPersistsAfterCelebrateWindowExpires() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "swift test"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertNotNil(s.buddy.lastCompleted)
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        // Tick past the 4-second celebrate window.
        s = applyEvents(s, .staleTick(at: NOW + 10_000))
        XCTAssertEqual(s.buddy.pet.state, .idle)
        XCTAssertNotNil(s.buddy.lastCompleted, "review survives celebrate window")
        XCTAssertEqual(s.buddy.lastCompleted?.tool, "Bash")
    }

    func testLastCompletedClearsWhenNewRequestArrives() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: "Foo.swift"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertNotNil(s.buddy.lastCompleted)
        s = applyEvents(s, .requestArrived(at: NOW + 10_000, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm", sessionLabel: nil))
        XCTAssertNil(s.buddy.lastCompleted, "incoming prompt clears review")
        XCTAssertEqual(s.buddy.pet.state, .attention)
    }

    func testLastCompletedClearsOnStartWorkingFromAnySession() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertNotNil(s.buddy.lastCompleted)
        s = applyEvents(s, .activitySignal(at: NOW + 10_000, sessionId: "s2", source: "cursor", signal: .startWorking, tool: nil, hint: nil))
        XCTAssertNil(s.buddy.lastCompleted, "work resuming on a different session clears review")
        XCTAssertEqual(s.buddy.pet.state, .busy)
    }

    func testReviewDismissedEventClearsLastCompleted() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil),
            .staleTick(at: NOW + 10_000)
        )
        XCTAssertNotNil(s.buddy.lastCompleted)
        s = applyEvents(s, .reviewDismissed(at: NOW + 11_000))
        XCTAssertNil(s.buddy.lastCompleted)
    }

    func testIdleMsgShowsCompletionSummaryWhenLastCompletedSet() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: "Foo.swift"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil),
            .staleTick(at: NOW + 10_000)
        )
        XCTAssertEqual(s.buddy.pet.state, .idle)
        // Device sees the completion summary on its msg line until a new prompt or work signal.
        XCTAssertTrue(s.buddy.msg.hasPrefix("Done: Edit"), "got msg=\(s.buddy.msg)")
    }

    // MARK: - Gap B: Working with confidence

    func testBusyStateMsgIncludesCurrentToolFromPrimarySession() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: nil, hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        )
        XCTAssertEqual(s.buddy.pet.state, .busy)
        XCTAssertTrue(s.buddy.msg.contains("Bash"), "got msg=\(s.buddy.msg)")
        XCTAssertTrue(s.buddy.msg.contains("swift test"), "got msg=\(s.buddy.msg)")
    }

    func testCurrentToolClearsOnCelebrate() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: "Foo.swift"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertNil(s.sessions["s1"]?.currentTool)
        XCTAssertNil(s.sessions["s1"]?.currentHint)
        // lastTool/lastHint are preserved for review purposes.
        XCTAssertEqual(s.sessions["s1"]?.lastTool, "Edit")
    }

    func testCurrentToolClearsOnStopWorking() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Read", hint: "Foo.swift"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .stopWorking, tool: nil, hint: nil)
        )
        XCTAssertNil(s.sessions["s1"]?.currentTool)
        XCTAssertNil(s.sessions["s1"]?.currentHint)
    }

    func testMultipleWorkingSessionsMsgUsesOldestWorkStartedAt() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil),
            // s1 starts working FIRST (oldest workStartedAt → primary).
            .activitySignal(at: NOW + 100, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "First.swift"),
            // s2 starts later.
            .activitySignal(at: NOW + 200, sessionId: "s2", source: "cursor", signal: .keepWorking, tool: "Bash", hint: "ls")
        )
        XCTAssertEqual(s.buddy.pet.state, .busy)
        XCTAssertTrue(s.buddy.msg.contains("Edit"), "primary session's tool wins; got msg=\(s.buddy.msg)")
        XCTAssertTrue(s.buddy.msg.contains("First.swift"), "got msg=\(s.buddy.msg)")
    }

    func testEntriesAccumulateAndTruncateAt10() {
        var s: InternalState = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil)
        )
        // Push 12 keepWorking events.
        for i in 1...12 {
            s = applyEvents(s, .activitySignal(at: NOW + Double(i), sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "file\(i).swift"))
        }
        XCTAssertEqual(s.buddy.entries.count, 10, "entries truncate at 10")
        // Newest first — entries[0] should be from i=12.
        XCTAssertTrue(s.buddy.entries[0].contains("file12.swift"), "newest first; got \(s.buddy.entries[0])")
    }

    func testKeepWorkingWithoutToolDoesNotOverwritePreviouslyStashedTool() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            // First keepWorking with a tool — populates currentTool.
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift"),
            // Subsequent keepWorking with no tool (some hooks don't carry it) should leave currentTool intact.
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.sessions["s1"]?.currentTool, "Edit")
        XCTAssertEqual(s.sessions["s1"]?.currentHint, "Foo.swift")
    }

    // MARK: - Gap C: Blocked / error

    func testErrorSignalSetsPetToErrorNotIdle() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "swift test"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.sessions["s1"]?.state, .errored)
        XCTAssertEqual(s.buddy.pet.state, .error)
        XCTAssertNotNil(s.buddy.firstErrored)
        XCTAssertEqual(s.buddy.firstErrored?.tool, "Bash")
    }

    func testStaleTickMarksSessionThinkingAfterStallTimeoutNoWorkSignal() {
        // Use a small workStallTimeoutMs so we don't have to advance 5min.
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "long-task")
        )
        XCTAssertEqual(s.buddy.pet.state, .busy)
        // Advance past stall threshold without further keep_working signals.
        s = applyEvents(s, .staleTick(at: NOW + 35_000))
        XCTAssertEqual(s.sessions["s1"]?.state, .thinking, "silent past stall → thinking, NOT errored")
        XCTAssertEqual(s.buddy.pet.state, .thinking)
        XCTAssertNotNil(s.buddy.firstThinking)
        XCTAssertEqual(s.buddy.firstThinking?.tool, "Bash")
        XCTAssertNil(s.buddy.firstErrored, "thinking is not an error")
    }

    func testStaleTickDoesNotMarkThinkingIfKeepWorkingWithinThreshold() {
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil)
        )
        // Bump lastWorkSignalAt within the threshold.
        s = applyEvents(s, .activitySignal(at: NOW + 25_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: nil))
        // Advance past first start, but recent keep_working keeps lastWorkSignalAt fresh.
        s = applyEvents(s, .staleTick(at: NOW + 50_000))
        XCTAssertEqual(s.sessions["s1"]?.state, .working)
        XCTAssertEqual(s.buddy.pet.state, .busy)
    }

    func testThinkingSessionRecoversToWorkingOnKeepWorkingPreservingWorkStartedAt() {
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil)
        )
        let originalStart = s.sessions["s1"]?.workStartedAt
        s = applyEvents(s, .staleTick(at: NOW + 35_000))
        XCTAssertEqual(s.buddy.pet.state, .thinking)
        // Resume — the agent emitted output again
        s = applyEvents(s, .activitySignal(at: NOW + 40_000, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift"))
        XCTAssertEqual(s.sessions["s1"]?.state, .working)
        XCTAssertEqual(s.buddy.pet.state, .busy)
        XCTAssertEqual(s.sessions["s1"]?.workStartedAt, originalStart, "thinking → working preserves original start time (work paused, not restarted)")
    }

    func testErrorAndThinkingPriorityErrorWins() {
        // Two sessions: one errored (StopFailure), one thinking (silent stall).
        // Pet state should be .error — explicit failure outranks thinking.
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "thinker", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "failed", source: "cursor", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "thinker", source: "claude-code", signal: .startWorking, tool: "Edit", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "failed", source: "cursor", signal: .startWorking, tool: "Bash", hint: nil),
            .activitySignal(at: NOW + 3, sessionId: "failed", source: "cursor", signal: .error, tool: nil, hint: nil)
        )
        // Now advance past stall — thinker session goes to thinking.
        s = applyEvents(s, .staleTick(at: NOW + 35_000))
        XCTAssertEqual(s.sessions["thinker"]?.state, .thinking)
        XCTAssertEqual(s.sessions["failed"]?.state, .errored)
        XCTAssertEqual(s.buddy.pet.state, .error, "error outranks thinking")
        // Both projections populate; surfaces decide what to render.
        XCTAssertNotNil(s.buddy.firstErrored)
        XCTAssertNotNil(s.buddy.firstThinking)
    }

    func testBusyAndThinkingPriorityBusyWins() {
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "thinker", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "active", source: "cursor", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "thinker", source: "claude-code", signal: .startWorking, tool: "Edit", hint: nil)
        )
        s = applyEvents(s, .staleTick(at: NOW + 35_000))
        XCTAssertEqual(s.sessions["thinker"]?.state, .thinking)
        // Now an unrelated session becomes busy — it should outrank thinking.
        s = applyEvents(s, .activitySignal(at: NOW + 40_000, sessionId: "active", source: "cursor", signal: .keepWorking, tool: "Bash", hint: nil))
        XCTAssertEqual(s.buddy.pet.state, .busy, "actively-working session outranks thinking peer")
    }

    func testThinkingMsgIncludesToolName() {
        var initial = InternalState.test()
        initial.workStallTimeoutMs = 30_000
        var s = applyEvents(
            initial,
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "WebFetch", hint: "https://docs/")
        )
        s = applyEvents(s, .staleTick(at: NOW + 35_000))
        XCTAssertTrue(s.buddy.msg.hasPrefix("Thinking: WebFetch"), "got msg=\(s.buddy.msg)")
    }

    func testErrorMsgUsesErrorPrefixNotStalled() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "swift test"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil)
        )
        XCTAssertTrue(s.buddy.msg.hasPrefix("Error: Bash"), "got msg=\(s.buddy.msg)")
    }

    func testErroredSessionRecoversToWorkingOnKeepWorking() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.buddy.pet.state, .error)
        // New keep_working signal should flip back to working.
        s = applyEvents(s, .activitySignal(at: NOW + 100, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift"))
        XCTAssertEqual(s.sessions["s1"]?.state, .working)
        XCTAssertEqual(s.buddy.pet.state, .busy)
    }

    func testErroredSessionWithActivePromptElsewherePetRemainsAttention() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil),
            // s1 errors out
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil),
            // s2 has a pending approval — attention should win
            .approvalArrived(at: NOW + 3, sessionId: "s2", requestId: "r1", tool: "Bash", hint: "rm", sessionLabel: nil, source: "cursor")
        )
        XCTAssertEqual(s.buddy.pet.state, .attention, "live approval beats error")
        // The error info is still tracked in firstErrored even though pet is attention.
        XCTAssertNotNil(s.buddy.firstErrored)
    }

    func testDismissErrorClearsErroredStateForSession() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.buddy.pet.state, .error)
        s = applyEvents(s, .errorDismissed(at: NOW + 3, sessionId: "s1"))
        XCTAssertEqual(s.sessions["s1"]?.state, .idle)
        XCTAssertEqual(s.buddy.pet.state, .idle)
        XCTAssertNil(s.buddy.firstErrored)
    }

    func testFirstErroredHasOldestWorkStartedAtAcrossMultipleErrored() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil),
            // s2 starts working FIRST (oldest workStartedAt).
            .activitySignal(at: NOW + 100, sessionId: "s2", source: "cursor", signal: .startWorking, tool: "Edit", hint: "First.swift"),
            // s1 starts later.
            .activitySignal(at: NOW + 200, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "Second.sh"),
            // Both error out.
            .activitySignal(at: NOW + 300, sessionId: "s2", source: "cursor", signal: .error, tool: nil, hint: nil),
            .activitySignal(at: NOW + 400, sessionId: "s1", source: "claude-code", signal: .error, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.buddy.firstErrored?.tool, "Edit", "oldest workStartedAt session is primary")
        XCTAssertEqual(s.buddy.firstErrored?.source, "cursor")
    }

    // MARK: - Gap D: Subagent / parallel

    func testActiveSessionsOrdersAttentionFirstThenErroredThenOldestWorking() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "claude", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "cursor", source: "cursor", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "codex", source: "codex", cwd: nil),
            // claude is working (oldest workStartedAt)
            .activitySignal(at: NOW + 100, sessionId: "claude", source: "claude-code", signal: .startWorking, tool: "Bash", hint: nil),
            // codex is working (newer)
            .activitySignal(at: NOW + 200, sessionId: "codex", source: "codex", signal: .startWorking, tool: "Edit", hint: nil),
            // cursor errors out
            .activitySignal(at: NOW + 300, sessionId: "cursor", source: "cursor", signal: .error, tool: "Read", hint: nil),
            // claude transitions to needsConfirmation last
            .approvalArrived(at: NOW + 400, sessionId: "claude", requestId: "r1", tool: "Bash", hint: "rm", sessionLabel: nil, source: "claude-code")
        )
        let snaps = s.buddy.activeSessions
        XCTAssertEqual(snaps.count, 3)
        // attention first
        XCTAssertEqual(snaps[0].state, .needsConfirmation)
        XCTAssertEqual(snaps[0].source, "claude-code")
        // errored next
        XCTAssertEqual(snaps[1].state, .errored)
        XCTAssertEqual(snaps[1].source, "cursor")
        // working last (codex still working since claude moved to attention)
        XCTAssertEqual(snaps[2].state, .working)
        XCTAssertEqual(snaps[2].source, "codex")
    }

    func testActiveSessionsCappedAtSix() {
        var s: InternalState = .test()
        for i in 1...8 {
            s = applyEvents(s, .sessionStarted(at: NOW + Double(i), sessionId: "s\(i)", source: "claude-code", cwd: nil))
            s = applyEvents(s, .activitySignal(at: NOW + Double(i), sessionId: "s\(i)", source: "claude-code", signal: .startWorking, tool: "Edit", hint: nil))
        }
        XCTAssertEqual(s.sessions.count, 8)
        XCTAssertEqual(s.buddy.activeSessions.count, 6, "wire-format/UI cap matches firmware tama.lines[6]")
    }

    func testActiveSessionsIncludesIdleSessionsAfterActiveOnes() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "idle1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "working1", source: "cursor", cwd: nil),
            .activitySignal(at: NOW + 100, sessionId: "working1", source: "cursor", signal: .startWorking, tool: "Edit", hint: nil)
        )
        XCTAssertEqual(s.buddy.activeSessions.count, 2)
        // working comes before idle
        XCTAssertEqual(s.buddy.activeSessions[0].state, .working)
        XCTAssertEqual(s.buddy.activeSessions[1].state, .idle)
    }

    func testActiveSessionsEmptyWhenNoSessions() {
        let s = InternalState.test()
        XCTAssertTrue(s.buddy.activeSessions.isEmpty)
    }

    // MARK: - Gap E: Tests / verify (activity classifier)

    func testActivityKindForSwiftTestCommandReturnsVerify() {
        XCTAssertEqual(activityKind(tool: "Bash", hint: "swift test"), .verify)
        XCTAssertEqual(activityKind(tool: "Bash", hint: "swift test --filter ReducerTests"), .verify)
        XCTAssertEqual(activityKind(tool: "Bash", hint: "npm test"), .verify)
        XCTAssertEqual(activityKind(tool: "Bash", hint: "pytest tests/"), .verify)
        XCTAssertEqual(activityKind(tool: "Bash", hint: "cargo test"), .verify)
    }

    func testActivityKindForGenericBashReturnsShell() {
        XCTAssertEqual(activityKind(tool: "Bash", hint: "ls -la"), .shell)
        XCTAssertEqual(activityKind(tool: "Bash", hint: "curl https://example.com"), .shell)
        XCTAssertEqual(activityKind(tool: "Bash", hint: ""), .shell)
    }

    func testActivityKindForReadToolReturnsRead() {
        XCTAssertEqual(activityKind(tool: "Read", hint: ""), .read)
        XCTAssertEqual(activityKind(tool: "Glob", hint: "**/*.swift"), .read)
        XCTAssertEqual(activityKind(tool: "Grep", hint: "TODO"), .read)
        XCTAssertEqual(activityKind(tool: "LSP", hint: ""), .read)
    }

    func testActivityKindForEditToolReturnsWrite() {
        XCTAssertEqual(activityKind(tool: "Edit", hint: "Foo.swift"), .write)
        XCTAssertEqual(activityKind(tool: "Write", hint: "/tmp/x"), .write)
        XCTAssertEqual(activityKind(tool: "MultiEdit", hint: ""), .write)
        XCTAssertEqual(activityKind(tool: "NotebookEdit", hint: ""), .write)
    }

    func testActivityKindForWebToolReturnsWeb() {
        XCTAssertEqual(activityKind(tool: "WebFetch", hint: "https://docs/"), .web)
        XCTAssertEqual(activityKind(tool: "WebSearch", hint: "swift docs"), .web)
    }

    func testActivityKindForUnknownToolReturnsWork() {
        XCTAssertEqual(activityKind(tool: "FancyNewTool", hint: ""), .work)
        XCTAssertEqual(activityKind(tool: "", hint: ""), .work)
    }

    func testPromptActivityKindSetAfterRequestArrived() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "swift test", sessionLabel: nil)
        )
        XCTAssertEqual(s.buddy.prompt?.activityKind, .verify)
    }

    func testSessionCurrentActivityKindSetAfterKeepWorking() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift")
        )
        XCTAssertEqual(s.sessions["s1"]?.currentActivityKind, .write)
        XCTAssertEqual(s.buddy.currentActivityKind, .write, "projected onto BuddyState during busy")
    }

    func testCompletedTaskActivityKindCarriedOnCelebrate() {
        let s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "swift test"),
            .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: nil, hint: nil)
        )
        XCTAssertEqual(s.buddy.lastCompleted?.activityKind, .verify)
    }
}
