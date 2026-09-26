import Foundation
import XCTest
@testable import BoopKit

/// Drives a core with a virtual clock. Starts 2026-10-14 14:00 UTC, a
/// Wednesday afternoon, with today's rituals already done.
final class CoreRig {
    static let start: Int64 = 1_791_986_400_000
    static let day: Int64 = 24 * 3600 * 1000
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    var now: Int64
    let core: Core
    var log: [CoreEffect] = []

    /// `awaySince` restores "I'm away" from settings, as the app does after
    /// a restart, before the first tick.
    init(start: Int64 = CoreRig.start, growth: Growth? = nil, newDay: Bool = false, seed: UInt64 = 1,
         awaySince: String? = nil) {
        now = start
        let today = time.day(start)
        core = Core(config: .init(name: "Pip", time: time, seed: seed), growth: growth ?? Growth(hatched: today),
                    lastActiveDay: newDay ? nil : today, now: start)
        if let awaySince { core.setAway(true, since: awaySince, at: start) }
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
}

func moments(_ fx: [CoreEffect]) -> [String] {
    fx.compactMap { if case .moment(let anim, let size) = $0 { return "\(anim) \(size)" } else { return nil } }
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

func growths(_ fx: [CoreEffect]) -> [Growth] {
    fx.compactMap { if case .growth(let g) = $0 { return g } else { return nil } }
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

    /// BEHAVIORS.md §3.1: size 1 under 15 s, 2 up to a minute, 3 beyond.
    func testTurnUnder15sCheersSize1() {
        let rig = CoreRig()
        XCTAssertEqual(moments(rig.turn(14_000)), ["cheer 1"])
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(moments(CoreRig().turn(5_000)), ["cheer 1"])
    }

    func testTurn15sTo1MinCheersSize2() {
        XCTAssertEqual(moments(CoreRig().turn(15_000)), ["cheer 2"])
        XCTAssertEqual(moments(CoreRig().turn(60_000)), ["cheer 2"])
    }

    func testTurnOver1MinCheersSize3() {
        let rig = CoreRig()
        let fx = rig.turn(1_200_000)
        XCTAssertEqual(moments(fx), ["cheer 3"])
        XCTAssertTrue(fx.contains(.happened("14:20 claude · landing · finished (20 min)")))
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · done · claude · landing · took 20 min · 14:20 Wednesday")
        XCTAssertEqual(inputs(fx).first?.rules, "cheer size 3")
        XCTAssertEqual(inputs(fx).first?.tookMs, 1_200_000)
    }

    func testAFinishCheersWhileOthersKeepWorking() {  // BEHAVIORS.md §3.1
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(10_000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "a")), ["cheer 1"])
        XCTAssertEqual(rig.state.base, "working")
    }

