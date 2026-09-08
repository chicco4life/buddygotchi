import XCTest
@testable import BoopCore

@MainActor
private func makeApprovalEngine() -> BuddyEngine {
    BuddyEngine(config: BuddyConfig(
        httpPort: 0,
        staleTimeoutMs: 600_000,
        celebrateDurationMs: 4_000,
        workStallTimeoutMs: 300_000,
        stateDir: "/tmp",
        approvalMode: true,
        token: "test-token"
    ), clock: MockClock())
}

/// Answering a request must always dismiss it, even when whatever was waiting
/// on the answer has already gone away.
///
/// `resolveApproval` used to bail out the moment it found no continuation,
/// leaving the prompt in state with nothing able to clear it. On the device
/// that reads as a card you cannot get rid of: the crown sends a decision, the
/// decision resolves nothing, and ten seconds later the firmware's re-offer
/// puts the identical request back on screen. Forever.
final class OrphanedPromptTests: XCTestCase {

    @MainActor
    func testDeviceDecisionClearsAPromptWhoseWaiterIsGone() async {
        let engine = makeApprovalEngine()

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp")

        // A prompt with no waiter behind it. This is a real shape, not a
        // contrived one: a PermissionRequest delivered over /hook/event (rather
        // than the blocking /hook/approve) puts a card on the device with
        // nothing parked on the other end of it.
        engine.submitRequest(
            sessionId: "s1", requestId: "orphan_1",
            tool: "Bash", hint: "rm -rf build", sessionLabel: nil)
        XCTAssertEqual(engine.state.prompt?.id, "orphan_1")

        // The crown answers it.
        let hadWaiter = engine.resolveApproval(requestId: "orphan_1", decision: .allow)

        XCTAssertFalse(hadWaiter, "nothing was waiting; the return value should say so")
        XCTAssertNil(engine.state.prompt, "answering the card did not dismiss it")
    }

    @MainActor
    func testNormalApprovalStillUnblocksItsCaller() async {
        let engine = makeApprovalEngine()

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp")
        async let decision = engine.submitApproval(
            sessionId: "s1", requestId: "req_1", tool: "Bash",
            hint: "git push", sessionLabel: nil, source: "claude-code")

        // Let the continuation register before answering.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let hadWaiter = engine.resolveApproval(requestId: "req_1", decision: .allow)

        XCTAssertTrue(hadWaiter, "a real waiter should be reported")
        let got = await decision
        XCTAssertEqual(got, .allow)
        XCTAssertNil(engine.state.prompt)
    }

    @MainActor
    func testDecisionForAnIdWeNeverHadIsStillReportedAsUnknown() {
        let engine = makeApprovalEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp")
        XCTAssertFalse(engine.resolveApproval(requestId: "never_seen", decision: .allow))
    }
}
