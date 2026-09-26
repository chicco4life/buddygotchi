import Foundation
import XCTest
@testable import BoopKit

/// Drives a core with a virtual clock. Starts 2026-10-14 14:00 UTC, a
/// Wednesday afternoon, with today already started.
final class CoreRig {
    static let start: Int64 = 1_791_986_400_000
    static let day: Int64 = 24 * 3600 * 1000
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    var now: Int64
    let core: Core
    var log: [CoreEffect] = []

    init(start: Int64 = CoreRig.start, newDay: Bool = false, seed: UInt64 = 1) {
        now = start
        let today = time.day(start)
        core = Core(config: .init(name: "Pip", time: time, seed: seed), lastActiveDay: newDay ? nil : today)
        if !newDay { core.tick(at: start) }  // the first snapshot has gone out
    }

    @discardableResult
    func send(_ kind: BoopEvent.Kind, _ agent: Agent = .claudeCode, session: String = "s1", project: String = "landing",
              tool: String? = nil, topic: String? = nil, failed: Bool? = nil) -> [CoreEffect] {
        let fx = core.handle(BoopEvent(agent: agent, session: session, project: project, event: kind,
                                       detail: .init(tool: tool, topic: topic, failed: failed), ts: now))
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
    fx.compactMap { if case .moment(let anim) = $0 { return anim } else { return nil } }
}

func inputs(_ fx: [CoreEffect]) -> [Input] {
    fx.compactMap { if case .input(let i) = $0 { return i } else { return nil } }
}

func asides(_ fx: [CoreEffect]) -> [String] {
    fx.compactMap { if case .aside(let line) = $0 { return line } else { return nil } }
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
        XCTAssertEqual(inputs(fx).map(\.kind), [.agentStarted])
        XCTAssertEqual(inputs(fx).first?.line, "agent started · claude · landing · 14:00 Wednesday")
        XCTAssertNil(inputs(fx).first?.rules)
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
        XCTAssertTrue(fx.contains(.happened("14:20 claude · landing · finished (20 min)")))
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · done · claude · landing · took 20 min · 14:20 Wednesday")
        XCTAssertEqual(inputs(fx).first?.rules, "cheer")
        XCTAssertEqual(inputs(fx).first?.tookMs, 1_200_000)
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
    func testFailedTurnPlaysNoMomentAndGoesIdle() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.wait(60_000)
        let fx = rig.send(.turnFailed)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertTrue(fx.contains(.happened("14:01 claude · landing · tests · failed")))
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · failed · claude · landing · topic: tests · 14:01 Wednesday")
        XCTAssertNil(inputs(fx).first?.rules, "the rules did nothing")
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
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · failed · claude · landing · topic: tests · 14:01 Wednesday")
        XCTAssertTrue(fx.contains(.happened("14:01 claude · landing · tests · failed")))
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

    func testTopicAndErrorReachTheInput() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.send(.activity, tool: "Read")
        rig.wait(3000)
        let fx = rig.core.handle(BoopEvent(agent: .claudeCode, session: "s1", project: "landing", event: .turnFailed,
                                           detail: .init(error: "rate_limit"), ts: rig.now))
        let failed = inputs(fx).first
        XCTAssertEqual(failed?.line, "agent finished · failed · claude · landing · topic: tests · error: rate limit · 14:00 Wednesday")
        XCTAssertEqual(failed?.outcome, .failed)
        XCTAssertEqual(failed?.topic, "tests")
        XCTAssertEqual(failed?.error, "rate_limit")
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
        XCTAssertEqual(states(fx).last?.wait, 1)
        XCTAssertEqual(rig.sessions, [["claude", "jetpack", "waiting"]])
        XCTAssertEqual(inputs(fx), [], "needs you is never an input")
        XCTAssertEqual(asides(fx), ["claude needs you · jetpack · 14:00 Wednesday"], "the transcript hears of it")
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

    func testMoreThanOneShowsTheOldestWithACount() {
        let rig = CoreRig()
        rig.send(.needsYou, .claudeCode, session: "a", project: "jetpack", tool: "Bash")
        rig.wait(1000)
        rig.send(.needsYou, .claudeCode, session: "b", project: "landing", tool: "Edit")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "jetpack", more: 1))
        rig.send(.activity, session: "a")
        XCTAssertEqual(rig.state.attn, StateSnapshot.Attention(agent: "claude", project: "landing", more: 0))
    }

    func testSafetyNetClearsAfterTenQuietMinutes() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        rig.wait(599_000)
        XCTAssertNotNil(rig.state.attn)
        rig.wait(1000)
        XCTAssertNil(rig.state.attn)
    }

    func testWhileSomethingNeedsYouOnlyWhatYouSayReachesTheBrain() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(5000)
        rig.send(.needsYou, session: "a", tool: "Bash")
        rig.wait(60_000)
        XCTAssertEqual(inputs(rig.send(.turnEnd, session: "b")), [])
        XCTAssertEqual(inputs(rig.core.talk("hello", at: rig.now)).map(\.kind), [.said])
    }
}

