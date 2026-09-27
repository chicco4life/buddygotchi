import BoopDevKit
import Foundation
import XCTest
@testable import BoopKit

/// Drives a core with a virtual clock. Starts 2026-10-14 14:00 UTC, a
/// Wednesday afternoon, with today already started.
final class CoreRig {
    static let start = Replay.defaultStart
    static let day: Int64 = 24 * 3600 * 1000
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    var now: Int64
    let core: Core
    var log: [CoreEffect] = []

    init(start: Int64 = CoreRig.start, newDay: Bool = false, seed: UInt64 = 1, rules: Personality.Rules = Personality.Rules()) {
        now = start
        let today = time.day(start)
        core = Core(config: .init(rules: rules, time: time, seed: seed), lastActiveDay: newDay ? nil : today)
        if !newDay { core.tick(at: start) }  // the first snapshot has gone out
    }

    @discardableResult
    func send(_ kind: BoopEvent.Kind, _ agent: Agent = .claudeCode, session: String = "s1", subagent: String? = nil,
              project: String = "landing", tool: String? = nil, topic: String? = nil, failed: Bool? = nil) -> [CoreEffect] {
        // A result (failed or not) is a finished call: its `PostToolUse`.
        var detail = BoopEvent.Detail(tool: tool, topic: topic, failed: failed)
        detail.done = kind == .activity && failed != nil
        let fx = core.handle(BoopEvent(agent: agent, session: session, subagent: subagent, project: project, event: kind,
                                       detail: detail, ts: now))
        log += fx
        return fx
    }

    @discardableResult
    func input(_ input: Core.DeviceInput) -> [CoreEffect] {
        let fx = core.input(input, at: now)
        log += fx
        return fx
    }

    /// Moves the clock, ticking once a second like the app does.
    @discardableResult
    func wait(_ ms: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        let end = now + ms
        while now < end {
            now = min(end, now + 1000)
            fx += core.tick(at: now)
        }
        log += fx
        return fx
    }

    /// A whole turn in one session: prompt, `ms` of work, finish.
    @discardableResult
    func turn(_ ms: Int64, session: String = "s1", agent: Agent = .claudeCode) -> [CoreEffect] {
        send(.turnStart, agent, session: session)
        wait(ms)
        return send(.turnEnd, agent, session: session)
    }

    var state: StateSnapshot { core.snapshot(at: now) }
    /// The popover's list, as `[agent, project, status]`.
    var sessions: [[String]] { core.sessionList(at: now).map { [$0.agent, $0.project, $0.status.rawValue] } }
}

func moments(_ fx: [CoreEffect]) -> [String] {
    fx.compactMap { if case .moment(let anim, _) = $0 { return anim } else { return nil } }
}

/// The events that wake the brain, by their lines.
func woke(_ fx: [CoreEffect]) -> [String] {
    events(fx).filter(\.wakesBrain).map(\.line)
}

/// A chatty Boop's rules, for tests that need chatter often.
extension Personality.Rules {
    static let chatty = Personality.Rules(chatterMs: 45_000...90_000, toolUses: .notable)
}

func mumbles(_ fx: [CoreEffect]) -> [String] {
    fx.compactMap { if case .mumble(let f, let w) = $0 { return w.map { "\(f) \($0)" } ?? f } else { return nil } }
}

func states(_ fx: [CoreEffect]) -> [StateSnapshot] {
    fx.compactMap { if case .state(let s) = $0 { return s } else { return nil } }
}

// MARK: - BEHAVIORS.md §3.1 Agent work

