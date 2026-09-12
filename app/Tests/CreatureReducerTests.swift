import Foundation
import XCTest
@testable import BoopCore

final class CreatureReducerTests: XCTestCase {
    private func fresh() -> InternalState {
        .initial(staleMs: 10_000_000, celebrateDurationMs: 99, approvalTimeoutMs: 10_000_000)
    }

    private func start(_ s: InternalState, _ at: Double = 0, _ id: String = "a") -> InternalState {
        reduce(s, .turnStarted(at: at, sessionId: id, source: "codex"))
    }

    private func finish(_ s: InternalState, _ at: Double = 100, _ id: String = "a") -> InternalState {
        reduce(s, .turnEnded(at: at, sessionId: id, source: "codex", outcome: .completed))
    }

    private func card(_ hint: String, tool: String = "Bash") -> InternalState {
        reduce(fresh(), .approvalArrived(at: 0, sessionId: "a", requestId: "p", tool: tool, hint: hint, sessionLabel: nil, source: "codex"))
    }

    func testLegacyProjectionEveryStateAndOverlay() {
        let mappings: [(CreatureState, PetState)] = [(.asleep, .sleep), (.idle, .idle), (.working, .busy), (.needsYou, .attention), (.done, .celebrate), (.uhoh, .error)]
        for (state, pet) in mappings {
            var c = Creature.initial
            c.state = state
            XCTAssertEqual(legacyPetState(from: c), pet)
            for overlay in [CreatureOverlay.greet, .boop] {
                c.overlay = overlay
                XCTAssertEqual(legacyPetState(from: c), [.idle, .working, .done].contains(state) ? .heart : pet)
            }
        }
        var c = Creature.initial
        c.state = .uhoh
        c.uhoh = .error
        XCTAssertEqual(legacyPetState(from: c), .error)
    }

    func testCollapseThreeSessionsAndDoneAboveWorking() {
        var s = start(start(start(fresh()), 1, "b"), 2, "c")
        s.sessions["c"]?.workStartedAt = -60_000
        s = finish(s, 100, "c")
        XCTAssertEqual(s.buddy.creature.state, .done)
        s = reduce(s, .turnEnded(at: 101, sessionId: "b", source: "codex", outcome: .failed(errorClass: nil)))
        XCTAssertEqual(s.buddy.creature.state, .uhoh)
        s = reduce(s, .requestArrived(at: 102, sessionId: "a", requestId: "p", tool: "Read", hint: "file", sessionLabel: nil))
        XCTAssertEqual(s.buddy.creature.state, .needsYou)
        XCTAssertEqual(s.buddy.creature.dots, 3)
        XCTAssertEqual(s.buddy.creature.dotAlert, 1)
        s = reduce(s, .requestCleared(at: 103, sessionId: "a"))
        XCTAssertEqual(s.buddy.creature.state, .uhoh)
        s = reduce(s, .errorDismissed(at: 104, sessionId: "b"))
        XCTAssertEqual(s.buddy.creature.state, .working) // interrupted completion never replays
        s = reduce(s, .staleTick(at: 1600))
        XCTAssertEqual(s.buddy.creature.state, .working)
    }

    func testCelebrationsFollowDurationIncludingAfterErrors() {
        for (span, expected): (Double, MomentTier) in [(2999, .face), (3000, .caption), (19999, .caption), (20000, .full)] {
            var s = start(fresh())
            for i in 1...5 { s = reduce(s, .toolResulted(at: Double(i), sessionId: "a", source: "codex", tool: "Bash", ok: false, durationMs: nil)) }
            s = finish(s, span)
            XCTAssertEqual(s.buddy.moment?.tier, expected)
            XCTAssertEqual(s.buddy.moment?.until, span + s.momentPolicy.duration(expected))
        }
    }

    func testFoldKeepsLargerTimerAndUpgradesSmaller() {
        var s = start(start(fresh()), 0, "b")
        s = finish(s, 3000)
        let id = s.buddy.moment?.id
        s.sessions["b"]?.workStartedAt = -20000
        s = finish(s, 3500, "b")
        XCTAssertEqual(s.buddy.moment?.id, id)
        XCTAssertEqual(s.buddy.moment?.tier, .full)
        XCTAssertEqual(s.buddy.moment?.until, 8500)
        s = start(s, 3600)
        s = finish(s, 3700)
        XCTAssertEqual(s.buddy.moment?.tier, .full)
        XCTAssertEqual(s.buddy.moment?.until, 8500)
        XCTAssertEqual(s.buddy.moment?.count, 3)
    }