    func testSeveralFinishingAtOnceMakeOneCheerAtTheBiggestSize() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.send(.turnStart, session: "c")
        rig.wait(30_000)
        rig.send(.turnStart, session: "c")  // c restarts: a quick one
        rig.wait(10_000)
        var fx = rig.send(.turnEnd, session: "c")
        XCTAssertEqual(moments(fx), ["cheer 1"])
        rig.wait(1000)
        fx = rig.send(.turnEnd, session: "a")
        XCTAssertEqual(moments(fx), ["cheer 2"], "upgraded to the bigger cheer")
        rig.wait(1000)
        fx = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(moments(fx), [], "same size inside the window: no second cheer")
        rig.wait(5000)
        rig.send(.turnStart, session: "a")
        rig.wait(1000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "a")), ["cheer 1"], "a new window")
    }

    func testFailedTurnPlaysOopsThenSideEye() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.wait(60_000)
        let fx = rig.send(.turnFailed)
        XCTAssertEqual(moments(fx), ["oops 1"])
        XCTAssertTrue(fx.contains(.happened("14:01 claude · landing · tests · failed")))
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · failed · claude · landing · topic: tests · 14:01 Wednesday")
        XCTAssertEqual(inputs(fx).first?.rules, "oops, then side_eye")
        XCTAssertEqual(moments(rig.wait(1000)), [])
        XCTAssertEqual(moments(rig.wait(1000)), ["side_eye 1"])
        XCTAssertEqual(growths(fx), [], "failures earn nothing")
    }

    /// BEHAVIORS.md §3.1: a turn whose last test, build or deploy command
    /// failed is a failed turn: oops, a side-eye, no cheer and no XP.
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
        XCTAssertEqual(moments(fx), ["oops 1"])
        XCTAssertEqual(inputs(fx).first?.line, "agent finished · failed · claude · landing · topic: tests · 14:01 Wednesday")
        XCTAssertTrue(fx.contains(.happened("14:01 claude · landing · tests · failed")))
        XCTAssertEqual(growths(fx), [], "a failed turn earns nothing")
        XCTAssertEqual(moments(rig.wait(2000)), ["side_eye 1"])
    }

    func testATurnWhoseLastCheckPassedCheers() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "build", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: false)
        rig.wait(10_000)
        XCTAssertEqual(moments(rig.send(.turnEnd)), ["cheer 1"])
        // The next turn starts clean: a failure in the last one doesn't count.
        rig.wait(5000)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "deploy", failed: true)
        rig.send(.turnEnd)
        rig.wait(5000)
        rig.send(.turnStart)
        rig.wait(1000)
        XCTAssertEqual(moments(rig.send(.turnEnd)), ["cheer 1"])
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
        XCTAssertEqual(states(fx).last?.threads, [["claude", "jetpack", "wait"]])
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
        XCTAssertEqual(moments(fx), [], "the device plays the nod when attn clears")
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
    /// only hears of it.
    func testATapIsTheRulesAlone() {
        let rig = CoreRig()
        let fx = rig.input(.tap)
        XCTAssertEqual(inputs(fx), [])
        XCTAssertEqual(asides(fx), ["tapped · 14:00 Wednesday: Boop wiggled"])
        XCTAssertEqual(moments(fx), [], "the device already wiggled")
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        XCTAssertEqual(asides(rig.input(.tap)), ["tapped · 14:00 Wednesday: Boop nodded and stopped nudging"])
    }

    /// BEHAVIORS.md §3.3: the fourth tap within 3 s is a poke streak: a
    /// side-eye at you, and an input for the brain in place of an aside.
    func testFourPokesWithinThreeSecondsSideEyeAndReachTheBrain() {
        let rig = CoreRig()
        for _ in 0..<3 {
            let fx = rig.input(.tap)
            XCTAssertEqual(inputs(fx), [])
            XCTAssertEqual(asides(fx), ["tapped · 14:00 Wednesday: Boop wiggled"])
            rig.wait(900)
        }
        let fx = rig.input(.tap)
        XCTAssertEqual(moments(fx), ["side_eye 1"])
        XCTAssertEqual(asides(fx), [])
        XCTAssertEqual(inputs(fx).map(\.line), ["poked again and again · 14:00 Wednesday"])
        XCTAssertEqual(inputs(fx).first?.rules, "side_eye at you")
    }

    /// At most once a minute: a streak sooner side-eyes you, and the brain
    /// only hears of it.
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
        XCTAssertEqual(moments(soon), ["side_eye 1"])
        XCTAssertEqual(asides(soon).last, "poked again and again · 14:00 Wednesday: Boop side-eyed you")
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
    /// in quiet mode a streak still side-eyes you and reaches the brain.
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
        XCTAssertEqual(moments(fx), ["side_eye 1"], "the taps before didn't count")
        XCTAssertEqual(inputs(fx).map(\.kind), [.poked])
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
        XCTAssertEqual(t.first?.rules, "listening, then thinking")
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
        XCTAssertNil(rig.core.listening)
        XCTAssertEqual(rig.input(.talkOff), [], "the late release changes nothing")
    }

    func testALostLinkTurnsTheDevicesMicOff() {
        let rig = CoreRig()
        rig.input(.talkOn)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [.listen(false)])
        XCTAssertNil(rig.core.listening)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [])
    }

    func testTheTalkButtonListensThenThinks() {
        let rig = CoreRig()
        let on = rig.core.listen(true, at: rig.now)
        XCTAssertTrue(on.contains(.listen(true)))
        XCTAssertEqual(moments(on), ["listening 1"], "the device shows it's listening, as for its own button")
        XCTAssertEqual(rig.core.listening?.by, .app)
        XCTAssertEqual(rig.core.linkDown(at: rig.now), [], "the Mac's own button doesn't need the device")
        XCTAssertEqual(rig.input(.talkOn), [], "already listening")
        let off = rig.core.listen(false, at: rig.now)
        XCTAssertTrue(off.contains(.listen(false)))
        XCTAssertEqual(moments(off), ["thinking 1"])
        XCTAssertFalse(rig.core.listen(false, at: rig.now).contains(.listen(false)), "stopping twice is harmless")

        rig.core.listen(true, at: rig.now)
        let limit = rig.wait(Core.listenLimitMs)
        XCTAssertTrue(limit.contains(.listen(false)))
        XCTAssertEqual(moments(limit), ["thinking 1"], "what was heard still goes to Boop")
    }

    func testAMicThatCantStartShrugs() {
        let rig = CoreRig()
        rig.core.listen(true, at: rig.now)
        let fx = rig.core.micFailed(at: rig.now)
        XCTAssertEqual(fx, [.listen(false), .moment(anim: "shrug", size: 1)])
        rig.input(.talkOn)
        XCTAssertEqual(rig.core.micFailed(at: rig.now), [.listen(false)], "the device shrugs by itself after its thinking")
    }

    /// The first activity of the day starts the day with no reaction and no
    /// XP: stretch, yawn and their +5 XP were removed from the product.
    func testFirstActivityOfTheDayStartsTheDayQuietly() {
        let rig = CoreRig(newDay: true)
        let fx = rig.send(.sessionStart)
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-14", firstSeen: "14:00", mood: "content")))
        XCTAssertEqual(moments(fx), [])
        XCTAssertTrue(growths(fx).isEmpty)
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

// MARK: - BEHAVIORS.md §4 XP and hunger

final class CoreGrowthTests: XCTestCase {
    func testOneXPPerFinishedTurn() {
        let rig = CoreRig(newDay: true)
        rig.turn(10_000)
        rig.turn(10_000)
        XCTAssertEqual(rig.core.growth.xp, 2)
        rig.input(.tap)
        rig.send(.needsYou, tool: "Bash")
        rig.send(.activity)
        XCTAssertEqual(rig.core.growth.xp, 2, "taps, approvals and time earn nothing")
    }

    func testLevels() {
        XCTAssertEqual(Growth(xp: 0, hatched: "2026-10-01").level, 1)
        XCTAssertEqual(Growth(xp: 49, hatched: "2026-10-01").level, 1)
        XCTAssertEqual(Growth(xp: 50, hatched: "2026-10-01").level, 2)
        XCTAssertEqual(Growth(xp: 1240, hatched: "2026-10-01").level, 25)
        XCTAssertEqual(Growth(xp: 1240, hatched: "2026-10-01").progress, 80)
    }

    func testLevelUpPlaysAtTheNextCalmMoment() {
        let rig = CoreRig(growth: Growth(xp: 49, hatched: "2026-10-01", lastFed: "2026-10-14"))
        rig.send(.turnStart, session: "other")
        rig.send(.needsYou, session: "other", tool: "Bash")
        let fx = rig.turn(10_000)
        XCTAssertEqual(moments(fx), ["cheer 1"])
        XCTAssertEqual(rig.state.level, 2)
        XCTAssertFalse(moments(rig.wait(60_000)).contains("levelup 1"), "not while something needs you")
        rig.send(.activity, session: "other")
        let later = rig.wait(5000)
        XCTAssertEqual(moments(later), ["levelup 1"])
        XCTAssertTrue(later.contains(.happened("14:01 reached level 2")))
    }

    func testDaysTogether() {
        XCTAssertEqual(Growth(hatched: "2026-10-14").days(today: "2026-10-14"), 1)
        XCTAssertEqual(Growth(hatched: "2026-10-02").days(today: "2026-10-14"), 13)
        XCTAssertEqual(CoreRig(growth: Growth(hatched: "2026-10-02")).state.days, 13)
    }

    func testHungerThresholds() {
        let g = Growth(xp: 100, hatched: "2026-09-01", lastFed: "2026-10-10")
        XCTAssertEqual(g.hunger(today: "2026-10-11"), .fed)
        XCTAssertEqual(g.hunger(today: "2026-10-12"), .hungry)
        XCTAssertEqual(g.hunger(today: "2026-10-15"), .hungry)
        XCTAssertEqual(g.hunger(today: "2026-10-16"), .starving)
        XCTAssertEqual(CoreRig(growth: Growth(hatched: "2026-09-01", lastFed: "2026-10-11")).state.hungry, 1)
        XCTAssertEqual(CoreRig(growth: Growth(hatched: "2026-09-01", lastFed: "2026-10-01")).state.hungry, 2)
    }

    func testStarvingLosesOneXPADayButNeverDropsALevel() {
        var g = Growth(xp: 102, hatched: "2026-09-01", lastFed: "2026-10-01")
        XCTAssertTrue(g.starve(today: "2026-10-07"))
        XCTAssertEqual(g.xp, 101)
        XCTAssertFalse(g.starve(today: "2026-10-07"), "once a day")
        g.starve(today: "2026-10-08")
        XCTAssertEqual(g.xp, 100)
        g.starve(today: "2026-10-20")
        XCTAssertEqual(g.xp, 100, "the start of level 3 is the floor")
        XCTAssertEqual(g.level, 3)
        g.earn(1, today: "2026-10-20")
        XCTAssertEqual(g.lost, 0)
        XCTAssertEqual(g.hunger(today: "2026-10-20"), .fed)
    }

    func testTheCoreAppliesStarvingAsDaysPass() {
        let rig = CoreRig(growth: Growth(xp: 60, hatched: "2026-09-01", lastFed: "2026-10-08"))
        XCTAssertEqual(rig.state.hungry, 2)
        rig.wait(1000)
        XCTAssertEqual(rig.core.growth.xp, 59)
        rig.wait(24 * 3600 * 1000)
        XCTAssertEqual(rig.core.growth.xp, 58)
    }

    func testFirstXPAfterBeingHungryPlaysGobble() {
        let rig = CoreRig(growth: Growth(xp: 10, hatched: "2026-09-01", lastFed: "2026-10-11"))
        let fx = rig.turn(10_000)
        XCTAssertEqual(moments(fx), ["cheer 1"])
        XCTAssertEqual(rig.state.hungry, 0)
        XCTAssertEqual(moments(rig.wait(2000)), ["gobble 1"])
        XCTAssertFalse(moments(rig.turn(40_000) + rig.wait(3000)).contains("gobble 1"))
    }

    func testHungerNeverSoundsOrInterrupts() {
        let rig = CoreRig(growth: Growth(xp: 10, hatched: "2026-09-01", lastFed: "2026-10-01"))
        let fx = rig.wait(3600 * 1000)
        XCTAssertEqual(moments(fx), [])
        XCTAssertEqual(mumbles(fx), [])
        XCTAssertEqual(inputs(fx), [])
    }

    /// BEHAVIORS.md §4: "I'm away" in the app pauses hunger, across a
    /// restart too: the pause keeps the day it started, and a hungry Boop
    /// loses nothing while you're gone.
    func testAwaySurvivesARestart() {
        let rig = CoreRig(growth: Growth(xp: 60, hatched: "2026-09-01", lastFed: "2026-10-09"))
        rig.core.setAway(true, at: rig.now)
        XCTAssertEqual(rig.core.awaySince, "2026-10-14")
        XCTAssertEqual(rig.state.hungry, 1)

        // Ten days on, the app starts again with away restored from settings.
        let restarted = CoreRig(start: rig.now + 10 * CoreRig.day, growth: rig.core.growth,
                                awaySince: rig.core.awaySince)
        XCTAssertEqual(restarted.core.awaySince, "2026-10-14", "the pause keeps its first day")
        XCTAssertEqual(restarted.state.hungry, 1, "as hungry as when you left, not starving")
        restarted.wait(3000)
        XCTAssertEqual(restarted.core.growth.xp, 60, "no XP lost while away")
        let fx = restarted.core.setAway(false, at: restarted.now)
        XCTAssertEqual(growths(fx).last?.lastFed, "2026-10-19", "moved on by the ten away days")
        XCTAssertEqual(restarted.state.hungry, 1)
        XCTAssertEqual(restarted.core.growth.xp, 60)
    }

    /// BEHAVIORS.md §4: XP earned while away is a meal, so coming back adds
    /// only the away days after it, and "last fed" never passes today.
    func testFeedingWhileAwayThenReturningStopsAtToday() {
        let rig = CoreRig(growth: Growth(xp: 10, hatched: "2026-09-01", lastFed: "2026-10-13"))
        rig.core.setAway(true, at: rig.now)
        rig.now += 6 * CoreRig.day
        rig.turn(10_000)  // a new day's first activity and a finished turn
        XCTAssertEqual(rig.core.growth.lastFed, "2026-10-20")
        XCTAssertEqual(rig.core.growth.xp, 11)
        rig.now += 3 * CoreRig.day
        let fx = rig.core.setAway(false, at: rig.now)
        XCTAssertEqual(growths(fx).last?.lastFed, "2026-10-23", "today, not nine days on from the meal")
        XCTAssertEqual(rig.state.hungry, 0)
    }

    func testAwayPausesHunger() {
        let rig = CoreRig(growth: Growth(xp: 10, hatched: "2026-09-01", lastFed: "2026-10-13"))
        rig.core.setAway(true, at: rig.now)
        rig.wait(10 * 24 * 3600 * 1000)
        XCTAssertEqual(rig.state.hungry, 0)
        XCTAssertEqual(rig.core.growth.xp, 10)
        let fx = rig.core.setAway(false, at: rig.now)
        XCTAssertEqual(growths(fx).last?.lastFed, "2026-10-23")
        XCTAssertEqual(rig.state.hungry, 0)
    }
}

// MARK: - Mood, chatter, quiet, screen and inputs

final class CoreRulesTests: XCTestCase {
    func testFailuresCalmBoopAndItDriftsBackInHalfAnHour() {
        let rig = CoreRig()
        for _ in 0..<3 {
            rig.send(.turnStart)
            rig.send(.turnFailed)
        }
        let low = rig.state.mood
        XCTAssertLessThan(low.energy, 60)
        XCTAssertLessThan(low.pace, 80)
        XCTAssertEqual(rig.core.moodWord(at: rig.now), "a bit frazzled")
        rig.wait(30 * 60 * 1000)
        XCTAssertGreaterThan(rig.state.mood.energy, 92)
    }

    func testQuickWinsMakeBoopBouncier() {
        let rig = CoreRig()
        for i in 0..<4 { rig.turn(5000, session: "q\(i)") }
        let mood = rig.state.mood
        XCTAssertGreaterThan(mood.energy, 130)
        XCTAssertGreaterThan(mood.pitch, 110)
    }

    func testNightIsDrowsierAndSleepsWithNothingWorking() {
        let rig = CoreRig(start: CoreRig.start + 9 * 3600 * 1000)  // 23:00
        rig.send(.sessionStart)
        XCTAssertTrue(rig.state.night)
        XCTAssertEqual(rig.state.base, "asleep")
        XCTAssertLessThan(rig.state.mood.energy, 100)
        rig.send(.turnStart)
        XCTAssertEqual(rig.state.base, "working")
    }

    func testNoSessionsIsAsleep() {
        XCTAssertEqual(CoreRig().state.base, "asleep")
    }

    func testWorkingChatterEveryTwoToFourMinutesWithTheTopicAboutHalfTheTime() {
        let rig = CoreRig(seed: 7)
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        var times: [Int64] = []
        var words = 0
        for _ in 0..<3600 {
            let fx = rig.wait(1000)
            rig.send(.activity)  // keep it working
            for m in mumbles(fx) {
                times.append(rig.now)
                if m.hasSuffix("tests") { words += 1 }
            }
        }
        XCTAssertGreaterThan(times.count, 12)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 120_000)
            XCTAssertLessThanOrEqual(b - a, 241_000)
        }
        XCTAssertGreaterThan(words, times.count / 5)
        XCTAssertLessThan(words, times.count * 4 / 5)
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

    /// BEHAVIORS.md §7: going quiet zips Boop's mouth, once.
    func testGoingQuietZipsBoopsMouth() {
        let rig = CoreRig()
        let fx = rig.core.setQuiet(minutes: 30, at: rig.now)
        XCTAssertEqual(moments(fx), ["zip 1"])
        XCTAssertEqual(states(fx).last?.quiet, 30, "the picture changes first")
        XCTAssertEqual(moments(rig.core.setQuiet(minutes: 60, at: rig.now)), [], "already quiet")
        XCTAssertEqual(moments(rig.core.setQuiet(minutes: 0, at: rig.now)), [])
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

    func testSnapshotShapeAndThreads() {
        let rig = CoreRig()
        rig.send(.sessionStart, .claudeCode, session: "a", project: "notes")
        rig.send(.turnStart, .codex, session: "b", project: "buddygotchi")
        rig.send(.turnStart, .claudeCode, session: "c", project: "jetpack")
        rig.send(.needsYou, .claudeCode, session: "d", project: "landing", tool: "Bash")
        let s = rig.state
        XCTAssertEqual(s.threads, [["claude", "landing", "wait"], ["codex", "buddygotchi", "work"],
                                   ["claude", "jetpack", "work"], ["claude", "notes", "idle"]])
        XCTAssertEqual([s.busy, s.idle, s.wait], [2, 1, 1])
        XCTAssertEqual(s.jsonLine, #"{"t":"state","v":1,"time":1791986400,"name":"Pip","base":"working","attn":{"agent":"claude","project":"landing","more":0},"busy":2,"idle":1,"wait":1,"mood":{"energy":100,"pace":100,"pitch":100},"quiet":0,"vol":6,"night":false,"level":1,"prog":0,"days":1,"hungry":0,"threads":[["claude","landing","wait"],["codex","buddygotchi","work"],["claude","jetpack","work"],["claude","notes","idle"]]}"#)
        let data = Data(s.jsonLine.utf8)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
        XCTAssertLessThanOrEqual(data.count, 512)
    }

    func testAtMostEightThreadsAndAFullSnapshotFitsInOneLine() {
        let rig = CoreRig()
        for i in 0..<12 {
            rig.send(.turnStart, i % 2 == 0 ? .codex : .claudeCode, session: "s\(i)", project: "project-name-\(i)")
        }
        XCTAssertEqual(rig.state.threads.count, 8, "all eight rows fit in 512 bytes")
        XCTAssertEqual(rig.state.busy, 12)
        let short = CoreRig()
        for i in 0..<12 { short.send(.turnStart, session: "s\(i)", project: "p\(i)") }
        XCTAssertEqual(short.state.threads.count, 8)
        XCTAssertLessThanOrEqual(rig.state.jsonLine.utf8.count, 512)

        let long = CoreRig()
        for i in 0..<8 {
            long.send(.turnStart, session: "s\(i)", project: "a-really-long-project-name-number-\(i)")
        }
        XCTAssertEqual(long.state.threads.first?[1], "a-really-long-project-n")
        XCTAssertLessThanOrEqual(long.state.jsonLine.utf8.count, 512)
        XCTAssertGreaterThan(long.state.threads.count, 4)
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
        XCTAssertEqual(rig.state.threads, [])
    }

    func testSessionEndRemovesIt() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.send(.sessionEnd)
        XCTAssertEqual(rig.state.threads, [])
        XCTAssertEqual(rig.state.base, "asleep")
    }
}
