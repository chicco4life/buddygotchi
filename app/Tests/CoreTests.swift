import Foundation
import XCTest
@testable import BoopKit

/// Drives a core with a virtual clock. Starts 2026-10-14 14:00 UTC, a
/// Wednesday afternoon, with today's rituals already done.
final class CoreRig {
    static let start: Int64 = 1_791_986_400_000
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    var now: Int64
    let core: Core
    var log: [CoreEffect] = []

    init(start: Int64 = CoreRig.start, growth: Growth? = nil, newDay: Bool = false, seed: UInt64 = 1) {
        now = start
        let today = time.day(start)
        core = Core(config: .init(name: "Pip", time: time, seed: seed), growth: growth ?? Growth(hatched: today),
                    lastActiveDay: newDay ? nil : today, now: start)
        if !newDay { core.tick(at: start) }  // the first snapshot has gone out
    }

    @discardableResult
    func send(_ kind: BoopEvent.Kind, _ agent: Agent = .claudeCode, session: String = "s1", project: String = "landing",
              tool: String? = nil, topic: String? = nil) -> [CoreEffect] {
        let fx = core.handle(BoopEvent(agent: agent, session: session, project: project, event: kind,
                                       detail: .init(tool: tool, topic: topic), ts: now))
        log += fx
        return fx
    }

    @discardableResult
    func input(_ input: Core.Input) -> [CoreEffect] {
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

func triggers(_ fx: [CoreEffect]) -> [Trigger] {
    fx.compactMap { if case .trigger(let t) = $0 { return t } else { return nil } }
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
        XCTAssertEqual(triggers(fx).map(\.kind), [.event])
        XCTAssertEqual(triggers(fx).first?.line, "turn started · claude · landing · 14:00 Wednesday")
    }

    func testTurnUnder30sNods() {
        let rig = CoreRig()
        XCTAssertEqual(moments(rig.turn(29_000)), ["nod 1"])
        XCTAssertEqual(rig.state.base, "idle")
    }

    func testTurn30sTo5MinCheersSize1() {
        XCTAssertEqual(moments(CoreRig().turn(30_000)), ["cheer 1"])
        XCTAssertEqual(moments(CoreRig().turn(299_000)), ["cheer 1"])
    }

    func testTurn5To20MinCheersSize2() {
        XCTAssertEqual(moments(CoreRig().turn(300_000)), ["cheer 2"])
        XCTAssertEqual(moments(CoreRig().turn(1_199_000)), ["cheer 2"])
    }

    func testTurnOver20MinCheersSize3() {
        let rig = CoreRig()
        let fx = rig.turn(1_200_000)
        XCTAssertEqual(moments(fx), ["cheer 3"])
        XCTAssertTrue(fx.contains(.happened("14:20 claude · landing · finished (20 min)")))
        XCTAssertEqual(triggers(fx).first?.line, "turn finished · claude · landing · took 20 min · 14:20 Wednesday")
    }

    func testSeveralFinishingAtOnceMakeOneCheerAtTheBiggestSize() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.send(.turnStart, session: "c")
        rig.wait(400_000)
        rig.send(.turnStart, session: "c")  // c restarts: a quick one
        rig.wait(10_000)
        var fx = rig.send(.turnEnd, session: "c")
        XCTAssertEqual(moments(fx), ["nod 1"])
        rig.wait(1000)
        fx = rig.send(.turnEnd, session: "a")
        XCTAssertEqual(moments(fx), ["cheer 2"], "upgraded to the bigger cheer")
        rig.wait(1000)
        fx = rig.send(.turnEnd, session: "b")
        XCTAssertEqual(moments(fx), [], "same size inside the window: no second cheer")
        rig.wait(5000)
        rig.send(.turnStart, session: "a")
        rig.wait(1000)
        XCTAssertEqual(moments(rig.send(.turnEnd, session: "a")), ["nod 1"], "a new window")
    }