final class CoreAgentWorkTests: XCTestCase {
    func testSendingAPromptMakesBaseWorking() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(rig.state.base, "idle")
        let fx = rig.send(.turnStart)
        XCTAssertEqual(states(fx).last?.base, "working")
        XCTAssertEqual(states(fx).last?.busy, 1)
        XCTAssertEqual(woke(fx), [#"claude started turn 1 on "landing"."#])
        XCTAssertNil(events(fx).first?.reaction)
    }

    func testAFinishedTurnCheersWhateverItsLength() {  // BEHAVIORS.md §3.1
        for ms: Int64 in [29_000, 300_000, 1_199_000] {
            let rig = CoreRig()
            XCTAssertEqual(moments(rig.turn(ms)), ["cheer"], "\(ms) ms")
            XCTAssertEqual(rig.state.base, "idle")
        }
        let rig = CoreRig()
        let fx = rig.turn(1_200_000)
        XCTAssertEqual(moments(fx), ["cheer"], "one size")
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": done after 20 min, a very long turn, 0 tools."#])
        XCTAssertEqual(events(fx).first?.reaction, "Boop cheered on its own.")
        XCTAssertEqual(events(fx).first?.facts["length_ms"], .int(1_200_000))
    }

    /// BEHAVIORS.md §5: the cheer lasts at least 2 s: as many loops of the
    /// mood's task-complete design (`FaceLoops`) as that takes, and no more.
    func testTheCheerLoopsForLongEnough() {
        XCTAssertEqual(Core.cheerMinMs, 2000)
        for mood in MoodAction.moods.map(\.name) {
            let loop = FaceLoops.ms(mood: mood, state: "task_complete")
            let loops = Core.cheerLoops(mood: mood)
            XCTAssertGreaterThanOrEqual(Int64(loops) * loop, Core.cheerMinMs, mood)
            XCTAssertLessThan(Int64(loops - 1) * loop, Core.cheerMinMs, mood)
        }
        XCTAssertTrue(CoreRig().turn(10_000).contains(.moment(anim: "cheer", loops: Core.cheerLoops(mood: "happy"))))
    }

    func testAFinishCheersWhileOthersKeepWorking() {  // BEHAVIORS.md §3.1
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(10_000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "a")), ["cheer"])
        XCTAssertEqual(rig.state.base, "working")
    }

    /// BEHAVIORS.md §3.1: each finish cheers; the device replaces a cheer
    /// that's playing, so several at once look like one.
    func testSeveralFinishingAtOnceEachCheer() {
        let rig = CoreRig()
        for s in ["a", "b", "c"] { rig.send(.turnStart, session: s) }
        rig.wait(400_000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "a")), ["cheer"])
        rig.wait(1000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "b")), ["cheer"])
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "c")), ["cheer"])
        XCTAssertEqual(moments(rig.wait(10_000)), [], "nothing follows")
    }

    /// BEHAVIORS.md §3.1: a failed turn has no moment of its own; the
    /// session goes idle and the brain still hears about it.
    /// ADAPTERS.md §3: a turn you interrupt ends without `Stop`, so the
    /// interrupt (or Claude sitting at its prompt) ends it: idle at once, no
    /// cheer, and the brain hears of a stopped turn (harness/EVENTS.md §4).
    func testAnInterruptedTurnGoesIdleQuietly() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        let fx = rig.send(.turnStopped, tool: "Bash")
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(events(fx).map { $0.facts["outcome"] }, ["stopped"])
        XCTAssertEqual(mumbles(rig.wait(10 * 60_000)), [], "no working chatter")

        rig.send(.turnStart, session: "s2")
        rig.send(.needsYou, session: "s2", tool: "Bash")
        rig.send(.turnStopped, session: "s2", tool: "Bash")
        XCTAssertNil(rig.state.attn, "an interrupted call answers it, as any event does")
        XCTAssertEqual(rig.state.base, "idle")
    }

    /// ADAPTERS.md §4: Esc on Claude's permission prompt sends no hook, and
    /// Claude's idle notice about a minute later never comes while the main
    /// agent's prompt is up. So the notice answers a request from the main
    /// agent, or one from a Notification alone, and the session goes idle.
    /// A subagent's request stays: its prompt may still be up.
    func testClaudesIdleNoticeAnswersTheMainAgentsRequest() {
        for asker in ["main agent", "notification alone"] {
            let rig = CoreRig(rules: .chatty)
            rig.send(.turnStart)
            rig.send(.needsYou, tool: asker == "main agent" ? "Bash" : nil)
            rig.wait(61_000)
            XCTAssertNotNil(rig.state.attn, asker)
            let fx = rig.send(.turnStopped)
            XCTAssertNil(states(fx).last?.attn, asker)
            XCTAssertEqual(rig.state.base, "idle", asker)
            XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]], asker)
            XCTAssertEqual(moments(fx), [], asker)
            XCTAssertEqual(woke(fx), [], "\(asker): the stopped turn ended while something needed you")
            XCTAssertEqual(mumbles(rig.wait(10 * 60_000)), [], "\(asker): no working chatter")
        }
        for askers in [["a1"], ["", "a1"]] {
            let rig = CoreRig()
            rig.send(.turnStart)
            for a in askers { rig.send(.needsYou, subagent: a.isEmpty ? nil : a, tool: "Bash") }
            rig.wait(61_000)
            rig.send(.turnStopped)
            XCTAssertNotNil(rig.state.attn, "\(askers): a subagent's prompt may still be up")
            rig.send(.activity, subagent: "a1", tool: "Bash")
            XCTAssertNil(rig.state.attn, "\(askers): its own next event answers it")
        }
    }

    func testFailedTurnPlaysNoMomentAndGoesIdle() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.wait(60_000)
        let fx = rig.send(.turnFailed)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": failed after 1 min, a long turn, 0 tools."#])
        XCTAssertNil(events(fx).first?.reaction, "the rules did nothing")
        XCTAssertEqual(moments(rig.wait(5000)), [], "nothing follows")
    }

    /// BEHAVIORS.md §3.1: a turn whose last test, build or deploy command
    /// failed is a failed turn: no cheer, no moment, and the brain hears it
    /// as failed.
    func testATurnThatLeavesItsTestsFailingFails() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.send(.activity, tool: "Edit", topic: "docs", failed: false)  // not a check
        rig.send(.activity, tool: "Read", failed: false)
        rig.send(.activity, tool: "Bash", topic: "tests")  // no result: PreToolUse, or Codex
        rig.wait(60_000)
        let fx = rig.send(.turnEnd)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(woke(fx), [#"claude finished turn 1 on "landing": failed after 1 min, a long turn, 4 tools (1 failed). Tests failing, docs edited."#])
        XCTAssertEqual(moments(rig.wait(2000)), [])
    }

    func testATurnWhoseLastCheckPassedCheers() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "build", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false)
        rig.wait(60_000)
        XCTAssertEqual(moments(rig.send(.turnEnd)), ["cheer"])
        // The next turn starts clean: a failure in the last one doesn't count.
        rig.wait(5000)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "deploy", failed: true)
        rig.send(.turnEnd)
        rig.wait(5000)
        rig.send(.turnStart)
        rig.wait(1000)
        XCTAssertEqual(moments(rig.send(.turnEnd)), ["cheer"])
    }

    func testTheErrorClassReachesTheEvent() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.send(.activity, tool: "Read")
        rig.wait(3000)
        let fx = rig.core.handle(BoopEvent(agent: .claudeCode, session: "s1", project: "landing", event: .turnFailed,
                                           detail: .init(error: "rate_limit"), ts: rig.now))
        let failed = events(fx).first
        XCTAssertEqual(failed?.line, #"claude finished turn 1 on "landing": failed (rate limit) after 3 s, a short turn, 0 tools."#)
        XCTAssertEqual(failed?.facts["outcome"], "failed")
        XCTAssertEqual(failed?.facts["error"], "rate_limit")
    }
}

