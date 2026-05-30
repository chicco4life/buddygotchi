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

        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "claude-code", signal: .stopWorking))
        XCTAssertEqual(s.buddy.pet.state, .attention, "Session 1 still needs confirmation")
        XCTAssertNotNil(s.buddy.prompt)
    }

    func testBusyOverridesIdleAcrossSessions() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .sessionStarted(at: NOW, sessionId: "s2", source: "cursor", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking))
        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "cursor", signal: .stopWorking))
        XCTAssertEqual(s.buddy.pet.state, .busy, "Session 1 is still working")
    }

    // MARK: - Celebrate

    func testCelebrateSignalSetsCelebrateState() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .startWorking)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .celebrate))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertNotNil(s.buddy.celebrateUntil)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 1, "Duration = celebrate time - work start time")
    }

    func testCelebrateExpiresOnStaleTick() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate)
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
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate))
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
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s2", source: "claude-code", signal: .startWorking))
        XCTAssertEqual(s.buddy.pet.state, .busy, "Busy takes priority over celebrate")
    }

    func testShortTaskDurationBelowThreshold() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1000, sessionId: "s1", source: "claude-code", signal: .startWorking)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 5000, sessionId: "s1", source: "claude-code", signal: .celebrate))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 4000, "4s task is below 30s threshold")
    }

    func testLongTaskDurationAboveThreshold() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .activitySignal(at: NOW + 1000, sessionId: "s1", source: "claude-code", signal: .startWorking)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 45_000, sessionId: "s1", source: "claude-code", signal: .celebrate))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 44_000, "44s task is above 30s threshold")
    }

    func testCelebrateWithoutWorkStartHasNilDuration() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 1, sessionId: "s1", source: "claude-code", signal: .celebrate))
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
}
