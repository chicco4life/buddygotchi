import XCTest
@testable import BoopCore

/// A blocking approval has a hook parked on the other end of it, so nothing
/// short of an answer, a session ending, or the expiry sweep may withdraw it.
///
/// Reproduced against the live app and device before the fix: park a real
/// `/hook/approve`, then post a `PostToolUse` for the SAME session (exactly
/// what a parallel `Read` finishing does) — the card vanished from the device
/// and the blocked hook returned passthrough. Agents batch tool calls
/// constantly, so approval mode was unreliable in any non-trivial session.
final class ApprovalSurvivalTests: XCTestCase {

    private let cfg = (stale: 600_000.0, celebrate: 4_000.0)

    private func stateWithParkedApproval() -> InternalState {
        var s = InternalState.initial(staleMs: cfg.stale, celebrateDurationMs: cfg.celebrate)
        s = reduce(s, .sessionStarted(at: 0, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .approvalArrived(
            at: 100, sessionId: "s1", requestId: "req_1",
            tool: "Bash", hint: "rm -rf build", sessionLabel: nil, source: "claude-code"))
        return s
    }

    func testParallelToolActivityDoesNotCancelABlockingApproval() {
        var s = stateWithParkedApproval()
        XCTAssertEqual(s.buddy.prompt?.id, "req_1")

        // A sibling Read finishes in the same session.
        s = reduce(s, .activitySignal(
            at: 200, sessionId: "s1", source: "claude-code",
            signal: .keepWorking, tool: "Read", hint: "/tmp/a"))

        XCTAssertEqual(s.buddy.prompt?.id, "req_1", "a parallel tool cancelled a parked approval")
        XCTAssertEqual(s.buddy.pet.state, .attention, "pet dropped out of attention with a decision owed")
        XCTAssertEqual(s.sessions["s1"]?.state, .needsConfirmation)
    }

    func testStartWorkingDoesNotCancelABlockingApproval() {
        var s = stateWithParkedApproval()
        s = reduce(s, .activitySignal(
            at: 200, sessionId: "s1", source: "claude-code",
            signal: .startWorking, tool: nil, hint: nil))
        XCTAssertEqual(s.buddy.prompt?.id, "req_1")
    }

    func testRequestClearedDoesNotCancelABlockingApproval() {
        var s = stateWithParkedApproval()
        s = reduce(s, .requestCleared(at: 200, sessionId: "s1"))
        XCTAssertEqual(s.buddy.prompt?.id, "req_1")
    }

    /// The other half of the contract: a PASSIVE notification card has no
    /// blocked caller, so activity should still dismiss it.
    func testActivityStillDismissesAPassiveNotificationCard() {
        var s = InternalState.initial(staleMs: cfg.stale, celebrateDurationMs: cfg.celebrate)
        s = reduce(s, .sessionStarted(at: 0, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .requestArrived(
            at: 100, sessionId: "s1", requestId: "note_1",
            tool: "Notification", hint: "idle", sessionLabel: nil))
        XCTAssertEqual(s.buddy.prompt?.id, "note_1")

        s = reduce(s, .activitySignal(
            at: 200, sessionId: "s1", source: "claude-code",
            signal: .keepWorking, tool: "Read", hint: "/tmp/a"))
        XCTAssertNil(s.buddy.prompt, "a passive card should be dismissed by new activity")
    }

    /// An answer still clears it — the fix must not strand the prompt.
    func testResolvingTheApprovalStillClearsIt() {
        var s = stateWithParkedApproval()
        s = reduce(s, .approvalResolved(at: 300, sessionId: "s1", requestId: "req_1", decision: .allow))
        XCTAssertNil(s.buddy.prompt, "an answered approval must leave")
    }

    func testSessionEndStillClearsAParkedApproval() {
        var s = stateWithParkedApproval()
        s = reduce(s, .sessionEnded(at: 300, sessionId: "s1"))
        XCTAssertNil(s.buddy.prompt)
    }

    /// The expiry sweep is what unblocks a hook nobody answered.
    func testApprovalStillExpires() {
        var s = stateWithParkedApproval()
        s = reduce(s, .staleTick(at: 100 + 300_000 + 1))
        XCTAssertNil(s.buddy.prompt, "the approval never expired")
    }
}