    func testAllErrorsUseGenericErrorAndClear() {
        for errorClass in [String?.none, "rate_limit"] {
            var s = start(fresh())
            s = reduce(s, .toolCalled(at: 1, sessionId: "a", source: "codex", tool: "Bash", hint: "swift build"))
            s = reduce(s, .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: errorClass)))
            XCTAssertEqual(s.buddy.creature.uhoh, .error)
            XCTAssertNil(s.buddy.creature.bubble) // Engine supplies the authored remark.
            XCTAssertEqual(start(s, 3).buddy.creature.state, .working)
            XCTAssertEqual(finish(s, 3).buddy.creature.state, .idle)
            XCTAssertNil(finish(s, 3).buddy.moment) // A failed turn cannot subsequently celebrate without new work.
            XCTAssertEqual(reduce(s, .errorDismissed(at: 3, sessionId: "a")).buddy.creature.state, .idle)
            XCTAssertEqual(reduce(s, .toolResulted(at: 3, sessionId: "a", source: "codex", tool: "Bash", ok: true, durationMs: 1)).buddy.creature.state, .working)
        }
    }

    func testGenericErrorBubbleAndReplacementExpiry() {
        var s = reduce(start(fresh()), .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: nil)))
        s = reduce(s, .voiceLine(at: 2, kind: .bubble, text: "something broke"))
        XCTAssertEqual(s.buddy.creature.bubble, "something broke")
        s = reduce(s, .turnEnded(at: 100, sessionId: "a", source: "codex", outcome: .failed(errorClass: "rate_limit")))
        s = reduce(s, .voiceLine(at: 100, kind: .bubble, text: "something failed"))
        s = reduce(s, .staleTick(at: 4002))
        XCTAssertEqual(s.buddy.creature.bubble, "something failed")
        s = reduce(s, .staleTick(at: 4100))
        XCTAssertNil(s.buddy.creature.bubble)
    }

    func testEffortUsesCurrentTaskDurationBoundariesAndResets() {
        var s = start(fresh())
        for (at, expected): (Double, CreatureEffort) in [
            (59_999, .light), (60_000, .light), (179_999, .light),
            (180_000, .hard), (299_999, .hard), (300_000, .grinding)
        ] {
            s = reduce(s, .staleTick(at: at))
            XCTAssertEqual(s.buddy.creature.effort, expected)
        }
        s = finish(s, 1_500_001)
        s = start(s, 1_510_000)
        XCTAssertEqual(s.buddy.creature.effort, .light)
    }

    func testPassiveAttentionDoesNotClassifyCommandStakes() {
        for hint in ["rm -rf build", "swift build", "read file"] {
            XCTAssertEqual(card(hint).buddy.creature.card?.stakes, .checkIt)
            XCTAssertEqual(card(hint).buddy.creature.card?.isApproval, false)
        }
    }

    func testCardQueueOldestFirst() {
        var s = card("first")
        s = reduce(s, .requestArrived(at: 10, sessionId: "b", requestId: "q", tool: "Read", hint: "second", sessionLabel: nil))
        XCTAssertEqual(s.buddy.creature.card?.id, "p")
        XCTAssertEqual(s.buddy.creature.card?.index, 0)
        XCTAssertEqual(s.buddy.creature.card?.count, 2)
        XCTAssertEqual(s.buddy.creature.card?.isApproval, false)
        s = reduce(s, .approvalResolved(at: 11, sessionId: "a", requestId: "p", decision: .deny))
        XCTAssertEqual(s.buddy.creature.card?.id, "q")
        XCTAssertEqual(s.buddy.creature.card?.count, 1)
    }

    func testFixedNudgeLadderForEveryStakesLevel() {
        for hint in ["rm -rf x", "swift build", "read file"] {
            var s = card(hint)
            for (at, rung): (Double, Int) in [(59_999, 0), (60_000, 1), (119_999, 1), (120_000, 2)] {
                s = reduce(s, .staleTick(at: at))
                XCTAssertEqual(s.buddy.creature.nudgeRung, rung)
            }
        }
    }

    func testDismissSnoozesOnlyCurrentRequest() {
        var s = reduce(card("rm -rf x"), .nudgeDismissed(at: 1))
        s = reduce(s, .staleTick(at: 200_000))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 0)
        XCTAssertEqual(s.nudges["p"]?.snoozed, true)
        s = reduce(s, .approvalArrived(at: 200_001, sessionId: "a", requestId: "q", tool: "Bash", hint: "rm -rf x", sessionLabel: nil, source: nil))
        s = reduce(s, .staleTick(at: 320_001))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 2)
        XCTAssertNil(s.nudges["p"])
    }

    func testQuietModePreservesVisualNudges() {
        for hint in ["rm -rf x", "build"] {
            var s = reduce(card(hint), .focusToggled(at: 1, on: true))
            s = reduce(s, .staleTick(at: 60_000))
            XCTAssertTrue(s.buddy.creature.focus)
            XCTAssertEqual(s.buddy.creature.nudgeRung, 1)
        }
    }

    func testDotsCappedAndThinkingIncluded() {
        var s = fresh()
        for i in 0..<8 { s = start(s, Double(i), "s\(i)") }
        s = reduce(s, .staleTick(at: 300_010))
        XCTAssertEqual(s.buddy.creature.dots, 5)
        XCTAssertNil(s.buddy.creature.dotAlert)
    }

    func testOverlaysOnlyOnIdleWorkingDone() {
        for s in [start(fresh()), finish(start(fresh()))] {
            XCTAssertEqual(reduce(s, .boopArrived(at: 200)).buddy.creature.overlay, .boop)
        }
        XCTAssertNil(reduce(fresh(), .boopArrived(at: 200)).buddy.creature.overlay, "sleep wins over affection")
        XCTAssertNil(reduce(card("x"), .boopArrived(at: 200)).buddy.creature.overlay)
        let failed = reduce(start(fresh()), .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: nil)))
        XCTAssertNil(reduce(failed, .boopArrived(at: 200)).buddy.creature.overlay)
    }

    func testGreetingLevelProjectionAndExpiry() {
        for (old, expected) in [(1, 1), (2, 3)] {
            // A greet shows once the owner is back and something is connected;
            // a sleeping buddy (no sessions) never overlays.
            var s = start(fresh())
            s.buddy.greetUntil = 1000
            s.buddy.greetLevel = old
            s = reduce(s, .staleTick(at: 1))
            XCTAssertEqual(s.buddy.creature.overlay, .greet)
            XCTAssertEqual(s.buddy.creature.greetLevel, expected)
            s = reduce(s, .staleTick(at: 1000))
            XCTAssertNil(s.buddy.creature.overlay)
            XCTAssertNil(s.buddy.creature.greetLevel)
        }
    }

    func testFailureUnderApprovalSurvivesResolutionAndDismissKeepsCard() {
        var s = reduce(card("build"), .turnEnded(at: 1, sessionId: "a", source: "codex", outcome: .failed(errorClass: nil)))
        XCTAssertEqual(s.buddy.creature.state, .needsYou)
        let dismissed = reduce(s, .errorDismissed(at: 2, sessionId: "a"))
        XCTAssertEqual(dismissed.buddy.creature.card?.id, "p")
        s = reduce(s, .approvalResolved(at: 2, sessionId: "a", requestId: "p", decision: .deny))
        XCTAssertEqual(s.buddy.creature.uhoh, .error)
        XCTAssertEqual(s.buddy.creature.dotAlert, 0)
    }

    func testLegacySignalsDelegateToTurnAndToolPaths() {
        var legacy = fresh()
        var modern = fresh()
        let events: [(BuddyEvent, BuddyEvent)] = [
            (.activitySignal(at: 0, sessionId: "a", source: "codex", signal: .startWorking, tool: nil, hint: nil), .turnStarted(at: 0, sessionId: "a", source: "codex")),
            (.activitySignal(at: 1, sessionId: "a", source: "codex", signal: .keepWorking, tool: "Bash", hint: "build"), .toolCalled(at: 1, sessionId: "a", source: "codex", tool: "Bash", hint: "build")),
            (.activitySignal(at: 2, sessionId: "a", source: "codex", signal: .error, tool: nil, hint: nil), .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: nil))),
            (.activitySignal(at: 3, sessionId: "a", source: "codex", signal: .stopWorking, tool: nil, hint: nil), .turnEnded(at: 3, sessionId: "a", source: "codex", outcome: .completed)),
        ]
        for (old, new) in events {
            legacy = reduce(legacy, old)
            modern = reduce(modern, new)
            // The shim is responsible for the creature and the session record,
            // not for every incidental field the two paths might populate.
            XCTAssertEqual(legacy.buddy.creature, modern.buddy.creature, old.name)
            XCTAssertEqual(legacy.sessions["a"]?.state, modern.sessions["a"]?.state, old.name)
            XCTAssertEqual(legacy.sessions["a"]?.uhoh, modern.sessions["a"]?.uhoh, old.name)
            XCTAssertEqual(legacy.sessions["a"]?.currentTool, modern.sessions["a"]?.currentTool, old.name)
        }
    }
}
