import AppKit
import Foundation
import XCTest
@testable import BoopCore

/// Covers what the desktop plays and — more importantly — the cases that used
/// to be silent: sub-30s completions, a second approval inside an existing
/// attention state, and one agent finishing while another keeps working.
final class ChirpDecisionTests: XCTestCase {

    private func start(_ sessionId: String, at: Double = NOW, source: String = "claude-code") -> BuddyEvent {
        .sessionStarted(at: at, sessionId: sessionId, source: source, cwd: "/tmp")
    }

    private func work(_ sessionId: String, at: Double, source: String = "claude-code") -> BuddyEvent {
        .activitySignal(at: at, sessionId: sessionId, source: source, signal: .startWorking, tool: "Edit", hint: "main.swift")
    }

    private func done(_ sessionId: String, at: Double, source: String = "claude-code") -> BuddyEvent {
        .activitySignal(at: at, sessionId: sessionId, source: source, signal: .celebrate, tool: "Edit", hint: "main.swift")
    }

    private func chirp(_ prev: InternalState, _ next: InternalState) -> Chirp? {
        ChirpDecision.chirp(prev: prev.buddy, next: next.buddy, soundsEnabled: true)
    }

    // MARK: - Completion

    func testCompletedTaskChirpsOnce() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let finished = applyEvents(working, done("s1", at: NOW + 10_000))