// MARK: - BEHAVIORS.md §3.2 Something needs you

final class CoreNeedsYouTests: XCTestCase {
    func testClaudeNeedsYouShowsImmediately() {
        let rig = CoreRig()
        rig.send(.turnStart, project: "jetpack")
        let fx = rig.send(.needsYou, project: "jetpack", tool: "Bash")
        let attn = states(fx).last?.attn
        XCTAssertEqual(attn, StateSnapshot.Attention(agent: "claude", project: "jetpack", more: 0))
        XCTAssertEqual(states(fx).last?.waiting, 1)
        XCTAssertEqual(rig.sessions, [["claude", "jetpack", "waiting"]])
        XCTAssertEqual(woke(fx), [], "needs you never wakes the brain")
        XCTAssertEqual(events(fx).map(\.line), [#"claude needs you on "jetpack"."#], "the brain hears of it")
    }

    func testCodexWaitsTwoSeconds() {
        let rig = CoreRig()
        rig.send(.turnStart, .codex)
        XCTAssertEqual(states(rig.send(.needsYou, .codex, tool: "shell")), [])
        XCTAssertNil(rig.state.attn)
        rig.wait(1000)
        XCTAssertNil(rig.state.attn)
        let fx = rig.wait(1000)
        XCTAssertEqual(states(fx).last?.attn?.agent, "codex")
    }

    func testCodexRequestHandledByItsReviewerNeverShows() {
        let rig = CoreRig()
        rig.send(.turnStart, .codex)
        rig.send(.needsYou, .codex, tool: "shell")
        rig.wait(1500)
        rig.send(.activity, .codex, tool: "shell")
        rig.wait(10_000)
        XCTAssertNil(rig.state.attn)
        XCTAssertTrue(rig.log.allSatisfy { if case .state(let s) = $0 { return s.attn == nil } else { return true } })
    }

    func testAnyLaterEventClearsIt() {
        for clearing in [BoopEvent.Kind.activity, .turnStart, .turnEnd, .turnFailed, .sessionEnd, .sessionStart] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.needsYou, tool: "Bash")
            rig.wait(4000)
            let fx = rig.send(clearing)
            XCTAssertNil(states(fx).last?.attn, clearing.rawValue)
            XCTAssertNotNil(states(fx).last, clearing.rawValue)
        }
    }

