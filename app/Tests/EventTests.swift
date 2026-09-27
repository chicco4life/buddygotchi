import Foundation
import XCTest
@testable import BoopKit

func events(_ fx: [CoreEffect]) -> [Event] {
    fx.compactMap { if case .event(let e) = $0 { return e } else { return nil } }
}

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
    /// thread named after its workspace and its project.
    func testATurnOfFailuresAndAComeback() throws {
        let start = hook(.turnStart)
        XCTAssertEqual(start.map(\.line), [#"claude started turn 1 on "fix-nav" (landing)."#])
        XCTAssertTrue(start[0].wakesBrain)

        XCTAssertEqual(tests(failed: true, id: "t1").map(\.line), [#"claude's tests failed on "fix-nav" (landing)."#])
        XCTAssertEqual(tests(failed: true, id: "t2").map(\.line),
                       [#"claude's tests failed again on "fix-nav" (landing), 2 in a row."#])
        let third = try XCTUnwrap(tests(failed: true, id: "t3").first)
        XCTAssertEqual(third.line, #"claude's tests failed again on "fix-nav" (landing), 3 in a row."#)
        XCTAssertEqual(third.facts["failed_before"], .int(2))
        XCTAssertEqual(third.facts["took"], "long", "40 s is long (EVENTS.md §5)")
        XCTAssertEqual(third.facts["took_ms"], .int(40_000))
        XCTAssertEqual(third.about, "claude_code/s1")

        XCTAssertEqual(tests(failed: false, id: "t4").map(\.line),
                       [#"claude's tests passed on "fix-nav" (landing) after 3 failures in a row."#])
        XCTAssertEqual(tests(failed: false, id: "t5"), [], "a pass with no failures before isn't notable")

        rig.wait(60_000)
        let end = try XCTUnwrap(hook(.turnEnd).first)
        XCTAssertEqual(end.line, #"claude finished turn 1 on "fix-nav" (landing): done after 4 min, a very long turn, 5 tools (3 failed). Tests passing. A comeback on tests."#)
        XCTAssertEqual(end.reaction, "Boop cheered on its own.")
        XCTAssertEqual(end.facts["comeback"], "tests")
        XCTAssertEqual(end.facts["outcome"], "done")
    }

    /// Routine tool uses are only counted, unless the personality asks for
    /// all of them (EVENTS.md §4).
    func testRoutineToolUsesAreCountedOrWithAllBecomeEvents() {
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Edit", done: true), [])
        rig.core.setToolUses(.all)
        XCTAssertEqual(hook(.activity, tool: "Edit", failed: false, done: true).map(\.line),
                       [#"claude edited a file on "fix-nav" (landing)."#])
        XCTAssertEqual(hook(.activity, tool: "mcp__x__y", failed: true, done: true, toolError: "other").map(\.line),
                       [#"claude used a tool on "fix-nav" (landing). It failed."#])
        XCTAssertTrue(hook(.turnEnd).first!.line.contains("3 tools (1 failed)"))
    }

    /// Codex says nothing about failures, so its tool uses are `unknown`
    /// and never notable (EVENTS.md §4).
    func testCodexToolUsesAreUnknown() {
        hook(.turnStart, agent: .codex, session: "c1")
        XCTAssertEqual(hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true), [])
        rig.core.setToolUses(.all)
        let e = hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true)
        XCTAssertEqual(e.first?.facts["result"], "unknown")
    }

    /// A failed check's error other than an exit code is named (EVENTS.md §8).
    func testAToolErrorIsNamedInTheLine() {
        hook(.turnStart)
        hook(.activity, tool: "Bash", topic: "build", id: "b")
        XCTAssertEqual(hook(.activity, tool: "Bash", topic: "build", failed: true, done: true, toolError: "timeout", id: "b")
            .map(\.line), [#"claude's build failed on "fix-nav" (landing) (timed out)."#])
    }

    /// A turn's gap, a failed turn, a stopped one, and a thread with no
    /// workspace named by its project.
    func testTurnEndsAndGaps() {
        hook(.turnStart, workspace: nil)
        rig.wait(5000)
        XCTAssertEqual(hook(.turnFailed, workspace: nil, error: "rate_limit").first?.line,
                       #"claude finished turn 1 on "landing": failed (rate limit) after 5 s, a short turn, 0 tools."#)
        rig.wait(30_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 2 on "landing", right after its last one."#)
        rig.wait(3000)
        let stopped = hook(.turnStopped, workspace: nil, tool: "Bash")
        XCTAssertEqual(stopped.first?.facts["outcome"], "stopped")
        rig.wait(20 * 60_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 3 on "landing", a while after its last one."#)
    }

    /// EVENTS.md §6: nothing wakes the brain while something needs you, in
    /// quiet mode, or with no brain; the events still come.
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
        XCTAssertEqual(pokes.map(\.line), ["You poked Boop 4 times in 2 s."])
        XCTAssertTrue(pokes[0].wakesBrain)
        for _ in 0..<4 { rig.wait(200); rig.input(.tap) }
        let again = events(rig.log).last!
        XCTAssertEqual(again.line, "You poked Boop 4 times in 1 s, again right after the last time.")
        XCTAssertFalse(again.wakesBrain, "at most once a minute")
    }

    /// EVENTS.md §4: an hour with nothing happening, and no thread working,
    /// brings a heartbeat, and so does every hour after that.
    func testHeartbeats() {
        hook(.turnStart)
        rig.wait(50 * 60_000)
        XCTAssertEqual(events(rig.log).filter { $0.kind == .heartbeat }, [], "a thread was working")
        hook(.turnEnd)
        let beats = events(rig.wait(2 * 60 * 60_000 + 1000)).filter { $0.kind == .heartbeat }
        XCTAssertEqual(beats.map(\.line), ["Nothing has happened for 1 hour.", "Nothing has happened for 2 hours."])
        XCTAssertTrue(beats.allSatisfy(\.wakesBrain))
        rig.input(.tap)
        XCTAssertEqual(events(rig.wait(59 * 60_000)).filter { $0.kind == .heartbeat }, [], "a tap starts the hour again")
    }

    /// The status line lists the other threads working now (EVENTS.md §8).
    func testStatusLine() {
        hook(.turnStart)
        rig.wait(3 * 60_000)
        hook(.turnStart, agent: .codex, session: "c1", workspace: nil)
        XCTAssertEqual(rig.core.statusLine(excluding: "claude_code/s1", at: rig.now), #"Working now: "landing" (codex), for 0 s."#)
        XCTAssertEqual(rig.core.statusLine(excluding: "codex/c1", at: rig.now), #"Working now: "fix-nav" (claude, landing), for 3 min."#)
        hook(.turnEnd)
        XCTAssertEqual(rig.core.statusLine(excluding: "codex/c1", at: rig.now), "Working now: nothing else.")
    }

    /// EVENTS.md §5's bands, at their edges.
    func testBands() {
        XCTAssertEqual(Band.length(ms: 14_999), "short")
        XCTAssertEqual(Band.length(ms: 60_000), "long")
        XCTAssertEqual(Band.length(ms: 60_001), "very long")
        XCTAssertEqual(Band.gap(ms: 119_999), "right after")
        XCTAssertEqual(Band.gap(ms: 3_599_999), "a while")
        XCTAssertEqual(Band.gap(ms: 3_600_000), "a long break")
    }
}
