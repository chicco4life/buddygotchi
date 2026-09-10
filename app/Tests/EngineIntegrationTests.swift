import XCTest
import AppKit
@testable import BoopCore

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
private final class MockPopoverPresenter: PopoverPresenting {
    var isPopoverShown = false
    var isInteractiveModeEnabled = false
    var showCalls: [(isApproval: Bool, dismissAfter: TimeInterval)] = []
    var closeCount = 0
    var cancelCount = 0

    func showPopover(isApproval: Bool, dismissAfter seconds: TimeInterval) {
        isPopoverShown = true
        showCalls.append((isApproval: isApproval, dismissAfter: seconds))
    }

    func closePopover() {
        isPopoverShown = false
        closeCount += 1
    }

    func cancelPopoverAutoDismiss() {
        cancelCount += 1
    }
}

@MainActor
final class StatusItemSpy: StatusItemPresenting {
    var image: NSImage?
    var toolTip: String?
}

@MainActor
private final class MockNotifier: DesktopNotificationPosting {
    var postedIds: [String] = []
    var clearedIds: [String] = []

    func postToolNotification(prompt: Prompt) {
        postedIds.append(prompt.id)
    }

    func clearNotification(promptId: String) {
        clearedIds.append(promptId)
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
        approvalMode: false,
        token: "test-token"
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

        XCTAssertEqual(recorder.last?.pet.state, .celebrate)
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
    func testDoneOverridesBusy() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        XCTAssertEqual(engine.state.pet.state, .celebrate)

        engine.activitySignal(sessionId: "s2", source: "cursor", signal: .startWorking)
        XCTAssertEqual(engine.state.pet.state, .celebrate)
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

        clock.advance(by: 1_000)
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

    @MainActor
    func testResolveAllPendingApprovalsCanPassthrough() async {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1",
                requestId: "r1",
                tool: "Bash",
                hint: "cmd",
                sessionLabel: nil,
                source: "claude-code"
            )
        }
        await Task.yield()

        engine.resolveAllPendingApprovals(decision: .passthrough)