    func testApprovingGoesBackToWork() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        XCTAssertEqual(rig.state.base, "idle")
        let fx = rig.send(.activity, tool: "Bash")
        XCTAssertEqual(states(fx).last?.base, "working")
        XCTAssertEqual(moments(fx), [], "the device just blends back to its look")
    }

    /// ADAPTERS.md §4: Claude has no hook for the moment you approve, so a
    /// request clears only when the approved tool finishes. A long command
    /// keeps "needs you" up until then, and one that runs past the safety
    /// net leaves the session idle until it finishes.
    func testAnApprovedLongCommandKeepsNeedsYouUntilItFinishes() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")  // PreToolUse comes before the permission check
        rig.send(.needsYou, tool: "Bash")
        rig.send(.needsYou)  // its Notification
        rig.wait(120_000)  // approved at once; the tests take two minutes
        XCTAssertNotNil(rig.state.attn, "nothing says you approved")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", topic: "tests", failed: false)).last?.base, "working")
        XCTAssertNil(rig.state.attn)

        rig.send(.activity, tool: "Bash", topic: "build")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(Core.Config().safetyNetMs)
        XCTAssertNil(rig.state.attn, "the safety net")
        XCTAssertEqual(rig.state.base, "idle", "though the approved build still runs")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", topic: "build", failed: false)).last?.base, "working")
    }

    func testDuplicateWhileWaitingIsIgnored() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(3000)
        let fx = rig.send(.needsYou)  // the matching Notification
        XCTAssertEqual(states(fx), [])
        XCTAssertEqual(rig.state.attn?.more, 0)
    }

    func testALateNotificationAfterAQuickApprovalIsIgnored() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.send(.activity, tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou)  // Notification, no tool
        XCTAssertNil(rig.state.attn)
        rig.wait(10_000)
        rig.send(.needsYou, tool: "Bash")  // a real new request
        XCTAssertNotNil(rig.state.attn)
    }

    /// ADAPTERS.md §4: Claude gives a subagent's hooks its parent's session.
    /// A sibling's tool calls don't answer another agent's request; only the
    /// asker's own next event, or a turn-level one, does.
    func testASiblingSubagentsToolsDontAnswerTheRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn)
        rig.wait(500)
        rig.send(.activity, subagent: "a2", tool: "Read")
        rig.send(.activity, tool: "Agent")  // the main agent: another subagent came back
        XCTAssertNotNil(rig.state.attn, "a sibling kept working")
        rig.wait(5500)
        XCTAssertEqual(states(rig.send(.needsYou)), [], "its Notification is the same request")
        rig.wait(60_000)
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNotNil(rig.state.attn)
        let fx = rig.send(.activity, subagent: "a1", tool: "Bash")  // approved
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "working")
    }

    /// Two subagents asking at once: "needs you" stays until both are
    /// answered, and a turn-level event answers everyone.
    func testEveryAskerMustBeAnswered() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a2", tool: "Edit")
        XCTAssertEqual(rig.state.attn?.more, 0, "one session")
        rig.send(.activity, subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn, "a2 still waits")
        rig.send(.activity, subagent: "a2", tool: "Edit")
        XCTAssertNil(rig.state.attn)
        for turnLevel in [BoopEvent.Kind.turnEnd, .turnFailed, .sessionEnd] {
            rig.send(.turnStart)
            rig.send(.needsYou, subagent: "a1", tool: "Bash")
            rig.send(.activity, subagent: "a2", tool: "Read")
            XCTAssertNotNil(rig.state.attn, turnLevel.rawValue)
            rig.send(turnLevel)
            XCTAssertNil(rig.state.attn, turnLevel.rawValue)
        }
    }

    /// A request that came as a Notification alone doesn't say who asked, so
    /// any event from the session answers it, as before subagents.
    func testANotificationAloneIsAnsweredByAnyEvent() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou)
        XCTAssertNotNil(rig.state.attn)
        rig.send(.activity, subagent: "a2", tool: "Read")
        XCTAssertNil(rig.state.attn)
    }

    /// ADAPTERS.md §4: a subagent you deny carries on, and one that then
    /// ends without another tool call sends only `SubagentStop`. Its end
    /// answers its own request and nobody else's, and the main agent's turn
    /// goes on working. The brain doesn't hear of it.
    func testASubagentsEndAnswersOnlyItsOwnRequest() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent")
        rig.send(.activity, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.needsYou, subagent: "a2", tool: "Edit")
        rig.wait(20_000)  // both denied: no hook says so
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a3")), [], "a sibling's end")
        XCTAssertEqual(states(rig.send(.subagentEnd)), [], "an end that names no subagent")
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a1")), [])
        XCTAssertNotNil(rig.state.attn, "a2 still waits")
        let fx = rig.send(.subagentEnd, subagent: "a2")
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "working", "the main agent's turn goes on")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "working"]])
        XCTAssertEqual(moments(fx), [])
        XCTAssertTrue(events(fx).isEmpty, "nothing for the brain")
        rig.send(.activity, tool: "Agent", failed: false)
        XCTAssertEqual(moments(rig.send(.turnEnd)), ["cheer"])
    }

    /// It answers nobody else: not the main agent, and not a request that
    /// came as a Notification alone, which doesn't say who asked.
    func testASubagentsEndLeavesOtherAskersWaiting() {
        for asker in ["main agent", "notification alone"] {
            let rig = CoreRig()
            rig.send(.turnStart)
            rig.send(.needsYou, tool: asker == "main agent" ? "Bash" : nil)
            rig.send(.needsYou, subagent: "a1", tool: "Bash")
            rig.send(.subagentEnd, subagent: "a1")
            XCTAssertNotNil(rig.state.attn, asker)
            rig.send(.activity, tool: "Bash")
            XCTAssertNil(rig.state.attn, asker)
        }
    }

    /// ADAPTERS.md §4: a subagent's end isn't activity. One that comes
    /// after its session's turn has ended (a background subagent finishing
    /// late) leaves the session idle, one from a session Boop hasn't seen
    /// creates it idle, and a turn gone stale stays stale. A request that
    /// came while no turn was going leaves the session idle when it clears.
    func testASubagentsEndNeverMakesASessionWork() {
        let rig = CoreRig(rules: .chatty)
        rig.turn(5000)
        XCTAssertEqual(states(rig.send(.subagentEnd, subagent: "a1")), [])
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(mumbles(rig.wait(10 * 60_000)), [], "no working chatter")

        rig.send(.subagentEnd, session: "s2", subagent: "a1")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"], ["claude", "landing", "idle"]])

        rig.send(.turnStart, session: "s3")
        rig.wait(Core.Config().staleWorkMs)
        XCTAssertEqual(rig.state.base, "idle", "an hour without events")
        XCTAssertEqual(states(rig.send(.subagentEnd, session: "s3", subagent: "a1")), [])
        XCTAssertEqual(rig.state.base, "idle", "still stale")

        rig.send(.needsYou, session: "s4", subagent: "a1", tool: "Bash")
        XCTAssertNotNil(rig.state.attn)
        let fx = rig.send(.subagentEnd, session: "s4", subagent: "a1")
        XCTAssertNil(states(fx).last?.attn)
        XCTAssertEqual(states(fx).last?.base, "idle", "no turn was going")
    }

    func testMoreThanOneShowsTheOldestWithACount() {
        let rig = CoreRig()
        rig.send(.needsYou, .claudeCode, session: "a", project: "jetpack", tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou, .claudeCode, session: "b", project: "landing", tool: "Edit")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "jetpack", more: 1))
        rig.send(.activity, session: "a")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "landing", more: 0))
    }

    /// ADAPTERS.md §4: after 10 minutes with no events "needs you" clears,
    /// and the session goes idle rather than back to working: no sweat drop
    /// and no chatter while the agent may still be waiting on its prompt.
    func testSafetyNetClearsAfterTenQuietMinutes() {
        XCTAssertEqual(Core.Config().safetyNetMs, 600_000)
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(599_000)
        XCTAssertNotNil(rig.state.attn)
        rig.wait(1000)
        XCTAssertNil(rig.state.attn)
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(rig.sessions, [["claude", "landing", "idle"]])
        XCTAssertEqual(mumbles(rig.wait(600_000)), [], "no working chatter")
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash")).last?.base, "working", "until the agent acts again")
    }

    /// ADAPTERS.md §4: the safety net also covers a Codex request no tick
    /// saw through its 2 s grace, as when the Mac sleeps right after Codex
    /// asks: the session goes idle rather than staying at work.
    func testSafetyNetCoversACodexRequestStillInItsGrace() {
        let rig = CoreRig(rules: .chatty)
        rig.send(.turnStart, .codex)
        rig.send(.activity, .codex, tool: "shell", topic: "deploy")
        rig.send(.needsYou, .codex, tool: "shell")
        rig.now += Core.Config().safetyNetMs  // one tick, on waking
        let fx = rig.core.tick(at: rig.now)
        XCTAssertEqual(states(fx).last?.base, "idle")
        XCTAssertNil(rig.state.attn)
        XCTAssertEqual(events(fx), [], "it never showed")
        XCTAssertEqual(rig.sessions, [["codex", "landing", "idle"]])
        XCTAssertEqual(mumbles(rig.wait(600_000)), [], "no working chatter")
    }

    func testWhileSomethingNeedsYouNothingWakesTheBrain() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(5000)
        rig.send(.needsYou, session: "a", tool: "Bash")
        rig.wait(60_000)
        let ended = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(woke(ended), [])
        XCTAssertEqual(events(ended).count, 1, "it still comes, for HISTORY")
    }
}

