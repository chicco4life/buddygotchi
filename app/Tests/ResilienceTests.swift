import Foundation
import XCTest
@testable import BoopCore

/// Resilience invariants: a prompt lives exactly as long as something is
/// verifiably waiting for the answer, and a quiet session is not a dead one.
///
/// - Abandonment (`.approvalAbandoned`): the blocked hook's HTTP connection
///   closing is the one reliable "nobody is waiting" signal; the card must
///   come down immediately, and late/duplicate abandons must be no-ops.
/// - Supervision (`.processWatchChanged`): a session with a live process
///   watcher is exempt from the stale reap — the watcher reports death
///   definitively, so silence alone must not put the pet to sleep.
/// - The timeout chain: reducer < curl < registered hook timeout, so each
///   layer's card dies before its caller gives up.
final class ResilienceTests: XCTestCase {

    // MARK: - stopWorking must not withdraw a blocking approval

    func testStopWorkingDoesNotWithdrawBlockingApproval() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code")
        )
        // Claude Code's idle_prompt notification routes to .stopWorking; a hook
        // is still blocked on r1, so the card must survive it.
        s = applyEvents(s, .activitySignal(at: NOW + 60_000, sessionId: "s1", source: "claude-code", signal: .stopWorking, tool: nil, hint: nil))

        XCTAssertEqual(s.buddy.prompt?.id, "r1", "idle signal silently withdrew a blocking approval")
        XCTAssertEqual(s.sessions["s1"]?.state, .needsConfirmation)
    }

    func testStopWorkingStillClearsPassiveNotificationPrompt() {
        // A non-approval card carries no blocked caller — stopWorking may
        // dismiss it, same as before.
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .requestArrived(at: NOW + 1, sessionId: "s1", requestId: "n1", tool: "Notification", hint: "waiting", sessionLabel: nil)
        )
        s = applyEvents(s, .activitySignal(at: NOW + 2, sessionId: "s1", source: "claude-code", signal: .stopWorking, tool: nil, hint: nil))

        XCTAssertNil(s.buddy.prompt)
        XCTAssertEqual(s.sessions["s1"]?.state, .idle)
    }

    // MARK: - Abandonment (hook connection closed)

    @MainActor

    func testAbandonForSupersededPromptLeavesNewPromptAlone() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "a", sessionLabel: nil, source: "claude-code"),
            .approvalArrived(at: NOW + 2, sessionId: "s1", requestId: "r2", tool: "Write", hint: "b", sessionLabel: nil, source: "claude-code")
        )
        // r1's hook hangs up (it was resumed passthrough when r2 replaced it).
        s = applyEvents(s, .approvalAbandoned(at: NOW + 3, sessionId: "s1", requestId: "r1"))

        XCTAssertEqual(s.buddy.prompt?.id, "r2", "abandoning a superseded prompt must not touch its successor")
        XCTAssertEqual(s.sessions["s1"]?.state, .needsConfirmation)
    }

    // MARK: - Supervised sessions and the stale reap

    func testWatchedSessionSurvivesStaleReap() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .processWatchChanged(at: NOW, watchedSessionIds: ["s1"])
        )
        // Way past staleMs with no activity — a 15-minute quiet build.
        s = applyEvents(s, .staleTick(at: NOW + TEST_STALE_MS + 100_000))

        XCTAssertNotNil(s.sessions["s1"], "a supervised session must not be reaped for silence")
        XCTAssertEqual(s.buddy.desktop.status, .connected)
    }

    func testUnwatchedSessionStillReaped() {
        var s = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .processWatchChanged(at: NOW, watchedSessionIds: ["s1"])
        )
        // Watcher fires or is cancelled — supervision ends, silence counts again.
        s = applyEvents(s, .processWatchChanged(at: NOW + 1, watchedSessionIds: []))
        s = applyEvents(s, .staleTick(at: NOW + TEST_STALE_MS + 100_000))

        XCTAssertNil(s.sessions["s1"])
        XCTAssertEqual(s.buddy.pet.state, .sleep)
    }

    func testWatchedSessionPromptStillExpires() {
        // Supervision keeps the SESSION alive; the PROMPT still dies on the
        // approval timeout, because past it the blocked curl has already
        // given up and nobody can receive the answer.
        var s = InternalState.initial(staleMs: TEST_STALE_MS, celebrateDurationMs: 4000, approvalTimeoutMs: 1_000)
        s = applyEvents(
            s,
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: nil),
            .approvalArrived(at: NOW + 1, sessionId: "s1", requestId: "r1", tool: "Bash", hint: "x", sessionLabel: nil, source: "claude-code"),
            .processWatchChanged(at: NOW, watchedSessionIds: ["s1"])
        )
        s = applyEvents(s, .staleTick(at: NOW + 5_000))

        XCTAssertNil(s.buddy.prompt, "prompt expiry applies even to supervised sessions")
        XCTAssertNotNil(s.sessions["s1"], "but the session itself survives")
    }

    // MARK: - The timeout chain

    // MARK: - Real-server disconnect abandonment

    /// Boots the REAL Hummingbird server on a spare port and hangs up a real
    /// TCP connection mid-approval. This is the one path the engine-level
    /// tests cannot reach: the whole design rests on the channel's
    /// closeFuture firing when the blocked hook's curl dies, and only an
    /// actual socket close can prove that.
    @MainActor
    private func pollUntil(
        timeoutMs: Int,
        what: String,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("timed out waiting for: \(what)")
    }

}

@MainActor
private func makeResilienceEngine() -> (BuddyEngine, EchoRecorder, MockClock) {
    let clock = MockClock()
    let config = BuddyConfig(
        httpPort: 0,
        staleTimeoutMs: 600_000,
        celebrateDurationMs: 4_000,

        stateDir: "/tmp",
        approvalMode: true,
        token: "test-token"
    )
    let engine = BuddyEngine(config: config, clock: clock)
    let recorder = EchoRecorder()
    engine.register(output: recorder)
    return (engine, recorder, clock)
}
