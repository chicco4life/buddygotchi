import XCTest
@testable import Buddygotchi

// MARK: - Test Infrastructure

@MainActor
final class MockClock: Clock {
    var time: Double = 1_000_000
    func now() -> Double { time }
    func advance(by ms: Double) { time += ms }
}

@MainActor
final class EchoRecorder: OutputProvider {
    let id = "echo"
    var transitions: [(prev: BuddyState, next: BuddyState)] = []

    var last: BuddyState? { transitions.last?.next }
    var count: Int { transitions.count }

    func start(engine: BuddyEngine) async {}
    func stop() async {}

    func stateDidChange(prev: BuddyState, next: BuddyState) {
        transitions.append((prev: prev, next: next))
    }
}

@MainActor
private func makeTestEngine(
    staleMs: Double = 600_000,
    celebrateMs: Double = 4_000
) -> (BuddyEngine, EchoRecorder, MockClock) {
    let clock = MockClock()
    let config = BuddyConfig(
        httpPort: 0,
        staleTimeoutMs: staleMs,
        celebrateDurationMs: celebrateMs,
        stateDir: "/tmp",
        approvalMode: false
    )
    let engine = BuddyEngine(config: config, clock: clock)
    let recorder = EchoRecorder()
    engine.register(output: recorder)
    return (engine, recorder, clock)
}

// MARK: - Tests

final class EngineIntegrationTests: XCTestCase {

    // MARK: A. Connection Lifecycle

    @MainActor
    func testInitialStateIsDisconnectedSleeping() {
        let (engine, recorder, _) = makeTestEngine()
        XCTAssertEqual(engine.state.desktop.status, .disconnected)
        XCTAssertEqual(engine.state.pet.state, .sleep)
        XCTAssertEqual(recorder.count, 0)
    }

