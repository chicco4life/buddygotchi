import XCTest
@testable import BoopCore

private let expiryNow: Double = 1_000_000

@MainActor
private func makePromptExpiryEngine(approvalTimeoutMs: Double = 300_000) -> (BuddyEngine, MockClock) {
    let clock = MockClock()
    let config = BuddyConfig(
        httpPort: 0,
        staleTimeoutMs: 600_000,
        approvalTimeoutMs: approvalTimeoutMs,
        celebrateDurationMs: 4_000,

        stateDir: "/tmp",
        approvalMode: false,
        token: "test-token"
    )
    return (BuddyEngine(config: config, clock: clock), clock)
}

private func makePromptExpiryState(approvalTimeoutMs: Double = 300_000) -> InternalState {
    .initial(
        staleMs: 600_000,
        celebrateDurationMs: 4_000,

        approvalTimeoutMs: approvalTimeoutMs
    )
}

final class PromptExpiryTests: XCTestCase {
    func testReducerClearsPromptOlderThanApprovalTimeout() {
        var state = makePromptExpiryState(approvalTimeoutMs: 300_000)
        state = reduce(state, .sessionStarted(at: expiryNow, sessionId: "s1", source: "claude-code", cwd: nil))
        state = reduce(state, .approvalArrived(at: expiryNow + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf", sessionLabel: nil, source: "claude-code"))

        state = reduce(state, .staleTick(at: expiryNow + 300_002))

        XCTAssertNil(state.sessions["s1"]?.prompt)
        XCTAssertEqual(state.sessions["s1"]?.state, .idle)
        XCTAssertNil(state.buddy.prompt)
        XCTAssertEqual(state.buddy.pet.state, .idle)
    }

    func testReducerKeepsFreshPromptBeforeApprovalTimeout() {
        var state = makePromptExpiryState(approvalTimeoutMs: 300_000)
        state = reduce(state, .sessionStarted(at: expiryNow, sessionId: "s1", source: "claude-code", cwd: nil))
        state = reduce(state, .approvalArrived(at: expiryNow + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf", sessionLabel: nil, source: "claude-code"))

        state = reduce(state, .staleTick(at: expiryNow + 300_000))

        XCTAssertEqual(state.sessions["s1"]?.prompt?.id, "r1")
        XCTAssertEqual(state.sessions["s1"]?.state, .needsConfirmation)
        XCTAssertEqual(state.buddy.prompt?.id, "r1")
        XCTAssertEqual(state.buddy.pet.state, .attention)
    }

    @MainActor
    func testEngineResolvesPendingApprovalAsPassthroughWhenPromptExpires() async {
        let (engine, clock) = makePromptExpiryEngine(approvalTimeoutMs: 1_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1",
                requestId: "r1",
                tool: "Bash",
                hint: "rm -rf",
                sessionLabel: nil,
                source: "claude-code"
            )
        }
        await Task.yield()
        XCTAssertEqual(engine.state.prompt?.id, "r1")

        clock.advance(by: 1_001)
        engine.triggerStaleTick()

        let decision = await approvalTask.value
        XCTAssertEqual(decision, .passthrough)
        XCTAssertNil(engine.state.prompt)
        XCTAssertEqual(engine.state.sessions.total, 1)
        XCTAssertEqual(engine.state.pet.state, .idle)
    }
}