        let decision = await approvalTask.value
        XCTAssertEqual(decision, .passthrough)
        XCTAssertNil(engine.state.prompt)
        XCTAssertEqual(engine.state.pet.state, .idle)
    }

    @MainActor
    func testRemovedSessionWithPendingApprovalPassthroughs() async {
        let (engine, _, _) = makeTestEngine(staleMs: 100)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1",
                requestId: "r1",
                tool: "Bash",
                hint: "cmd",
                sessionLabel: nil,
                source: "claude-code"
            )
        }
        await Task.yield()

        engine.sessionEnded(sessionId: "s1")

        let decision = await approvalTask.value
        XCTAssertEqual(decision, .passthrough)
    }

    @MainActor
    func testStaleReapResolvesPendingApprovalAsPassthrough() async {
        let (engine, _, clock) = makeTestEngine(staleMs: 1_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)

        let approvalTask = Task { @MainActor in
            await engine.submitApproval(
                sessionId: "s1", requestId: "r1",
                tool: "Bash", hint: "rm -rf",
                sessionLabel: nil, source: "claude-code"
            )
        }
        await Task.yield()
        XCTAssertEqual(engine.state.pet.state, .attention)

        clock.advance(by: 2_000)
        engine.triggerStaleTick()
        let decision = await approvalTask.value

        XCTAssertEqual(decision, .passthrough)
        XCTAssertEqual(engine.state.sessions.total, 0)
        XCTAssertEqual(engine.state.pet.state, .sleep)
    }

    @MainActor
    func testSetSpeciesUpdatesStateAndHeartbeat() {
        // renderState prefers the persisted buddySpecies preference over the
        // state it is handed, so this test is only meaningful with that
        // preference out of the way. Without this it passes on a clean machine
        // and fails on a developer's — the running app writes the key when the
        // device announces its species on connect.
        let key = DefaultsKey.buddySpecies
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let (engine, _, _) = makeTestEngine()
        engine.setSpecies("duck")

        XCTAssertEqual(engine.state.pet.species, "duck")
        XCTAssertEqual(engine.state.pet.species, "duck")
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
        let config = BuddyConfig(httpPort: 0, staleTimeoutMs: 600_000, celebrateDurationMs: 4_000, stateDir: "/tmp", approvalMode: false, token: "test-token")
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

    @MainActor
    func testDesktopOutputPostsRapidAttentionTransitions() {
        let statusItem = StatusItemSpy()
        let presenter = MockPopoverPresenter()
        let notifier = MockNotifier()
        let output = DesktopOutput(
            statusItem: statusItem,
            presenter: presenter,
            notifier: notifier,
            playCelebrate: {},
            playAttention: {},
            playError: {}
        )

        var attentionOne = BuddyState.initial
        attentionOne.creature.state = .needsYou
        attentionOne.prompt = Prompt(id: "p1", tool: "Bash", hint: "first", arrivedAt: NOW)

        var busy = attentionOne
        busy.creature.state = .working
        busy.prompt = nil

        var attentionTwo = busy
        attentionTwo.creature.state = .needsYou
        attentionTwo.prompt = Prompt(id: "p2", tool: "Bash", hint: "second", arrivedAt: NOW + 1)

        output.stateDidChange(prev: .initial, next: attentionOne)
        output.stateDidChange(prev: attentionOne, next: busy)
        output.stateDidChange(prev: busy, next: attentionTwo)

        let cachedImage = statusItem.image
        output.stateDidChange(prev: attentionTwo, next: attentionTwo)
        XCTAssertTrue(statusItem.image === cachedImage)
        XCTAssertEqual(statusItem.toolTip, "needsYou")
        XCTAssertEqual(statusItem.image?.accessibilityDescription, DesktopOutput.statusIcon(for: attentionTwo.creature).accessibilityDescription)
        XCTAssertEqual(statusItem.image?.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(notifier.postedIds, ["p1", "p2"])
        XCTAssertEqual(notifier.clearedIds, ["p1"])
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

    // MARK: - Gap A: Done / needs review

    @MainActor
    func testClaudePostToolUseThenStopRecordsLastCompletedToolName() {
        let (engine, _, clock) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp/my-app")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        clock.advance(by: 1_500)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "BuddyState.swift")
        clock.advance(by: 500)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)

        XCTAssertEqual(engine.state.pet.state, .celebrate)
        XCTAssertNotNil(engine.state.lastCompleted)
        XCTAssertEqual(engine.state.lastCompleted?.tool, "Edit")
        XCTAssertEqual(engine.state.lastCompleted?.source, "claude-code")
        XCTAssertEqual(engine.state.lastCompleted?.sessionLabel, "my-app")
    }

    @MainActor
    func testReviewSurvivesCelebrateWindowIntoIdleAndDismissClears() {
        let (engine, _, clock) = makeTestEngine(celebrateMs: 4_000)
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        XCTAssertEqual(engine.state.pet.state, .celebrate)
        XCTAssertNotNil(engine.state.lastCompleted)

        // Tick past celebrate window — pet drops to idle but review persists.
        clock.advance(by: 5_000)
        engine.triggerStaleTick()
        XCTAssertEqual(engine.state.pet.state, .idle)
        XCTAssertNotNil(engine.state.lastCompleted, "review survives into idle")

        engine.dismissReview()
        XCTAssertNil(engine.state.lastCompleted, "dismiss clears review")
    }

    @MainActor
    func testMultipleSessionsReviewReflectsCelebratingSessionTool() {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.sessionStarted(sessionId: "s2", source: "cursor", cwd: nil)
        engine.activitySignal(sessionId: "s2", source: "cursor", signal: .startWorking)
        engine.activitySignal(sessionId: "s2", source: "cursor", signal: .keepWorking, tool: "Bash", hint: "ls")
        // s1 finishes; review should be from s1 (the celebrating session), not s2.
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)
        // Because s2 is still working, aggregate clears lastCompleted.
        XCTAssertNil(engine.state.lastCompleted, "concurrent working session suppresses review")
        XCTAssertEqual(engine.state.pet.state, .celebrate, "s1 done takes priority over s2 working")

        // Once s2 also stops, reviewing the celebrating session would only return if it celebrates again.
        // This documents the priority: review never overrides live state.
    }

    @MainActor
    func testCursorStopSignalGoesThroughCelebratePath() {
        // Engine-level test. The HookServer's /hook/signal endpoint translates Cursor's
        // "stop_working" signal to .celebrate; here we simulate the engine call after
        // that translation.
        let (engine, recorder, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "c1", source: "cursor", cwd: nil)
        engine.activitySignal(sessionId: "c1", source: "cursor", signal: .startWorking)
        engine.activitySignal(sessionId: "c1", source: "cursor", signal: .keepWorking, tool: "Bash", hint: "swift test")
        engine.activitySignal(sessionId: "c1", source: "cursor", signal: .celebrate)
        XCTAssertEqual(recorder.last?.pet.state, .celebrate)
        XCTAssertNotNil(recorder.last?.lastCompleted)
        XCTAssertEqual(recorder.last?.lastCompleted?.source, "cursor")
        XCTAssertEqual(recorder.last?.lastCompleted?.tool, "Bash")
    }

    @MainActor
    func testHeartbeatEmitsDoneCheerAndEngineTime() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/tmp/my-app")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .celebrate)

        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.state, .done)
        XCTAssertNotNil(rs.cheer)
        XCTAssertEqual(rs.t, Int(engine.deviceFrameTime))
    }


    @MainActor
    func testHeartbeatEmitsWorkingEffort() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Read", hint: "Package.swift")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "BuddyState.swift")

        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.state, .working)
        XCTAssertNotNil(rs.effort)
    }

    @MainActor
    func testWorkingWithoutBubbleOmitsBubble() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertNil(rs.bubble)
    }

    @MainActor
    func testHeartbeatCountsSessionDots() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        for i in 1...10 {
            engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "file\(i).swift")
        }
        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.dots, 1)
    }

    @MainActor
    func testHeartbeatMapsErrorToUhoh() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "npm test")
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .error)

        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.state, .uhoh)
        XCTAssertEqual(rs.uhoh, .error)
    }

    @MainActor
    func testHeartbeatMapsErrorWithoutToolToUhoh() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .error)

        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.state, .uhoh)
        XCTAssertEqual(rs.uhoh, .error)
    }

    @MainActor
    func testHeartbeatRemainsWorkingAcrossToolKinds() throws {
        let (engine, _, _) = makeTestEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        let rs = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs.state, .working)

        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "Foo.swift")
        let rs2 = renderState(from: engine.state, now: engine.deviceFrameTime)
        XCTAssertEqual(rs2.state, .working)
    }
}

