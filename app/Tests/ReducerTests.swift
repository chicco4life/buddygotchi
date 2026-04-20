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
    static func test() -> InternalState { .initial(staleMs: TEST_STALE_MS) }
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
}
