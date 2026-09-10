import XCTest
@testable import BoopCore

@MainActor
private func makeApprovalEngine() -> BuddyEngine {
    BuddyEngine(config: BuddyConfig(
        httpPort: 0,
        staleTimeoutMs: 600_000,
        celebrateDurationMs: 4_000,

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
    func testDecisionForAnIdWeNeverHadIsStillReportedAsUnknown() {
        let engine = makeApprovalEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp")
        XCTAssertFalse(engine.resolveApproval(requestId: "never_seen", decision: .allow))
    }
}