// MARK: - BEHAVIORS.md §3.3 You and Boop

final class CoreYouAndBoopTests: XCTestCase {
    /// harness/EVENTS.md §4: a tap is the rules' alone; the brain only
    /// hears of it. While something needs you, the device only squashes,
    /// and the event doesn't claim a reaction.
    func testATapIsTheRulesAlone() {
        let rig = CoreRig()
        let fx = rig.input(.tap)
        XCTAssertEqual(woke(fx), [])
        XCTAssertEqual(events(fx).map(\.line), ["You tapped Boop."])
        XCTAssertEqual(events(fx).first?.reaction, "Boop wiggled on its own.")
        XCTAssertEqual(moments(fx), [], "the device already wiggled")
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        let needed = rig.input(.tap)
        XCTAssertEqual(events(needed).map(\.line), ["You tapped Boop."])
        XCTAssertNil(events(needed).first?.reaction)
        XCTAssertEqual(moments(needed), [])
    }

    /// BEHAVIORS.md §3.3: the fourth tap within 3 s is a poke streak, which
    /// wakes the brain in place of a tap. The rules add no moment: the device
    /// has already wiggled.
    func testFourPokesWithinThreeSecondsReachTheBrain() {
        let rig = CoreRig()
        for _ in 0..<3 {
            let fx = rig.input(.tap)
            XCTAssertEqual(woke(fx), [])
            rig.wait(900)
        }
        let fx = rig.input(.tap)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(woke(fx), ["You poked Boop 4 times in 3 s."])
        XCTAssertEqual(events(fx).first?.reaction, "Boop wiggled on its own.")
    }