// MARK: - BEHAVIORS.md §3.3 You and Boop

final class CoreYouAndBoopTests: XCTestCase {
    /// HARNESS.md §2: a tap is the rules' alone; the brain's transcript
    /// only hears of it. While something needs you, the device only
    /// squashes, and the aside doesn't claim a reaction.
    func testATapIsTheRulesAlone() {
        let rig = CoreRig()
        let fx = rig.input(.tap)
        XCTAssertEqual(inputs(fx), [])
        XCTAssertEqual(asides(fx), ["tapped · 14:00 Wednesday: Boop wiggled"])
        XCTAssertEqual(moments(fx), [], "the device already wiggled")
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        let needed = rig.input(.tap)
        XCTAssertEqual(asides(needed), ["tapped while something needs you · 14:00 Wednesday"])
        XCTAssertEqual(moments(needed), [])
    }

    /// BEHAVIORS.md §3.3: the fourth tap within 3 s is a poke streak: an
    /// input for the brain in place of an aside. The rules add no moment:
    /// the device has already wiggled.
    func testFourPokesWithinThreeSecondsSideEyeAndReachTheBrain() {
        let rig = CoreRig()
        for _ in 0..<3 {
            let fx = rig.input(.tap)
            XCTAssertEqual(inputs(fx), [])
            XCTAssertEqual(asides(fx), ["tapped · 14:00 Wednesday: Boop wiggled"])
            rig.wait(900)
        }
        let fx = rig.input(.tap)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(asides(fx), [])
        XCTAssertEqual(inputs(fx).map(\.line), ["poked again and again · 14:00 Wednesday"])
        XCTAssertEqual(inputs(fx).first?.rules, "wiggle")
    }

    /// At most once a minute: a streak sooner is only noted in the brain's
    /// transcript.
    func testAPokeStreakReachesTheBrainAtMostOnceAMinute() {
        let rig = CoreRig()
        var pokes: [Input] = []
        func streak() -> [CoreEffect] {
            var fx: [CoreEffect] = []
            for _ in 0..<4 { fx += rig.input(.tap); fx += rig.wait(500) }
            pokes += inputs(fx)
            return fx
        }
        _ = streak()
        let soon = streak()
        XCTAssertEqual(moments(soon), [])
        XCTAssertEqual(asides(soon).last, "poked again and again · 14:00 Wednesday: Boop wiggled")
        rig.wait(60_000)
        _ = streak()
        XCTAssertEqual(pokes.map(\.kind), [.poked, .poked])
    }

    func testSlowPokesNeverAnnoyIt() {
        let rig = CoreRig()
        var fx: [CoreEffect] = []
        for _ in 0..<6 { fx += rig.input(.tap); fx += rig.wait(3000) }
        XCTAssertEqual(inputs(fx), [])
        XCTAssertEqual(moments(fx), [])
    }

