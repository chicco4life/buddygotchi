import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

func events(_ fx: [CoreEffect]) -> [Event] { Eval.events(fx) }

/// The core's events for the harness (harness/EVENTS.md).
final class EventTests: XCTestCase {
    var rig = CoreRig()

    @discardableResult
    func hook(_ kind: BoopEvent.Kind, agent: Agent = .claudeCode, session: String = "s1", workspace: String? = "fix-nav",
              tool: String? = nil, topic: String? = nil, failed: Bool? = nil, done: Bool = false,
              toolError: String? = nil, id: String? = nil, error: String? = nil) -> [Event] {
        var detail = BoopEvent.Detail(tool: tool, topic: topic, error: error, failed: failed, toolError: toolError, toolUseID: id)
        detail.done = done
        return events(rig.core.handle(BoopEvent(agent: agent, session: session, project: "landing", workspace: workspace,
                                                event: kind, detail: detail, ts: rig.now)))
    }

    /// One test run: its `PreToolUse`, `ms` later its result.
    @discardableResult
    func tests(failed: Bool, after ms: Int64 = 40_000, id: String) -> [Event] {
        hook(.activity, tool: "Bash", topic: "tests", id: id)
        rig.wait(ms)
        return hook(.activity, tool: "Bash", topic: "tests", failed: failed, done: true,
                    toolError: failed ? "exit_code" : nil, id: id)
    }