    /// At most once a minute: a streak sooner doesn't wake the brain
    /// (BEHAVIORS.md §3.3).
    func testAPokeStreakReachesTheBrainAtMostOnceAMinute() {
        let rig = CoreRig()
        var pokes: [String] = []
        func streak() -> [CoreEffect] {
            var fx: [CoreEffect] = []
            for _ in 0..<4 { fx += rig.input(.tap); fx += rig.wait(500) }
            pokes += woke(fx)
            return fx
        }
        _ = streak()
        let soon = streak()
        XCTAssertEqual(moments(soon), [])
        XCTAssertEqual(events(soon).last?.kind, .pokes)
        rig.wait(60_000)
        _ = streak()
        XCTAssertEqual(pokes.count, 2)
    }

    func testSlowPokesNeverAnnoyIt() {
        let rig = CoreRig()
        var fx: [CoreEffect] = []
        for _ in 0..<6 { fx += rig.input(.tap); fx += rig.wait(3000) }
        XCTAssertEqual(woke(fx), [])
        XCTAssertEqual(moments(fx), [])
    }

    /// While something needs you a tap means "I saw it", so it isn't
    /// counted.
    func testPokesWhileSomethingNeedsYouDontCount() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        var fx: [CoreEffect] = []
        for _ in 0..<5 { fx += rig.input(.tap); fx += rig.wait(300) }
        XCTAssertEqual(moments(fx), [])
        XCTAssertFalse(events(fx).contains { $0.kind == .pokes })
        rig.send(.activity, tool: "Bash")  // answered on the Mac
        fx = []
        for _ in 0..<4 { fx += rig.input(.tap); fx += rig.wait(200) }
        XCTAssertEqual(events(fx).filter { $0.kind == .pokes }.count, 1, "the taps before didn't count")
    }

    /// The first activity of the day starts short-term memory with no
    /// moment: the morning stretch and yawn were removed.
    func testFirstActivityOfTheDayStartsTheDayQuietly() {
        let rig = CoreRig(newDay: true)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-14")))
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(moments(rig.wait(2000)), [])
        XCTAssertFalse(rig.send(.turnStart).contains { if case .newDay = $0 { true } else { false } }, "only the first activity")
    }

    /// ARCHITECTURE.md §3.2: timers run on the steady time the core is
    /// given, and days and times of day on the wall clock the app reports.
    /// Setting the Mac's clock back an hour doesn't stretch working
    /// chatter's wait; moving it past midnight starts a new day.
    func testTimersFollowTheSteadyClockAndDaysTheWallClock() {
        let rig = CoreRig(seed: 7, rules: .chatty)
        rig.send(.turnStart)
        rig.wait(1000)
        rig.core.setWallClock(rig.now - 3_600_000, at: rig.now)  // the Mac's clock set back an hour
        XCTAssertFalse(mumbles(rig.wait(120_000)).isEmpty, "chatter, on time")
        rig.core.setWallClock(rig.now + CoreRig.day, at: rig.now)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-15")))
    }

    /// The runtime's steady clock starts at the wall clock's time and never
    /// goes back.
    func testTheSteadyClockStartsAtTheWallClockAndNeverStepsBack() {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let clock = Runtime.steadyClock()
        var last = clock()
        XCTAssertLessThan(abs(last - wall), 100)
        for _ in 0..<1000 {
            let now = clock()
            XCTAssertGreaterThanOrEqual(now, last)
            last = now
        }
    }

    /// A new day starts short-term memory fresh; nothing about it reaches
    /// the brain (the reflection was removed on 2026-09-26).
    func testANewDayOnlyStartsShortTermFresh() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.wait(24 * 3600 * 1000)
        let fx = rig.send(.turnStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-15")))
        XCTAssertEqual(events(fx).map(\.kind), [.turnStart])
    }
}

// MARK: - BEHAVIORS.md §6 Personalities

final class CorePersonalityTests: XCTestCase {
    /// The gaps between chatter mumbles over two working hours.
    func chatterGaps(_ rig: CoreRig) -> [Int64] {
        rig.send(.turnStart)
        var times: [Int64] = []
        for _ in 0..<7200 {
            if !mumbles(rig.wait(1000)).isEmpty { times.append(rig.now) }
            rig.send(.activity)  // keep it working
        }
        return zip(times, times.dropFirst()).map { $1 - $0 }
    }