        XCTAssertEqual(chirp(working, finished), .complete)
        // A subsequent tick with no new completion must stay quiet.
        let ticked = applyEvents(finished, .staleTick(at: NOW + 11_000))
        XCTAssertNil(chirp(finished, ticked))
    }

    func testShortTaskIsSilent() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let finished = applyEvents(working, done("s1", at: NOW + 500))

        XCTAssertNil(chirp(working, finished))
    }

    func testTaskAtThresholdChirps() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let finished = applyEvents(working, done("s1", at: NOW + ChirpDecision.minCompletionDurationMs))

        XCTAssertEqual(chirp(working, finished), .complete)
    }

    /// The completion marker survives legacy review-card suppression while
    /// another session is working, even though done now wins the projection.
    func testCompletionChirpsWhileAnotherAgentKeepsWorking() {
        let both = applyEvents(
            .test(),
            start("s1"), start("s2", source: "cursor"),
            work("s1", at: NOW), work("s2", at: NOW, source: "cursor")
        )
        let oneDone = applyEvents(both, done("s1", at: NOW + 10_000))

        XCTAssertEqual(oneDone.buddy.pet.state, .celebrate, "done outranks the working peer")
        XCTAssertNil(oneDone.buddy.lastCompleted, "aggregation clears the review card while busy")
        XCTAssertEqual(chirp(both, oneDone), .complete)
    }

    /// Three agents, two finishing back to back while the third works on.
    /// The folded done state has no second edge; the completion marker still
    /// carries each finish to the existing sound policy.
    func testConsecutiveCompletionsEachChirpWithNoPetStateEdge() {
        let all = applyEvents(
            .test(),
            start("s1"), start("s2", source: "cursor"), start("s3", source: "codex"),
            work("s1", at: NOW), work("s2", at: NOW, source: "cursor"), work("s3", at: NOW, source: "codex")
        )
        let first = applyEvents(all, done("s1", at: NOW + 10_000))
        let second = applyEvents(first, done("s2", at: NOW + 11_000, source: "cursor"))

        XCTAssertEqual(all.buddy.pet.state, .busy)
        XCTAssertEqual(first.buddy.pet.state, .celebrate)
        XCTAssertEqual(second.buddy.pet.state, .celebrate, "the folded done state has no second state edge")
        XCTAssertEqual(chirp(all, first), .complete)
        XCTAssertEqual(chirp(first, second), .complete)
    }

    // MARK: - Attention

    func testApprovalChirpsAttention() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let waiting = applyEvents(working, .approvalArrived(
            at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
            tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code"
        ))

        XCTAssertEqual(chirp(working, waiting), .attention)
    }

    /// A second agent asking while the first is still waiting keeps the pet in
    /// .attention, so the pet-state guard used to make this silent.
    func testSecondApprovalDuringAttentionChirpsAgain() {
        let waiting = applyEvents(
            .test(),
            start("s1"), start("s2", source: "cursor"),
            .approvalArrived(at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
                             tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code")
        )
        let bothWaiting = applyEvents(waiting, .approvalArrived(
            at: NOW + 2_000, sessionId: "s2", requestId: "req_2",
            tool: "Write", hint: "config.json", sessionLabel: nil, source: "cursor"
        ))

        XCTAssertEqual(waiting.buddy.pet.state, .attention)
        XCTAssertEqual(bothWaiting.buddy.pet.state, .attention)
        XCTAssertEqual(chirp(waiting, bothWaiting), .attention)
    }

    /// Resolving the first of two queued approvals promotes the second to
    /// `buddy.prompt`, changing the projected prompt id. Nothing new arrived,
    /// so nothing should sound.
    func testResolvingOneOfTwoApprovalsIsSilentDespitePromptIdChange() {
        let bothWaiting = applyEvents(
            .test(),
            start("s1"), start("s2", source: "cursor"),
            .approvalArrived(at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
                             tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code"),
            .approvalArrived(at: NOW + 2_000, sessionId: "s2", requestId: "req_2",
                             tool: "Write", hint: "config.json", sessionLabel: nil, source: "cursor")
        )
        let oneResolved = applyEvents(bothWaiting, .approvalResolved(
            at: NOW + 3_000, sessionId: "s1", requestId: "req_1", decision: .allow
        ))

        XCTAssertNotEqual(bothWaiting.buddy.prompt?.id, oneResolved.buddy.prompt?.id, "queue advanced")
        XCTAssertEqual(oneResolved.buddy.pet.state, .attention, "s2 still waiting")
        XCTAssertNil(chirp(bothWaiting, oneResolved))
    }

    func testResolvingApprovalIsSilent() {
        let waiting = applyEvents(
            .test(),
            start("s1"),
            .approvalArrived(at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
                             tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code")
        )
        let resolved = applyEvents(waiting, .approvalResolved(
            at: NOW + 2_000, sessionId: "s1", requestId: "req_1", decision: .allow
        ))

        XCTAssertNil(chirp(waiting, resolved))
    }

    // MARK: - Error

    func testErrorChirpsOnce() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let failed = applyEvents(working, .activitySignal(
            at: NOW + 1_000, sessionId: "s1", source: "claude-code",
            signal: .error, tool: "Bash", hint: "npm test"
        ))

        XCTAssertEqual(failed.buddy.pet.state, .error)
        XCTAssertEqual(chirp(working, failed), .error)

        let ticked = applyEvents(failed, .staleTick(at: NOW + 2_000))
        XCTAssertNil(chirp(failed, ticked), "still errored — one problem, one chirp")
    }

    /// Attention outranks a simultaneous completion: the thing that needs the
    /// user beats the thing that doesn't.
    func testAttentionWinsOverCompletion() {
        let both = applyEvents(
            .test(),
            start("s1"), start("s2", source: "cursor"),
            work("s1", at: NOW), work("s2", at: NOW, source: "cursor")
        )
        let mixed = applyEvents(
            both,
            done("s1", at: NOW + 10_000),
            .approvalArrived(at: NOW + 10_000, sessionId: "s2", requestId: "req_1",
                             tool: "Bash", hint: "npm test", sessionLabel: nil, source: "cursor")
        )

        XCTAssertEqual(chirp(both, mixed), .attention)
    }

    // MARK: - Mute

    func testSoundsDisabledSilencesEverything() {
        let working = applyEvents(.test(), start("s1"), work("s1", at: NOW))
        let finished = applyEvents(working, done("s1", at: NOW + 10_000))
        let waiting = applyEvents(working, .approvalArrived(
            at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
            tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code"
        ))

        XCTAssertNil(ChirpDecision.chirp(prev: working.buddy, next: finished.buddy, soundsEnabled: false))
        XCTAssertNil(ChirpDecision.chirp(prev: working.buddy, next: waiting.buddy, soundsEnabled: false))
    }

    func testInitialStateIsSilent() {
        XCTAssertNil(ChirpDecision.chirp(prev: .initial, next: .initial, soundsEnabled: true))
    }
}

// MARK: - Wiring

@MainActor
private final class StubPresenter: PopoverPresenting {
    var isPopoverShown = false
    var isInteractiveModeEnabled = false
    func closePopover() { isPopoverShown = false }
    func cancelPopoverAutoDismiss() {}
}

@MainActor
private final class StubNotifier: DesktopNotificationPosting {
    var postedIds: [String] = []
    func postToolNotification(prompt: Prompt) { postedIds.append(prompt.id) }
    func clearNotification(promptId: String) {}
}

/// The decision tests above prove the policy; this proves it is actually
/// reached — that `stateDidChange` still routes to the playback closures.
@MainActor
final class DesktopOutputSoundTests: XCTestCase {

    private func makeOutput(soundsEnabled: Bool = true) -> (DesktopOutput, () -> [String]) {
        var played: [String] = []
        let statusItem: NSStatusItem? = nil // No WindowServer connection is needed for output behavior tests.
        let output = DesktopOutput(
            statusItem: statusItem,
            presenter: StubPresenter(),
            notifier: StubNotifier(),
            soundsEnabled: { soundsEnabled },
            playCelebrate: { played.append("celebrate") },
            playAttention: { played.append("attention") },
            playError: { played.append("error") }
        )
        return (output, { played })
    }

    func testCompletionReachesThePlaybackClosure() {
        let (output, played) = makeOutput()

        let working = applyEvents(
            .test(),
            .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/tmp"),
            .activitySignal(at: NOW, sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Edit", hint: "x")
        )
        let finished = applyEvents(working, .activitySignal(
            at: NOW + 10_000, sessionId: "s1", source: "claude-code", signal: .celebrate, tool: "Edit", hint: "x"
        ))

        output.stateDidChange(prev: working.buddy, next: finished.buddy)

        XCTAssertEqual(played(), ["celebrate"])
    }

    func testMutedOutputPlaysNothing() {
        let (output, played) = makeOutput(soundsEnabled: false)

        let idle = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        let waiting = applyEvents(idle, .approvalArrived(
            at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
            tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code"
        ))

        output.stateDidChange(prev: idle.buddy, next: waiting.buddy)

        XCTAssertEqual(played(), [])
    }

    func testApprovalReachesThePlaybackClosure() {
        let (output, played) = makeOutput()

        let idle = applyEvents(.test(), .sessionStarted(at: NOW, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        let waiting = applyEvents(idle, .approvalArrived(
            at: NOW + 1_000, sessionId: "s1", requestId: "req_1",
            tool: "Bash", hint: "npm test", sessionLabel: nil, source: "claude-code"
        ))

        output.stateDidChange(prev: idle.buddy, next: waiting.buddy)

        XCTAssertEqual(played(), ["attention"])
    }
}