    /// While something needs you a tap means "I saw it", so it isn't counted;
    /// in quiet mode a streak still reaches the brain.
    func testPokesWhileSomethingNeedsYouDontCount() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        var fx: [CoreEffect] = []
        for _ in 0..<5 { fx += rig.input(.tap); fx += rig.wait(300) }
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(inputs(fx), [])
        rig.send(.activity, tool: "Bash")  // answered on the Mac
        rig.core.setQuiet(minutes: 15, at: rig.now)
        fx = []
        for _ in 0..<4 { fx += rig.input(.tap); fx += rig.wait(200) }
        XCTAssertEqual(inputs(fx).map(\.kind), [.poked], "the taps before didn't count")
    }

    /// BEHAVIORS.md §3.3: the input says when you yelled, even with no words,
    /// and whether your words asked for quiet.
    func testYelledTalkAndAskingForQuiet() {
        let rig = CoreRig()
        let yelled = inputs(rig.core.talk("", yelled: true, at: rig.now)).first
        XCTAssertEqual(yelled?.line, "you said · yelled · 14:00 Wednesday")
        XCTAssertEqual(yelled?.words, "")
        XCTAssertEqual(yelled?.yelled, true)
        for (words, asked) in [("shut up", false), ("be quiet please", true), ("stop talking", false), ("Quiet!", true),
                               ("speak quietly", false)] {
            rig.core.talk(words, at: rig.now)
            XCTAssertEqual(rig.core.quietAsked, asked, words)
        }
    }

    func testPushToTalkListensAndSendsTheWords() {
        let rig = CoreRig()
        XCTAssertEqual(rig.input(.talkOn), [.listen(true)])
        XCTAssertEqual(rig.input(.talkOff), [.listen(false)])
        let t = inputs(rig.core.talk("shut up for ten minutes", at: rig.now))
        XCTAssertEqual(t.first?.kind, .said)
        XCTAssertEqual(t.first?.words, "shut up for ten minutes")
        XCTAssertEqual(t.first?.line, "you said · 14:00 Wednesday", "the words travel apart from the line")
        XCTAssertEqual(t.first?.rules, "listening")
        // HARNESS.md §4: about 30 s of speech at most.
        let long = inputs(rig.core.talk(String(repeating: "blah ", count: 200), at: rig.now))
        XCTAssertEqual(long.first?.words?.count, 500)
    }

    /// UX.md §5: the mic is on only while you hold the button, and never
    /// longer than 30 s, even if the release never arrives.
    func testTheMicTurnsItselfOffAfterThirtySeconds() {
        let rig = CoreRig()
        rig.input(.talkOn)
        XCTAssertEqual(rig.core.listening?.by, .device)
        XCTAssertEqual(rig.input(.talkOn), [], "a second talk_on doesn't restart the clock")
        XCTAssertFalse(rig.wait(29_000).contains(.listen(false)))
        let fx = rig.wait(1_000)
        XCTAssertTrue(fx.contains(.listen(false)))
        XCTAssertEqual(moments(fx), [], "the device's own listening ends at the same limit")
        XCTAssertFalse(rig.wait(Core.replyWaitMs * 2).contains(.endListening), "the device ends its own face")
        XCTAssertNil(rig.core.listening)
        XCTAssertEqual(rig.input(.talkOff), [], "the late release changes nothing")
    }

    func testALostLinkTurnsTheDevicesMicOff() {
        let rig = CoreRig()
        rig.input(.talkOn)
        XCTAssertEqual(rig.input(.talkOff), [.listen(false)], "nothing extra: the device waits for the reply itself")
        XCTAssertFalse(rig.wait(Core.replyWaitMs * 2).contains(.endListening))
        rig.input(.talkOn)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [.listen(false)])
        XCTAssertNil(rig.core.listening)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [])
    }

    /// BEHAVIORS.md §3.3: the Talk button shows `listening` from the mic
    /// turning on until the reply; 8 s after Send, the empty moment ends it
    /// if no reply came.
    func testTheTalkButtonListensThenWaitsEightSecondsForTheReply() {
        XCTAssertEqual(Core.replyWaitMs, 8_000)
        let rig = CoreRig()
        let on = rig.core.listen(true, at: rig.now)
        XCTAssertTrue(on.contains(.listen(true)))
        XCTAssertEqual(moments(on), ["listening"], "the device shows it's listening, as for its own button")
        XCTAssertEqual(rig.core.listening?.by, .app)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [], "the Mac's own button doesn't need the device")
        XCTAssertEqual(rig.input(.talkOn), [], "already listening")
        let off = rig.core.listen(false, at: rig.now)
        XCTAssertTrue(off.contains(.listen(false)))
        XCTAssertEqual(moments(off), [], "Send adds no face: listening carries on")
        XCTAssertFalse(off.contains(.endListening))
        XCTAssertFalse(rig.core.listen(false, at: rig.now).contains(.listen(false)), "stopping twice is harmless")
        XCTAssertFalse(rig.wait(7_000).contains(.endListening))
        let ended = rig.wait(1_000)
        XCTAssertEqual(ended.filter { $0 == .endListening }.count, 1)
        XCTAssertEqual(moments(ended), [])
        XCTAssertFalse(rig.wait(Core.replyWaitMs).contains(.endListening), "once")
    }

    /// BEHAVIORS.md §3.3: the 30 s mic limit waits for the reply as Send does.
    func testTheTalkButtonsLimitAlsoWaitsEightSeconds() {
        let rig = CoreRig()
        rig.core.listen(true, at: rig.now)
        let limit = rig.wait(Core.listenLimitMs)
        XCTAssertTrue(limit.contains(.listen(false)), "what was heard still goes to Boop")
        XCTAssertEqual(moments(limit), [])
        XCTAssertFalse(limit.contains(.endListening))
        XCTAssertFalse(rig.wait(Core.replyWaitMs - 1_000).contains(.endListening))
        XCTAssertTrue(rig.wait(1_000).contains(.endListening))
    }

    /// A new `listening` face isn't ended by the last one's empty moment.
    func testListeningAgainCancelsTheWait() {
        let rig = CoreRig()
        rig.core.listen(true, at: rig.now)
        rig.core.listen(false, at: rig.now)
        rig.wait(3_000)
        rig.input(.talkOn)
        XCTAssertFalse(rig.wait(Core.replyWaitMs).contains(.endListening))
        rig.input(.talkOff)
        rig.core.listen(true, at: rig.now)
        rig.core.listen(false, at: rig.now)
        rig.wait(3_000)
        rig.core.listen(true, at: rig.now)
        XCTAssertFalse(rig.wait(Core.replyWaitMs).contains(.endListening))
    }

    /// BEHAVIORS.md §3.3: a Mac mic that can't start ends the Talk button's
    /// `listening` at once with the empty moment. The device's own button
    /// ends its face by itself.
    func testAMicThatCantStartEndsListeningAtOnce() {
        let rig = CoreRig()
        rig.core.listen(true, at: rig.now)
        XCTAssertEqual(rig.core.micFailed(at: rig.now), [.listen(false), .endListening])
        XCTAssertFalse(rig.wait(Core.replyWaitMs * 2).contains(.endListening), "no second one later")
        rig.input(.talkOn)
        XCTAssertEqual(rig.core.micFailed(at: rig.now), [.listen(false)])
        XCTAssertFalse(rig.wait(Core.replyWaitMs * 2).contains(.endListening))
    }

    /// The first activity of the day starts short-term memory with no
    /// moment: the morning stretch and yawn were removed.
    func testFirstActivityOfTheDayStartsTheDayQuietly() {
        let rig = CoreRig(newDay: true)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-14", firstSeen: "14:00")))
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(moments(rig.wait(2000)), [])
        XCTAssertFalse(rig.send(.turnStart).contains { if case .newDay = $0 { true } else { false } }, "only the first activity")
    }

    func testANewDayRunsReflectionOnYesterday() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.wait(24 * 3600 * 1000)
        let fx = rig.send(.turnStart)
        XCTAssertEqual(inputs(fx).map(\.kind), [.newDay, .agentStarted])
        XCTAssertEqual(inputs(fx).first?.yesterday, "2026-10-14")
        XCTAssertEqual(inputs(fx).first?.line, "new day · yesterday 2026-10-14")
    }
}

