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
        c.uhoh = .stuck
        XCTAssertEqual(legacyPetState(from: c), .thinking)
        c.uhoh = .hungry
        XCTAssertEqual(legacyPetState(from: c), .error)
    }

    func testCollapseThreeSessionsAndDoneAboveWorking() {
        var s = start(start(start(fresh()), 1, "b"), 2, "c")
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
        XCTAssertEqual(s.buddy.creature.state, .done)
        s = reduce(s, .staleTick(at: 1600))
        XCTAssertEqual(s.buddy.creature.state, .working)
    }

    func testAllCheerThresholdBranches() {
        let cases: [(Int, Double, EffortTier, CheerSize)] = [
            (0, 1, .light, .hop), (3, 1, .light, .dance),
            (1, 1_200_000, .light, .dance), (0, 1, .grinding, .dance),
            (1, 1, .light, .cheer), (0, 300_000, .light, .cheer),
            (0, 1, .hard, .cheer), (0, 299_999, .light, .hop),
            (0, 1_200_000, .light, .cheer), (2, 1, .light, .cheer),
        ]
        for (errors, span, effort, expected) in cases {
            var s = start(fresh())
            s.sessions["a"]?.errorCount = errors
            s.sessions["a"]?.reportedEffort = effort
            s = finish(s, span)
            XCTAssertEqual(s.buddy.creature.cheer, expected)
            XCTAssertEqual(s.buddy.celebrateIntensity, expected.intensity)
            XCTAssertEqual(s.buddy.celebrateUntil, span + s.cheerThresholds.duration(expected))
        }
    }

    func testCheerThresholdInjection() {
        var s = start(fresh())
        s.cheerThresholds.cheerSpanMs = 10
        s.cheerThresholds.cheerMs = 20
        s = finish(s, 10)
        XCTAssertEqual(s.buddy.creature.cheer, .cheer)
        XCTAssertEqual(s.buddy.celebrateUntil, 30)
    }

    func testFoldKeepsLargerTimerAndUpgradesSmaller() {
        var s = start(start(fresh()), 0, "b")
        s.sessions["a"]?.reportedEffort = .grinding
        s = finish(s, 100)
        s = finish(s, 500, "b")
        XCTAssertEqual(s.buddy.creature.cheer, .dance)
        XCTAssertEqual(s.buddy.celebrateUntil, 4100)
        s = start(s, 600, "b")
        s = finish(s, 3501, "b")
        XCTAssertEqual(s.buddy.creature.cheer, .hop)
        XCTAssertEqual(s.buddy.celebrateUntil, 5001)
        s = start(s, 3600)
        s.sessions["a"]?.reportedEffort = .hard
        s = finish(s, 3700)
        XCTAssertEqual(s.buddy.creature.cheer, .cheer)
        XCTAssertEqual(s.buddy.celebrateUntil, 6200)
    }

    func testDoneGiftCollectAndUTF8Cap() {
        var s = start(fresh())
        s = reduce(s, .toolCalled(at: 1, sessionId: "a", source: "codex", tool: "Bash", hint: String(repeating: "한", count: 30)))
        s = finish(s)
        s = reduce(s, .staleTick(at: 1600))
        XCTAssertEqual(s.buddy.creature.state, .idle)
        XCTAssertTrue(s.buddy.creature.gift)
        XCTAssertEqual(s.buddy.creature.giftLine?.utf8.count, 39)
        let line = s.buddy.creature.giftLine
        s = reduce(s, .collectArrived(at: 1700))
        XCTAssertFalse(s.buddy.creature.gift)
        XCTAssertNil(s.buddy.creature.giftLine)
        XCTAssertEqual(s.buddy.creature.bubble, line)
        s = reduce(s, .staleTick(at: 5700))
        XCTAssertNil(s.buddy.creature.bubble)
    }

    func testBoopCollectsGift() {
        var s = finish(start(fresh()))
        s = reduce(s, .staleTick(at: 1600))
        s = reduce(s, .boopArrived(at: 1601))
        XCTAssertFalse(s.buddy.creature.gift)
        XCTAssertEqual(s.buddy.creature.bubble, "done: ")
        XCTAssertEqual(s.buddy.creature.overlay, .boop)
    }

    func testErrorHungryAndClearing() {
        for errorClass in [String?.none, "rate_limit"] {
            var s = start(fresh())
            s = reduce(s, .toolCalled(at: 1, sessionId: "a", source: "codex", tool: "Bash", hint: "swift build"))
            s = reduce(s, .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: errorClass)))
            XCTAssertEqual(s.buddy.creature.uhoh, errorClass == nil ? .error : .hungry)
            XCTAssertEqual(s.buddy.creature.bubble, errorClass == nil ? "build failed" : "hungry")
            XCTAssertEqual(start(s, 3).buddy.creature.state, .working)
            XCTAssertEqual(finish(s, 3).buddy.creature.state, .done)
            XCTAssertEqual(reduce(s, .errorDismissed(at: 3, sessionId: "a")).buddy.creature.state, .idle)
            XCTAssertEqual(reduce(s, .toolResulted(at: 3, sessionId: "a", source: "codex", tool: "Bash", ok: true, durationMs: 1)).buddy.creature.state, .working)
        }
    }

    func testGenericErrorBubbleAndReplacementExpiry() {
        var s = reduce(start(fresh()), .turnEnded(at: 2, sessionId: "a", source: "codex", outcome: .failed(errorClass: nil)))
        XCTAssertEqual(s.buddy.creature.bubble, "something broke")
        s = reduce(s, .turnEnded(at: 100, sessionId: "a", source: "codex", outcome: .failed(errorClass: "rate_limit")))
        s = reduce(s, .staleTick(at: 4002))
        XCTAssertEqual(s.buddy.creature.bubble, "hungry")
        s = reduce(s, .staleTick(at: 4100))
        XCTAssertNil(s.buddy.creature.bubble)
    }

    func testStuckBySilenceAndSuccessClears() {
        var s = reduce(start(fresh()), .staleTick(at: 300_001))
        XCTAssertEqual(s.buddy.creature.uhoh, .stuck)
        XCTAssertEqual(s.buddy.creature.bubble, "might be going in circles")
        s = reduce(s, .toolResulted(at: 300_002, sessionId: "a", source: "codex", tool: "Bash", ok: true, durationMs: nil))
        XCTAssertEqual(s.buddy.creature.state, .working)
    }

    func testSixIdenticalCallsAndReset() {
        var s = start(fresh())
        for i in 1...6 {
            s = reduce(s, .toolCalled(at: Double(i), sessionId: "a", source: "codex", tool: "Bash", hint: "test"))
            XCTAssertEqual(s.buddy.creature.state, i == 6 ? .uhoh : .working)
        }
        XCTAssertEqual(s.buddy.creature.uhoh, .stuck)
        s = start(s, 7)
        for i in 8...14 {
            s = reduce(s, .toolCalled(at: Double(i), sessionId: "a", source: "codex", tool: "Bash", hint: "test \(i)"))
        }
        XCTAssertEqual(s.buddy.creature.state, .working)
    }

    func testEffortReportedOverridesHeuristic() {
        var s = start(fresh())
        s.sessions["a"]?.errorCount = 3
        s = reduce(s, .effortReported(at: 10, sessionId: "a", level: .light))
        XCTAssertEqual(s.buddy.creature.effort, .light)
        s = reduce(s, .effortReported(at: 11, sessionId: "a", level: .hard))
        XCTAssertEqual(s.buddy.creature.effort, .hard)
        s = reduce(s, .effortReported(at: 12, sessionId: "a", level: .grinding))
        XCTAssertEqual(s.buddy.creature.effort, .grinding)
    }

    func testEveryStakesPatternAndReadOnlyTools() {
        for hint in ["rm -rf x", "rm -r x", "sudo test", "git push --force", "git push -f origin", "curl example | sh", "wget example |sh", "mkfs disk", "dd if=x", "chmod 777 x", "echo\nhi", "echo\u{1b}"] {
            XCTAssertEqual(card(hint).buddy.creature.card?.stakes, .careful, hint)
        }
        for tool in ["Read", "Glob", "Grep", "LS", "LSP", "read_file", "list_dir", "grep_search", "codebase_search"] {
            XCTAssertEqual(card("file\tname", tool: tool).buddy.creature.card?.stakes, .fine)
            XCTAssertEqual(card("rm -rf x", tool: tool).buddy.creature.card?.stakes, .careful)
        }
        XCTAssertEqual(card("swift build").buddy.creature.card?.stakes, .checkIt)
    }

    func testCardQueueOldestFirst() {
        var s = card("first")
        s = reduce(s, .requestArrived(at: 10, sessionId: "b", requestId: "q", tool: "Read", hint: "second", sessionLabel: nil))
        XCTAssertEqual(s.buddy.creature.card?.id, "p")
        XCTAssertEqual(s.buddy.creature.card?.index, 0)
        XCTAssertEqual(s.buddy.creature.card?.count, 2)
        XCTAssertEqual(s.buddy.creature.card?.isApproval, true)
        s = reduce(s, .approvalResolved(at: 11, sessionId: "a", requestId: "p", decision: .deny))
        XCTAssertEqual(s.buddy.creature.card?.id, "q")
        XCTAssertEqual(s.buddy.creature.card?.count, 1)
    }

    func testCarefulNudgeRungsAndCheckItCap() {
        for hint in ["rm -rf x", "swift build"] {
            var s = card(hint)
            XCTAssertEqual(s.buddy.creature.nudgeRung, 0)
            s = reduce(s, .staleTick(at: 180_000))
            XCTAssertEqual(s.buddy.creature.nudgeRung, 1)
            s = reduce(s, .staleTick(at: 480_000))
            XCTAssertEqual(s.buddy.creature.nudgeRung, hint == "rm -rf x" ? 2 : 1)
        }
    }

    func testDismissHalvesAndThreeDismissalsSnoozeToolForSession() {
        var s = card("rm -rf x")
        for i in 1...3 {
            s = reduce(s, .nudgeDismissed(at: Double(i)))
            XCTAssertEqual(s.nudges["p"]?.nextAt, Double(i) + 180_000 / pow(2, Double(i)))
        }
        XCTAssertEqual(s.buddy.creature.bubble, "okay, I'll hush about that")
        s = reduce(s, .staleTick(at: 1_000_000))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 0)
        s = reduce(s, .approvalArrived(at: 1_000_001, sessionId: "a", requestId: "q", tool: "Bash", hint: "sudo x", sessionLabel: nil, source: nil))
        s = reduce(s, .staleTick(at: 1_200_001))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 0)
        XCTAssertEqual(s.nudges["q"]?.snoozed, true)
    }

    func testFocusGatesOnlyNonCareful() {
        for hint in ["rm -rf x", "build"] {
            var s = reduce(card(hint), .focusToggled(at: 1, on: true))
            s = reduce(s, .staleTick(at: 180_000))
            XCTAssertTrue(s.buddy.creature.focus)
            XCTAssertEqual(s.buddy.creature.nudgeRung, hint == "build" ? 0 : 1)
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
}

extension CreatureReducerTests {
    func testNudgeRungTwoRateLimitSurvivesDismissal() {
        var s = reduce(card("sudo x"), .staleTick(at: 180_000))
        s = reduce(s, .staleTick(at: 480_000))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 2)
        s = reduce(s, .nudgeDismissed(at: 480_001))
        s = reduce(s, .staleTick(at: 570_001))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 1)
        s = reduce(s, .staleTick(at: 720_001))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 1)
        s = reduce(s, .staleTick(at: 1_080_000))
        XCTAssertEqual(s.buddy.creature.nudgeRung, 2)
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

    func testRepeatedCallsStayStuckUntilExplicitRecovery() {
        var s = start(fresh())
        for i in 1...6 { s = reduce(s, .toolCalled(at: Double(i), sessionId: "a", source: "codex", tool: "Bash", hint: "x")) }
        s = reduce(s, .toolCalled(at: 7, sessionId: "a", source: "codex", tool: "Read", hint: "y"))
        XCTAssertEqual(s.buddy.creature.uhoh, .stuck)
        let unknown = reduce(s, .toolResulted(at: 8, sessionId: "a", source: "codex", tool: "Read", ok: nil, durationMs: nil))
        XCTAssertEqual(unknown.buddy.creature.uhoh, .stuck)
        XCTAssertEqual(finish(s, 9).buddy.creature.state, .done)
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
            XCTAssertEqual(legacy, modern)
        }
    }
}