    /// BEHAVIORS.md §2 and §6: chatter keeps the personality's pace, or
    /// never comes.
    func testChatterKeepsThePersonalitysPace() {
        let fast = chatterGaps(CoreRig(seed: 7, rules: Personality.Rules(chatterMs: 30_000...60_000)))
        XCTAssertGreaterThan(fast.count, 100)
        for gap in fast { XCTAssertTrue((30_000...61_000).contains(gap), "\(gap)") }
        let usual = chatterGaps(CoreRig(seed: 7))
        XCTAssertGreaterThan(usual.count, 25)
        for gap in usual { XCTAssertTrue((120_000...241_000).contains(gap), "\(gap)") }
        XCTAssertEqual(chatterGaps(CoreRig(seed: 7, rules: Personality.Rules(chatterMs: nil))), [])
    }

    /// A new personality applies from the next event, with no restart.
    func testANewPersonalityAppliesAtOnce() {
        let rig = CoreRig(rules: Personality.Rules(chatterMs: nil))
        rig.send(.turnStart)
        XCTAssertEqual(mumbles(rig.wait(300_000)), [], "no chatter")
        rig.core.setRules(Personality.Rules(chatterMs: 30_000...60_000))
        XCTAssertFalse(mumbles(rig.wait(61_000)).isEmpty, "chatters within 60 s")
    }

    /// DECISIONS.md §2.2: a personality file's front matter, and its
    /// defaults for anything missing or unreadable.
    func testFrontMatter() {
        let chatter = Personality.Rules(frontMatter: "chatter: 30-60\ntool_uses: all")
        XCTAssertEqual(chatter, Personality.Rules(chatterMs: 30_000...60_000, toolUses: .all))
        XCTAssertEqual(Personality.Rules(frontMatter: "chatter: none").chatterMs, nil)
        XCTAssertEqual(Personality.Rules(frontMatter: "chatter: 60-30\ntool_uses: loud"), Personality.Rules())
        XCTAssertEqual(Personality.Rules(frontMatter: "cheer: long\nchatter: 30-60"), Personality.Rules(chatterMs: 30_000...60_000),
                       "an older file's cheer is ignored: every finish cheers")
    }
}

// MARK: - Chatter, screen and inputs

final class CoreRulesTests: XCTestCase {
    /// BEHAVIORS.md §2: asleep only with no sessions, whatever the time.
    func testAsleepOnlyWithNoSessionsEvenLateAtNight() {
        let rig = CoreRig(start: CoreRig.start + 9 * 3600 * 1000)  // 23:00
        XCTAssertEqual(rig.state.base, "asleep")
        rig.send(.sessionStart)
        XCTAssertEqual(rig.state.base, "idle")
        rig.send(.turnStart)
        XCTAssertEqual(rig.state.base, "working")
    }

    func testNoSessionsIsAsleep() {
        XCTAssertEqual(CoreRig().state.base, "asleep")
    }