// MARK: - Chatter, quiet, screen and inputs

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

    /// BEHAVIORS.md §2: every 2–4 minutes while agents work, day or night;
    /// about half the time a `curious` question about the topic, otherwise
    /// a `happy` mumble with no word.
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

    func testNoChatterWhenIdleOrQuiet() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(mumbles(rig.wait(600_000)), [])
        rig.send(.turnStart)
        rig.core.setQuiet(minutes: 30, at: rig.now)
        var fx: [CoreEffect] = []
        for _ in 0..<25 { fx += rig.wait(60_000); rig.send(.activity) }
        XCTAssertEqual(mumbles(fx), [])
    }

    /// BEHAVIORS.md §5: going quiet shows only the quiet icon; the `zip`
    /// animation is parked.
    func testGoingQuietPlaysNoMoment() {
        let rig = CoreRig()
        let fx = rig.core.setQuiet(minutes: 30, at: rig.now)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(states(fx).last?.quiet, 30)
    }

    func testQuietCountsDownInTheSnapshot() {
        let rig = CoreRig()
        XCTAssertEqual(states(rig.core.setQuiet(minutes: 10, at: rig.now)).last?.quiet, 10)
        rig.wait(90_000)
        XCTAssertEqual(rig.state.quiet, 9)
        rig.wait(510_000)
        XCTAssertEqual(rig.state.quiet, 0)
        XCTAssertEqual(inputs(rig.send(.turnStart)).count, 1)
    }

    func testQuietGatesAgentInputs() {
        let rig = CoreRig()
        rig.core.setQuiet(minutes: 5, at: rig.now)
        XCTAssertEqual(inputs(rig.turn(40_000)), [])
        XCTAssertEqual(inputs(rig.core.talk("hi", at: rig.now)).count, 1)
        XCTAssertFalse(rig.core.canMumble(at: rig.now))
        rig.core.setQuiet(minutes: 0, at: rig.now)
        XCTAssertTrue(rig.core.canMumble(at: rig.now))
    }

    /// HARNESS.md §2: agent inputs within 3 s become one, the most important
    /// winning: failed, then a finish of 15 s or more, then a shorter
    /// finish, then a start.
    func testAgentInputsInABurstMergeIntoOne() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(600_000)
        let first = inputs(rig.send(.turnEnd, session: "a"))
        XCTAssertEqual(first.count, 1)
        rig.wait(500)
        XCTAssertEqual(inputs(rig.send(.turnStart, session: "c")), [])
        XCTAssertEqual(inputs(rig.send(.turnFailed, session: "b")), [])
        let merged = inputs(rig.wait(3000))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].outcome, .failed, "failed beats a start")
        XCTAssertEqual(merged[0].more, 1)
        XCTAssertTrue(merged[0].line.hasSuffix(" · +1 more"), merged[0].line)
        rig.wait(5000)
        XCTAssertEqual(inputs(rig.send(.turnStart, session: "d")).count, 1, "a new window")
    }

    /// PROTOCOL.md §3: the `state` message carries only the counts and
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
        XCTAssertEqual([s.busy, s.idle, s.wait], [2, 1, 1])
        XCTAssertEqual(s.jsonLine, #"{"t":"state","v":1,"time":1791986400,"name":"Pip","base":"working","attn":{"agent":"claude","project":"landing","more":0},"busy":2,"idle":1,"wait":1,"quiet":0,"vol":6}"#)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(s.jsonLine.utf8)))
    }

    func testNamesAreClippedToTheDevicesFields() {
        let rig = CoreRig()
        rig.send(.needsYou, session: "s", project: "a-really-long-project-name-number-1", tool: "Bash")
        XCTAssertEqual(rig.state.attn?.project, "a-really-long-project-n")
        XCTAssertEqual(rig.sessions.first?[1], "a-really-long-project-name-number-1", "the popover shows it whole")
        XCTAssertLessThanOrEqual(rig.state.jsonLine.utf8.count, StateSnapshot.maxLine)
        XCTAssertEqual(StateSnapshot.clip("ünïcödé-ünïcödé-ünïcödé"), "ünïcödé-ünïcödé")
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