extension EngineIntegrationTests {
    @MainActor
    func testTurnStartedReachesCreature() {
        let (engine, recorder, _) = makeTestEngine()
        engine.turnStarted(sessionId: "new", source: "codex")
        XCTAssertEqual(recorder.last?.creature.state, .working)
    }

    @MainActor
    func testToolCalledReachesCreature() {
        let (engine, recorder, clock) = makeTestEngine()
        for _ in 0..<6 {
            clock.advance(by: 1)
            engine.toolCalled(sessionId: "new", source: "codex", tool: "Bash", hint: "test", goal: "opaque")
        }
        XCTAssertNil(recorder.last?.creature.uhoh)
    }

    @MainActor
    func testToolResultedReachesCreature() {
        let (engine, recorder, clock) = makeTestEngine()
        engine.turnEnded(sessionId: "new", source: "codex", outcome: .failed(errorClass: "rate_limit"))
        clock.advance(by: 1)
        engine.toolResulted(sessionId: "new", source: "codex", tool: "Bash", ok: true)
        XCTAssertEqual(recorder.last?.creature.state, .working)
        XCTAssertNil(recorder.last?.creature.uhoh)
    }

    @MainActor
    func testTurnEndedReachesCreature() {
        let (engine, recorder, clock) = makeTestEngine()
        engine.turnStarted(sessionId: "new", source: "codex")
        clock.advance(by: 100)
        engine.turnEnded(sessionId: "new", source: "codex", outcome: .completed)
        XCTAssertEqual(recorder.last?.creature.cheer, .hop)
    }

    @MainActor
    func testFocusToggledReachesCreature() {
        let (engine, recorder, _) = makeTestEngine()
        engine.focusToggled(on: true)
        XCTAssertEqual(recorder.last?.creature.focus, true)
    }

    @MainActor
    func testNudgeDismissedReachesCreature() {
        let (engine, recorder, clock) = makeTestEngine()
        engine.submitRequest(sessionId: "new", requestId: "p", tool: "Bash", hint: "build", sessionLabel: nil)
        for _ in 0..<3 {
            clock.advance(by: 1)
            engine.nudgeDismissed()
        }
        XCTAssertNil(recorder.last?.creature.bubble)
    }
}

extension EngineIntegrationTests {
    @MainActor
    func testDeviceCommandsReachEngineThroughParser() throws {
        let (engine, _, clock) = makeTestEngine()
        for line in [#"{"cmd":"posture","p":"travel"}"#, #"{"cmd":"battery","pct":73,"charging":true}"#, #"{"cmd":"focus","on":true}"#] {
            engine.handleDeviceCommand(try XCTUnwrap(parseDeviceLine(line)))
        }
        XCTAssertEqual(engine.state.devicePosture, .travel)
        XCTAssertEqual(engine.state.deviceBattery, DeviceBattery(pct: 73, charging: true))
        XCTAssertTrue(engine.state.creature.focus)
        engine.handleDeviceCommand(try XCTUnwrap(parseDeviceLine(#"{"cmd":"focus","on":false}"#)))
        XCTAssertFalse(engine.state.creature.focus)
        engine.turnStarted(sessionId: "wire", source: "codex")
        clock.advance(by: 1000)
        engine.turnEnded(sessionId: "wire", source: "codex", outcome: .completed)
        clock.advance(by: 1500)
        engine.triggerStaleTick()
        XCTAssertNil(parseDeviceLine(#"{"cmd":"collect"}"#))
        let before = engine.state
        engine.handleDeviceCommand(try XCTUnwrap(parseDeviceLine(#"{"cmd":"motion","m":"shake"}"#)))
        XCTAssertEqual(engine.state, before)
    }

    @MainActor
    func testDeviceDecisionThroughParserResolvesContinuation() async throws {
        let (engine, _, _) = makeTestEngine()
        for legacy in [false, true] {
            let id = "wire-id-테스트-" + String(repeating: "x", count: 30)
            let result = Task { @MainActor in
                await engine.submitApproval(sessionId: "wire", requestId: id, tool: "Bash", hint: "test", sessionLabel: nil, source: "codex")
            }
            await Task.yield()
            let line = "{\"cmd\":\"\(legacy ? "permission" : "decision")\",\"id\":\"\(id.prefix(utf8Bytes: 23))\",\"\(legacy ? "decision" : "d")\":\"allow\"}"
            engine.handleDeviceCommand(try XCTUnwrap(parseDeviceLine(line)))
            let decision = await result.value
            XCTAssertEqual(decision, .allow)
        }
    }
}