    func testFailedTurnPlaysOopsThenSideEye() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.wait(60_000)
        let fx = rig.send(.turnFailed)
        XCTAssertEqual(moments(fx), ["oops 1"])
        XCTAssertTrue(fx.contains(.happened("14:01 claude · landing · tests · failed")))
        XCTAssertEqual(triggers(fx).first?.line, "turn failed · claude · landing · topic: tests · 14:01 Wednesday")
        XCTAssertEqual(moments(rig.wait(1000)), [])
        XCTAssertEqual(moments(rig.wait(1000)), ["side_eye 1"])
        XCTAssertEqual(growths(fx), [], "failures earn nothing")
    }

    func testTopicAndErrorReachTheTriggerLine() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests")
        rig.send(.activity, tool: "Read")
        rig.wait(3000)
        let fx = rig.core.handle(BoopEvent(agent: .claudeCode, session: "s1", project: "landing", event: .turnFailed,
                                           detail: .init(error: "rate_limit"), ts: rig.now))
        XCTAssertEqual(triggers(fx).first?.line, "turn failed · claude · landing · topic: tests · error: rate limit · 14:00 Wednesday")
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
        XCTAssertEqual(triggers(fx), [], "needs you is never a trigger")
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

    func testWhileSomethingNeedsYouOnlyTalkAndReflectionReachTheHarness() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(5000)
        rig.send(.needsYou, session: "a", tool: "Bash")
        rig.wait(60_000)
        XCTAssertEqual(triggers(rig.input(.tap)), [])
        XCTAssertEqual(triggers(rig.send(.turnEnd, session: "b")), [])
        XCTAssertEqual(triggers(rig.core.talk("hello", at: rig.now)).map(\.kind), [.talk])
        XCTAssertEqual(mumbles(rig.input(.feel)), [], "no mumbles while something needs you")
    }
}

// MARK: - BEHAVIORS.md §3.3 You and Boop

final class CoreYouAndBoopTests: XCTestCase {
    func testTapSendsATapTrigger() {
        let rig = CoreRig()
        let fx = rig.input(.tap)
        XCTAssertEqual(triggers(fx).map(\.line), ["tapped · 14:00 Wednesday"])
        XCTAssertEqual(moments(fx), [], "the device already wiggled")
    }

    func testPushToTalkListensAndSendsTheWords() {
        let rig = CoreRig()
        XCTAssertEqual(rig.input(.talkOn), [.listen(true)])
        XCTAssertEqual(rig.input(.talkOff), [.listen(false)])
        let t = triggers(rig.core.talk("shut up for ten minutes", at: rig.now))
        XCTAssertEqual(t.first?.kind, .talk)
        XCTAssertEqual(t.first?.words, "shut up for ten minutes")
        XCTAssertFalse(t.first!.line.contains("shut"), "the words travel apart from the line")
    }

    func testTouchAndHoldGetsAMumbleFromTheMood() {
        let rig = CoreRig()
        XCTAssertEqual(mumbles(rig.input(.feel)), ["curious"])
        rig.turn(10_000)
        rig.turn(10_000, session: "s2")
        XCTAssertEqual(mumbles(rig.input(.feel)), ["happy"])
    }

    func testFirstActivityOfTheDayStretchesThenYawns() {
        let rig = CoreRig(newDay: true)
        let fx = rig.send(.sessionStart)
        XCTAssertEqual(moments(fx), ["stretch 1"])
        XCTAssertTrue(fx.contains(.newDay(date: "2026-10-14", firstSeen: "14:00", mood: "content")))
        XCTAssertEqual(growths(fx).last?.xp, 5)
        XCTAssertEqual(moments(rig.wait(2000)), ["yawn 1"])
        XCTAssertEqual(moments(rig.send(.turnStart)), [], "only the first activity")
    }

    func testANewDayRunsReflectionOnYesterday() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.wait(24 * 3600 * 1000)
        let fx = rig.send(.turnStart)
        XCTAssertEqual(triggers(fx).map(\.kind), [.reflect, .event])
        XCTAssertEqual(triggers(fx).first?.line, "reflect · yesterday 2026-10-14")
        XCTAssertEqual(moments(fx), ["stretch 1"])
    }

    func testFocusToggleFromTheDevice() {
        let rig = CoreRig()
        XCTAssertEqual(states(rig.input(.focus)).last?.focus, true)
        XCTAssertEqual(states(rig.input(.focus)).last?.focus, false)
    }
}

// MARK: - BEHAVIORS.md §4 XP and hunger