    /// EVENTS.md §8: the tests-fail-then-pass turn, line by line, with the
    /// thread named after its workspace and its project. A repeat failure
    /// reads as the first did; streaks are left to the facts.
    func testATurnOfFailuresAndAComeback() throws {
        let start = hook(.turnStart)
        XCTAssertEqual(start.map(\.line), [#"claude started turn 1 on "fix-nav" (landing)."#])
        XCTAssertTrue(start[0].wakesBrain)

        XCTAssertEqual(tests(failed: true, id: "t1").map(\.line), [#"claude's tests failed on "fix-nav" (landing)."#])
        XCTAssertEqual(tests(failed: true, id: "t2").map(\.line),
                       [#"claude's tests failed on "fix-nav" (landing)."#])
        let third = try XCTUnwrap(tests(failed: true, id: "t3").first)
        XCTAssertEqual(third.line, #"claude's tests failed on "fix-nav" (landing)."#)
        XCTAssertEqual(third.facts["failed_before"], .int(2))
        XCTAssertEqual(third.facts["took"], "short", "40 s is short (EVENTS.md §5)")
        XCTAssertEqual(third.facts["took_ms"], .int(40_000))
        XCTAssertEqual(third.about, "claude_code/s1")

        XCTAssertEqual(tests(failed: false, id: "t4").map(\.line),
                       [#"claude's tests passed on "fix-nav" (landing) after failing."#])
        XCTAssertEqual(tests(failed: false, id: "t5"), [], "a pass with no failures before isn't notable")

        rig.wait(60_000)
        let end = try XCTUnwrap(hook(.turnEnd).first)
        XCTAssertEqual(end.line, #"claude finished turn 1 on "fix-nav" (landing): done, a long turn."#, "4 min is long")
        XCTAssertNil(end.reaction, "no rule cheers (BEHAVIORS.md §3.1)")
        XCTAssertEqual(end.facts["comeback"], "tests", "the facts keep what the line leaves out")
        XCTAssertEqual(end.facts["tools_failed"], .int(3))
        XCTAssertEqual(end.facts["outcome"], "done")
    }

    /// Routine tool uses are only counted, unless the personality asks for
    /// all of them (EVENTS.md §4).
    func testRoutineToolUsesAreCountedOrWithAllBecomeEvents() {
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Edit", done: true), [])
        rig.core.setRules(Personality.Rules(toolUses: .all))
        XCTAssertEqual(hook(.activity, tool: "Edit", failed: false, done: true).map(\.line),
                       [#"claude edited a file on "fix-nav" (landing)."#])
        XCTAssertEqual(hook(.activity, tool: "mcp__x__y", failed: true, done: true, toolError: "other").map(\.line),
                       [#"claude used a tool on "fix-nav" (landing). It failed."#])
        XCTAssertEqual(hook(.turnEnd).first!.facts["tools_failed"], .int(1), "counted in the facts, not the line")
    }

    /// Codex says nothing about failures, so its tool uses are `unknown`
    /// and never notable (EVENTS.md §4).
    func testCodexToolUsesAreUnknown() {
        hook(.turnStart, agent: .codex, session: "c1")
        XCTAssertEqual(hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true), [])
        rig.core.setRules(Personality.Rules(toolUses: .all))
        let e = hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true)
        XCTAssertEqual(e.first?.facts["result"], "unknown")
    }

    /// A failed check's error is in its facts, not its line (EVENTS.md §8).
    func testAToolErrorIsLeftOutOfTheLine() {
        hook(.turnStart)
        hook(.activity, tool: "Bash", topic: "build", id: "b")
        let failed = hook(.activity, tool: "Bash", topic: "build", failed: true, done: true, toolError: "timeout", id: "b")
        XCTAssertEqual(failed.map(\.line), [#"claude's build failed on "fix-nav" (landing)."#])
        XCTAssertEqual(failed.first?.facts["error"], "timeout")
    }

    /// A failed turn, a stopped one, and a very long one; turn starts say
    /// nothing of the gap; a thread with no workspace is named by its
    /// project. A turn end is its outcome and its length band, nothing else.
    func testTurnEnds() {
        hook(.turnStart, workspace: nil)
        rig.wait(5000)
        let failed = hook(.turnFailed, workspace: nil, error: "rate_limit").first
        XCTAssertEqual(failed?.line, #"claude finished turn 1 on "landing": failed, a short turn."#)
        XCTAssertEqual(failed?.facts["error"], "rate_limit")
        rig.wait(30_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 2 on "landing"."#)
        rig.wait(90_000)
        let stopped = hook(.turnStopped, workspace: nil, tool: "Bash")
        XCTAssertEqual(stopped.first?.line, #"claude finished turn 2 on "landing": stopped, a long turn."#)
        rig.wait(20 * 60_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 3 on "landing"."#)
        rig.wait(6 * 60_000)
        XCTAssertEqual(hook(.turnEnd, workspace: nil).first?.line, #"claude finished turn 3 on "landing": done, a very long turn."#)
    }

    /// EVENTS.md §6: nothing wakes the brain while something needs you, or
    /// with no brain; the events still come.
    func testGates() {
        hook(.turnStart)
        let asked = hook(.needsYou, tool: "Bash")
        XCTAssertEqual(asked.map(\.line), [#"claude needs you on "fix-nav" (landing)."#])
        XCTAssertFalse(asked[0].wakesBrain)
        XCTAssertFalse(hook(.turnStart, session: "s2").first!.wakesBrain, "something needs you")
        hook(.activity, tool: "Bash")
        XCTAssertTrue(hook(.turnStart, session: "s3").first!.wakesBrain)
        rig.core.setBrain(false)
        XCTAssertFalse(hook(.turnStart, session: "s4").first!.wakesBrain, "no key")
    }

    /// Taps and poke streaks (EVENTS.md §4, BEHAVIORS.md §3.3).
    func testTapsAndPokes() {
        let tap = events(rig.input(.tap))
        XCTAssertEqual(tap.map(\.line), ["You tapped Boop."])
        XCTAssertEqual(tap[0].reaction, "Boop wiggled on its own.")
        XCTAssertFalse(tap[0].wakesBrain)
        rig.wait(500); rig.input(.tap); rig.wait(500); rig.input(.tap); rig.wait(500)
        let pokes = events(rig.input(.tap))
        XCTAssertEqual(pokes.map(\.line), ["You poked Boop again and again."])
        XCTAssertEqual(pokes[0].facts["count"], .int(4))
        XCTAssertTrue(pokes[0].wakesBrain)
        for _ in 0..<4 { rig.wait(200); rig.input(.tap) }
        let again = events(rig.log).last!
        XCTAssertEqual(again.line, "You poked Boop again and again.", "no gap in the line")
        XCTAssertFalse(again.wakesBrain, "at most once a minute")
    }

    /// EVENTS.md §4: an hour with nothing happening, and no thread working,
    /// brings a heartbeat, and so does every hour after that. While a
    /// thread works, the working heartbeat comes instead.
    func testHeartbeats() {
        let idle = { (fx: [CoreEffect]) in events(fx).filter { $0.kind == .heartbeat && $0.facts["idle_hours"] != nil } }
        hook(.turnStart)
        rig.wait(50 * 60_000)
        XCTAssertEqual(idle(rig.log), [], "a thread was working")
        let working = events(rig.log).filter { $0.kind == .heartbeat }
        XCTAssertGreaterThan(working.count, 10, "the working heartbeat instead")
        XCTAssertTrue(working.allSatisfy { $0.line.hasPrefix(#"claude is still working on "fix-nav" (landing), a "#) && $0.wakesBrain })
        XCTAssertEqual(working.last?.line, #"claude is still working on "fix-nav" (landing), a very long turn."#)
        hook(.turnEnd)
        let beats = idle(rig.wait(2 * 60 * 60_000 + 1000))
        XCTAssertEqual(beats.map(\.line), ["Nothing has happened for 1 hour.", "Nothing has happened for 2 hours."])
        XCTAssertTrue(beats.allSatisfy(\.wakesBrain))
        rig.input(.tap)
        XCTAssertEqual(idle(rig.wait(59 * 60_000)), [], "a tap starts the hour again")
    }

    /// EVENTS.md §5's length band, at its edges: short under a minute,
    /// long under 5, very long from 5, as the moods read it.
    func testBands() {
        XCTAssertEqual(Band.length(ms: 59_999), "short")
        XCTAssertEqual(Band.length(ms: 60_000), "long")
        XCTAssertEqual(Band.length(ms: 299_999), "long")
        XCTAssertEqual(Band.length(ms: 300_000), "very long")
    }
}