    @MainActor
    func testSessionStartConnects() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/project")

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.last?.desktop.status, .connected)
        XCTAssertEqual(recorder.last?.pet.state, .idle)
        XCTAssertEqual(recorder.last?.sessions.total, 1)
    }

    @MainActor
    func testSessionEndDisconnects() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionEnded(sessionId: "s1")

        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(recorder.last?.desktop.status, .disconnected)
        XCTAssertEqual(recorder.last?.pet.state, .sleep)
        XCTAssertEqual(recorder.last?.sessions.total, 0)
    }

    @MainActor
    func testMultipleSessionsStayConnectedUntilAllEnd() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        XCTAssertEqual(recorder.last?.sessions.total, 2)
        XCTAssertEqual(recorder.last?.desktop.status, .connected)

        engine.sessionEnded(sessionId: "s1")
        XCTAssertEqual(recorder.last?.desktop.status, .connected)
        XCTAssertEqual(recorder.last?.sessions.total, 1)

        engine.sessionEnded(sessionId: "s2")
        XCTAssertEqual(recorder.last?.desktop.status, .disconnected)
        XCTAssertEqual(recorder.last?.sessions.total, 0)
    }

    // MARK: B. Pet State Transitions

    @MainActor
    func testStartWorkingSetsBusy() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)

        XCTAssertEqual(recorder.last?.pet.state, .busy)
    }

    @MainActor
    func testStopWorkingSetsIdle() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .stopWorking)

        XCTAssertEqual(recorder.last?.pet.state, .idle)
    }

    @MainActor
    func testKeepWorkingMaintainsBusy() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking)

        XCTAssertEqual(recorder.last?.pet.state, .busy)
    }

    @MainActor
    func testRequestArrivedSetsAttention() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf /", sessionLabel: "project")

        XCTAssertEqual(recorder.last?.pet.state, .attention)
        XCTAssertNotNil(recorder.last?.prompt)
        XCTAssertEqual(recorder.last?.prompt?.tool, "Bash")
        XCTAssertEqual(recorder.last?.prompt?.hint, "rm -rf /")
    }

    @MainActor
    func testClearRequestReturnsToBusy() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "ls", sessionLabel: nil)
        engine.clearRequest(sessionId: "s1")

        XCTAssertEqual(recorder.last?.pet.state, .busy)
        XCTAssertNil(recorder.last?.prompt)
    }

    @MainActor
    func testCelebrateSignalSetsCelebrate() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)

        XCTAssertEqual(recorder.last?.pet.state, .celebrate)
        XCTAssertNotNil(recorder.last?.celebrateUntil)
    }

    // MARK: C. Session Counts

    @MainActor
    func testSessionCountsReflectActiveSessions() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        XCTAssertEqual(recorder.last?.sessions, SessionCounts(total: 2, running: 0, waiting: 0))

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        XCTAssertEqual(recorder.last?.sessions.running, 1)

        engine.submitRequest(sessionId: "s2", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil)
        XCTAssertEqual(recorder.last?.sessions, SessionCounts(total: 2, running: 2, waiting: 1))
    }

    @MainActor
    func testWaitingCountIncludesApprovals() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil)

        XCTAssertEqual(recorder.last?.sessions.waiting, 1)
    }

    @MainActor
    func testEndedSessionDecrementsCount() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)
        engine.sessionEnded(sessionId: "s1")

        XCTAssertEqual(recorder.last?.sessions.total, 1)
    }

    // MARK: D. Prompt Selection

    @MainActor
    func testPromptShowsOldestWaitingRequest() {
        let (engine, _, clock) = makeTestEngine()

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        clock.advance(by: 100)
        engine.submitRequest(sessionId: "s2", requestId: "r2", tool: "Write", hint: "file", sessionLabel: nil)

        clock.advance(by: 100)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "cmd", sessionLabel: nil)

        XCTAssertEqual(engine.state.prompt?.id, "r2")
    }

    @MainActor
    func testPromptClearsWhenNoWaitingSessions() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil)
        engine.clearRequest(sessionId: "s1")

        XCTAssertNil(engine.state.prompt)
    }

    @MainActor
    func testPromptShowsApprovalFields() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        Task { @MainActor in
            _ = await engine.submitApproval(
                sessionId: "s1", requestId: "r1",
                tool: "Bash", hint: "rm -rf",
                sessionLabel: "proj", source: "claude-code"
            )
        }
        await Task.yield()

        XCTAssertEqual(engine.state.prompt?.isApproval, true)
        XCTAssertEqual(engine.state.prompt?.source, "claude-code")
    }

    // MARK: E. Priority Ordering

    @MainActor
    func testAttentionOverridesBusy() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        XCTAssertEqual(engine.state.pet.state, .busy)

        engine.submitRequest(sessionId: "s2", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil)
        XCTAssertEqual(engine.state.pet.state, .attention)
    }

    @MainActor
    func testAttentionOverridesCelebrate() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        XCTAssertEqual(engine.state.pet.state, .celebrate)

        engine.submitRequest(sessionId: "s2", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil)
        XCTAssertEqual(engine.state.pet.state, .attention)
    }

    @MainActor
    func testBusyOverridesCelebrate() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        XCTAssertEqual(engine.state.pet.state, .celebrate)

        engine.activitySignal(sessionId: "s2", source: "cursor", signal: .startWorking)
        XCTAssertEqual(engine.state.pet.state, .busy)
    }

    // MARK: F. Celebrate Behavior

    @MainActor
    func testCelebrateExpiresAfterDuration() {
        let (engine, _, clock) = makeTestEngine(celebrateMs: 4_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        XCTAssertEqual(engine.state.pet.state, .celebrate)

        clock.advance(by: 5_000)
        engine.triggerStaleTick()

        XCTAssertEqual(engine.state.pet.state, .idle)
        XCTAssertNil(engine.state.celebrateUntil)
    }

    @MainActor
    func testCelebrateStillActiveBeforeDuration() {
        let (engine, _, clock) = makeTestEngine(celebrateMs: 4_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)

        clock.advance(by: 2_000)
        engine.triggerStaleTick()

        XCTAssertEqual(engine.state.pet.state, .celebrate)
    }

    @MainActor
    func testCelebrateRecordsTaskDuration() {
        let (engine, _, clock) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)

        clock.advance(by: 10_000)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)

        XCTAssertEqual(engine.state.lastTaskDurationMs, 10_000)
    }

    // MARK: G. Approval Flow

    @MainActor
    func testApprovalArrivedSetsAttention() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        Task { @MainActor in
            _ = await engine.submitApproval(
                sessionId: "s1", requestId: "r1",
                tool: "Bash", hint: "cmd",
                sessionLabel: nil, source: "claude-code"
            )
        }
        await Task.yield()

        XCTAssertEqual(engine.state.pet.state, .attention)
        XCTAssertEqual(engine.state.prompt?.isApproval, true)
    }

    @MainActor
    func testApprovalAllowResumesWorking() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1", requestId: "r1",
                tool: "Bash", hint: "cmd",
                sessionLabel: nil, source: "claude-code"
            )
        }
        await Task.yield()

        XCTAssertEqual(engine.state.pet.state, .attention)

        engine.resolveApproval(requestId: "r1", decision: .allow)
        let decision = await approvalTask.value

        XCTAssertEqual(decision, .allow)
        XCTAssertEqual(engine.state.pet.state, .busy)
        XCTAssertNil(engine.state.prompt)
    }

    @MainActor
    func testApprovalDenyGoesIdle() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1", requestId: "r1",
                tool: "Bash", hint: "cmd",
                sessionLabel: nil, source: "claude-code"
            )
        }
        await Task.yield()

        engine.resolveApproval(requestId: "r1", decision: .deny)
        let decision = await approvalTask.value

        XCTAssertEqual(decision, .deny)
        XCTAssertEqual(engine.state.pet.state, .idle)
    }

    @MainActor
    func testResolveAllPendingApprovals() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        let t1 = Task { @MainActor in
            await engine.submitApproval(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "a", sessionLabel: nil, source: "claude-code")
        }
        let t2 = Task { @MainActor in
            await engine.submitApproval(sessionId: "s2", requestId: "r2", tool: "Write", hint: "b", sessionLabel: nil, source: "cursor")
        }
        await Task.yield()

        engine.resolveAllPendingApprovals(decision: .allow)

        let d1 = await t1.value
        let d2 = await t2.value
        XCTAssertEqual(d1, .allow)
        XCTAssertEqual(d2, .allow)
        XCTAssertNil(engine.state.prompt)
    }

    // MARK: H. Output Contract

    @MainActor
    func testRecorderReceivesEveryStateChange() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .stopWorking)
        engine.sessionEnded(sessionId: "s1")

        XCTAssertEqual(recorder.count, 4)
    }

    @MainActor
    func testRecorderPrevMatchesPreviousNext() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.sessionEnded(sessionId: "s1")

        for i in 1..<recorder.transitions.count {
            XCTAssertEqual(recorder.transitions[i].prev, recorder.transitions[i - 1].next)
        }
    }

    @MainActor
    func testMultipleOutputsAllReceiveChanges() {
        let clock = MockClock()
        let config = BuddyConfig(httpPort: 0, staleTimeoutMs: 600_000, celebrateDurationMs: 4_000, stateDir: "/tmp", approvalMode: false)
        let engine = BuddyEngine(config: config, clock: clock)
        let r1 = EchoRecorder()
        let r2 = EchoRecorder()
        engine.register(output: r1)
        engine.register(output: r2)

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)

        XCTAssertEqual(r1.count, r2.count)
        XCTAssertEqual(r1.last, r2.last)
    }

    // MARK: I. Edge Cases

    @MainActor
    func testDuplicateSessionStartIsIdempotent() {
        let (engine, _, clock) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        clock.advance(by: 100)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        XCTAssertEqual(engine.state.sessions.total, 1)
    }

    @MainActor
    func testEndNonexistentSessionIsNoop() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionEnded(sessionId: "ghost")

        XCTAssertEqual(recorder.count, 0)
    }

    @MainActor
    func testClearRequestWithoutPendingIsNoop() {
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.clearRequest(sessionId: "s1")

        XCTAssertEqual(recorder.count, 1)
    }

    // MARK: J. Stale Timeout

    @MainActor
    func testStaleTickRemovesExpiredSession() {
        let (engine, _, clock) = makeTestEngine(staleMs: 600_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        clock.advance(by: 700_000)
        engine.triggerStaleTick()

        XCTAssertEqual(engine.state.desktop.status, .disconnected)
        XCTAssertEqual(engine.state.pet.state, .sleep)
        XCTAssertEqual(engine.state.sessions.total, 0)
    }

    @MainActor
    func testStaleTickKeepsFreshSession() {
        let (engine, _, clock) = makeTestEngine(staleMs: 600_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        clock.advance(by: 300_000)
        engine.triggerStaleTick()

        XCTAssertEqual(engine.state.desktop.status, .connected)
        XCTAssertEqual(engine.state.sessions.total, 1)
    }
}