final class CoreGrowthTests: XCTestCase {
    func testOneXPPerFinishedTurnAndFiveForTheFirstActivityOfTheDay() {
        let rig = CoreRig(newDay: true)
        rig.turn(10_000)
        rig.turn(10_000)
        XCTAssertEqual(rig.core.growth.xp, 7)
        rig.input(.tap)
        rig.send(.needsYou, tool: "Bash")
        rig.send(.activity)
        XCTAssertEqual(rig.core.growth.xp, 7, "taps, approvals and time earn nothing")
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
        let fx = rig.turn(40_000)
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
        let fx = rig.turn(40_000)
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
        XCTAssertEqual(triggers(fx), [])
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

// MARK: - Mood, chatter, quiet, focus, screen and triggers

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

    func testNoChatterWhenIdleQuietOrInFocus() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        XCTAssertEqual(mumbles(rig.wait(600_000)), [])
        rig.send(.turnStart)
        rig.core.setQuiet(minutes: 30, at: rig.now)
        var fx: [CoreEffect] = []
        for _ in 0..<25 { fx += rig.wait(60_000); rig.send(.activity) }
        XCTAssertEqual(mumbles(fx), [])
        rig.core.setFocus(true, at: rig.now)
        fx = []
        for _ in 0..<10 { fx += rig.wait(60_000); rig.send(.activity) }
        XCTAssertEqual(mumbles(fx), [])
    }

    func testQuietCountsDownInTheSnapshot() {
        let rig = CoreRig()
        XCTAssertEqual(states(rig.core.setQuiet(minutes: 10, at: rig.now)).last?.quiet, 10)
        rig.wait(90_000)
        XCTAssertEqual(rig.state.quiet, 9)
        rig.wait(510_000)
        XCTAssertEqual(rig.state.quiet, 0)
        XCTAssertEqual(triggers(rig.input(.tap)).count, 1)
    }

    func testQuietAndFocusGateTriggers() {
        let rig = CoreRig()
        rig.core.setQuiet(minutes: 5, at: rig.now)
        XCTAssertEqual(triggers(rig.input(.tap)), [])
        XCTAssertEqual(triggers(rig.turn(40_000)), [])
        rig.core.setQuiet(minutes: 0, at: rig.now)
        rig.core.setFocus(true, at: rig.now)
        XCTAssertEqual(triggers(rig.input(.tap)), [])
        XCTAssertEqual(triggers(rig.core.talk("hi", at: rig.now)).count, 1)
    }

    func testTriggersInABurstMergeIntoOne() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.wait(600_000)
        let first = triggers(rig.send(.turnEnd, session: "a"))
        XCTAssertEqual(first.count, 1)
        rig.wait(500)
        XCTAssertEqual(triggers(rig.input(.tap)), [])
        XCTAssertEqual(triggers(rig.send(.turnFailed, session: "b")), [])
        let merged = triggers(rig.wait(3000))
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].line.hasPrefix("turn failed · claude · landing"), merged[0].line)
        XCTAssertTrue(merged[0].line.hasSuffix(" · +1 more"), merged[0].line)
        rig.wait(5000)
        XCTAssertEqual(triggers(rig.input(.tap)).count, 1, "a new window")
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
        XCTAssertEqual(s.jsonLine, #"{"t":"state","v":1,"time":1791986400,"name":"Pip","base":"working","attn":{"agent":"claude","project":"landing","more":0},"busy":2,"idle":1,"wait":1,"mood":{"energy":100,"pace":100,"pitch":100},"quiet":0,"focus":false,"vol":6,"night":false,"level":1,"prog":0,"days":1,"hungry":0,"threads":[["claude","landing","wait"],["codex","buddygotchi","work"],["claude","jetpack","work"],["claude","notes","idle"]]}"#)
        let data = Data(s.jsonLine.utf8)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
        XCTAssertLessThanOrEqual(data.count, 512)
    }

    func testAtMostEightThreadsAndAFullSnapshotFitsInOneLine() {
        let rig = CoreRig()
        for i in 0..<12 {
            rig.send(.turnStart, i % 2 == 0 ? .codex : .claudeCode, session: "s\(i)", project: "project-name-\(i)")
        }
        XCTAssertEqual(rig.state.threads.count, 7, "the eighth row doesn't fit in 512 bytes")
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