    /// BEHAVIORS.md §2 and §6: every 2–4 minutes while agents work, day or
    /// night; about half the time a `curious` question about the topic,
    /// otherwise a `happy` mumble with no word.
    func testWorkingChatterEveryTwoToFourMinutesWithTheTopicAboutHalfTheTime() {
        for start in [CoreRig.start, CoreRig.start + 9 * 3600 * 1000 + 1_800_000] {  // 14:00 and 23:30
            let rig = CoreRig(start: start, seed: 7)
            rig.send(.turnStart)
            rig.send(.activity, tool: "Bash", topic: "tests")
            var times: [Int64] = []
            var said: [String] = []
            for _ in 0..<3600 {
                let fx = rig.wait(1000)
                rig.send(.activity)  // keep it working
                for m in mumbles(fx) {
                    times.append(rig.now)
                    said.append(m)
                }
            }
            XCTAssertGreaterThan(times.count, 12)
            for (a, b) in zip(times, times.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b - a, 120_000)
                XCTAssertLessThanOrEqual(b - a, 241_000)
            }
            XCTAssertEqual(Set(said), ["curious tests", "happy"])
            let words = said.filter { $0 == "curious tests" }.count
            XCTAssertGreaterThan(words, times.count / 5)
            XCTAssertLessThan(words, times.count * 4 / 5)
        }
    }

    func testNoChatterWhenIdle() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(mumbles(rig.wait(600_000)), [])
    }

    /// PROTOCOL.md §3: the `state` message carries only the busy count and
    /// the oldest session that needs you; the list is the popover's.
    func testSnapshotShapeAndSessionList() {
        let rig = CoreRig()
        rig.send(.sessionStart, .claudeCode, session: "a", project: "notes")
        rig.send(.turnStart, .codex, session: "b", project: "buddygotchi")
        rig.send(.turnStart, .claudeCode, session: "c", project: "jetpack")
        rig.send(.needsYou, .claudeCode, session: "d", project: "landing", tool: "Bash")
        let s = rig.state
        XCTAssertEqual(rig.sessions, [["claude", "landing", "waiting"], ["codex", "buddygotchi", "working"],
                                      ["claude", "jetpack", "working"], ["claude", "notes", "idle"]])
        XCTAssertEqual([s.busy, s.waiting], [2, 1])
        XCTAssertEqual(s.jsonLine, #"{"t":"state","v":1,"base":"working","mood":"happy","attn":{"agent":"claude","project":"landing","more":0},"busy":2,"vol":6}"#)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(s.jsonLine.utf8)))
    }

    /// PROTOCOL.md §3 carries no idle count, so a second idle session
    /// leaves the snapshot as it was; the core still says the list changed,
    /// for the popover and debug.jsonl's `status`, and only then.
    func testASessionListChangeTheSnapshotDoesntShow() {
        let rig = CoreRig()
        XCTAssertEqual(states(rig.send(.sessionStart, session: "a", project: "notes")).map(\.base), ["idle"])
        let fx = rig.send(.sessionStart, session: "b", project: "jetpack")
        XCTAssertEqual(fx, [.sessions], "the same snapshot, and a new list")
        XCTAssertEqual(rig.send(.sessionEnd, session: "b", project: "jetpack"), [.sessions])
        XCTAssertEqual(rig.wait(5000), [], "nothing changed")
        XCTAssertEqual(rig.state.waiting, 0)
    }

    /// PROTOCOL.md §3: every `state` carries Boop's mood, happy until the
    /// mood action says otherwise, and a new mood goes out at once.
    func testANewMoodGoesOutInTheNextState() {
        let rig = CoreRig()
        XCTAssertEqual(rig.state.mood, "happy")
        let fx = rig.core.setMood("determined", at: rig.now)
        guard case .state(let s)? = fx.first, fx.count == 1 else {
            XCTFail("\(fx)")
            return
        }
        XCTAssertEqual(s.mood, "determined")
        XCTAssertEqual(rig.state.mood, "determined", "and every state after it")
    }

    func testNamesAreClippedToTheDevicesFields() {
        let rig = CoreRig()
        rig.send(.needsYou, session: "s", project: "a-really-long-project-name-number-1", tool: "Bash")
        // A cut project name ends in "..", within the 23 bytes (PROTOCOL.md §3).
        XCTAssertEqual(rig.state.attn?.project, "a-really-long-project..")
        XCTAssertEqual(rig.sessions.first?[1], "a-really-long-project-name-number-1", "the popover shows it whole")
        XCTAssertLessThanOrEqual(rig.state.jsonLine.utf8.count, StateSnapshot.maxLine)
        XCTAssertEqual(StateSnapshot.clip("ünïcödé-ünïcödé-ünïcödé"), "ünïcödé-ünïcödé")
        XCTAssertEqual(StateSnapshot.clip("ünïcödé-ünïcödé-ünïcödé", marked: true), "ünïcödé-ünïcöd..")
        XCTAssertEqual(StateSnapshot.clip("a-23-byte-project-name!", marked: true), "a-23-byte-project-name!", "one that fits isn't marked")
        // Finder names folders decomposed (e and U+0301), which the device
        // draws as "e?": the Mac sends names precomposed, before measuring
        // them (PROTOCOL.md §3). Swift's == can't tell the two apart.
        let finder = CoreRig()
        finder.send(.needsYou, project: "cafe\u{301}", tool: "Bash")
        XCTAssertEqual(finder.state.attn.map { Array($0.project.utf8) }, [0x63, 0x61, 0x66, 0xC3, 0xA9])
        XCTAssertEqual(finder.sessions.first?[1], "cafe\u{301}", "the popover shows it as it came")
        let resume = "re\u{301}sume\u{301}-re\u{301}sume\u{301}-re\u{301}sume\u{301}"
        XCTAssertEqual(Array(StateSnapshot.clip(resume, marked: true).utf8), Array("r\u{E9}sum\u{E9}-r\u{E9}sum\u{E9}-r\u{E9}..".utf8), "23 bytes")
    }

    func testSnapshotsGoOutOnlyWhenSomethingChanged() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(states(rig.wait(5000)), [])
        XCTAssertEqual(states(rig.send(.activity)).count, 1)
        XCTAssertEqual(states(rig.send(.activity)).count, 0)
    }

    func testStaleWorkGoesIdleAndOldSessionsAreForgotten() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(3_600_000)
        XCTAssertEqual(rig.state.base, "idle")
        rig.wait(24 * 3_600_000)
        XCTAssertEqual(rig.sessions, [])
    }

    func testSessionEndRemovesIt() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.send(.sessionEnd)
        XCTAssertEqual(rig.sessions, [])
        XCTAssertEqual(rig.state.base, "asleep")
    }
}
