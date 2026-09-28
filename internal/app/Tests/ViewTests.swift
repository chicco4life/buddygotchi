import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The view: raw events folded into what the brain hears (harness/EVENTS.md).
final class ViewTests: XCTestCase {
    var rig = CoreRig()

    @discardableResult
    func hook(_ kind: Hook, agent: Agent = .claudeCode, session: String = "s1", workspace: String? = "fix-nav",
              tool: String? = nil, topic: String? = nil, failed: Bool? = nil, done: Bool = false,
              id: String? = nil, error: String? = nil, message: String? = nil, prompt: String? = nil) -> [ViewEvent] {
        events(rig.send(kind, agent, session: session, workspace: workspace, tool: tool, topic: topic, failed: failed,
                        id: id, done: done, error: error, message: message, prompt: prompt))
    }

    /// One test run: its `PreToolUse`, `ms` later its result.
    @discardableResult
    func tests(failed: Bool, after ms: Int64 = 40_000, id: String) -> [ViewEvent] {
        hook(.activity, tool: "Bash", topic: "tests", id: id)
        rig.wait(ms)
        return hook(.activity, tool: "Bash", topic: "tests", failed: failed, done: true, id: id, error: failed ? "exit_code" : nil)
    }

    /// EVENTS.md §8: the tests-fail-then-pass turn, line by line, with the
    /// thread named after its workspace and its project. A repeat failure
    /// reads as the first did; streaks are left to the facts.
    func testATurnOfFailuresAndAComeback() throws {
        let start = hook(.turnStart, prompt: "fix the nav\nplease")
        XCTAssertEqual(start.map(\.line), [#"claude started turn 1 on "fix-nav" (landing)."#])
        XCTAssertEqual(start.map(\.name), ["turn start"])
        XCTAssertEqual(start[0].notes, [#"You asked: "fix the nav please""#], "on one line")
        XCTAssertTrue(start[0].wakesBrain)

        XCTAssertEqual(tests(failed: true, id: "t1").map(\.line), [#"claude's tests failed on "fix-nav" (landing)."#])
        XCTAssertEqual(tests(failed: true, id: "t2").map(\.line),
                       [#"claude's tests failed on "fix-nav" (landing)."#])
        let third = try XCTUnwrap(tests(failed: true, id: "t3").first)
        XCTAssertEqual(third.name, "tool end")
        XCTAssertEqual(third.line, #"claude's tests failed on "fix-nav" (landing)."#)
        XCTAssertEqual(third.facts["failed_before"], .int(2))
        XCTAssertEqual(third.facts["took"], "short", "40 s is short (EVENTS.md §5)")
        XCTAssertEqual(third.facts["took_ms"], .int(40_000))
        XCTAssertEqual(third.about, "claude_code/s1")

        XCTAssertEqual(tests(failed: false, id: "t4").map(\.line),
                       [#"claude's tests passed on "fix-nav" (landing) after failing."#])
        XCTAssertEqual(tests(failed: false, id: "t5"), [], "a pass with no failures before isn't notable")

        rig.wait(60_000)
        let end = try XCTUnwrap(hook(.turnEnd, message: "All green now.").first)
        XCTAssertEqual(end.line, #"claude finished turn 1 on "fix-nav" (landing): done, a long turn, 5 tool calls."#,
                       "4 min is long; failed calls count the same")
        XCTAssertEqual(end.notes, [#"Its last message: "All green now.""#])
        XCTAssertTrue(end.did.isEmpty, "no rule cheers (BEHAVIORS.md §3.1)")
        XCTAssertEqual(end.facts["comeback"], "tests", "the facts keep what the line leaves out")
        XCTAssertEqual(end.facts["tools_failed"], .int(3))
        XCTAssertEqual(end.facts["outcome"], "done")
        XCTAssertEqual(end.facts["message"], "All green now.")
    }

    /// EVENTS.md §8: a long prompt or message is cut, on one line.
    func testLongWordsAreCut() {
        let long = String(repeating: "word ", count: 200)
        let note = EventLine.lastMessage(long)!
        XCTAssertEqual(note.count, "Its last message: \"\"".count + EventLine.messageMax)
        XCTAssertTrue(note.hasSuffix("…\""))
        XCTAssertNil(EventLine.prompt("  \n "))
        XCTAssertEqual(EventLine.turnEnd(agent: "claude", turn: 1, thread: "\"x\"", outcome: "done", lengthMs: 0, tools: 1),
                       #"claude finished turn 1 on "x": done, a short turn, 1 tool call."#)
        XCTAssertEqual(EventLine.turnEnd(agent: "claude", turn: 1, thread: "\"x\"", outcome: "done", lengthMs: 0, tools: 0),
                       #"claude finished turn 1 on "x": done, a short turn, no tool calls."#)
    }

    /// EVENTS.md §3: the keep rule is data. By default a tool call's start
    /// is read but not kept, its wait on you is, and its end only when
    /// notable; sessions and subagents are never kept.
    func testTheKeepRule() {
        XCTAssertTrue(Keep.standard.keeps(.turn, .start, notable: false))
        XCTAssertFalse(Keep.standard.keeps(.tool, .start, notable: true))
        XCTAssertTrue(Keep.standard.keeps(.tool, .wait, notable: false))
        XCTAssertFalse(Keep.standard.keeps(.tool, .end, notable: false))
        XCTAssertTrue(Keep.standard.keeps(.tool, .end, notable: true))
        XCTAssertFalse(Keep.standard.keeps(.session, .start, notable: true))
        XCTAssertFalse(Keep.standard.keeps(.subagent, .end, notable: true))
        XCTAssertTrue(Keep.of(Personality.Rules(toolUses: .all)).keeps(.tool, .end, notable: false))

        hook(.sessionStart)
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Bash", topic: "tests", id: "t"), [], "a start isn't kept")
        XCTAssertEqual(EventLine.toolStart(agent: "claude", category: "shell", topic: "tests", thread: #""landing""#),
                       #"claude started running tests on "landing"."#)
    }

    /// Routine tool uses are only counted, unless the personality asks for
    /// all of them (EVENTS.md §4).
    func testRoutineToolUsesAreCountedOrWithAllBecomeEvents() {
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Edit", done: true), [])
        rig.view.setRules(Personality.Rules(toolUses: .all))
        XCTAssertEqual(hook(.activity, tool: "Edit", failed: false, done: true).map(\.line),
                       [#"claude edited a file on "fix-nav" (landing)."#])
        XCTAssertEqual(hook(.activity, tool: "mcp__x__y", failed: true, done: true, error: "other").map(\.line),
                       [#"claude used a tool on "fix-nav" (landing). It failed."#])
        XCTAssertEqual(hook(.turnEnd).first!.facts["tools_failed"], .int(1), "counted in the facts, not the line")
    }

    /// Codex says nothing about failures, so its tool uses are `unknown`
    /// and never notable (EVENTS.md §4).
    func testCodexToolUsesAreUnknown() {
        hook(.turnStart, agent: .codex, session: "c1")
        XCTAssertEqual(hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true), [])
        rig.view.setRules(Personality.Rules(toolUses: .all))
        let e = hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true)
        XCTAssertEqual(e.first?.facts["result"], "unknown")
    }

    /// A failed check's error is in its facts, not its line (EVENTS.md §8).
    func testAToolErrorIsLeftOutOfTheLine() {
        hook(.turnStart)
        hook(.activity, tool: "Bash", topic: "build", id: "b")
        let failed = hook(.activity, tool: "Bash", topic: "build", failed: true, done: true, id: "b", error: "timeout")
        XCTAssertEqual(failed.map(\.line), [#"claude's build failed on "fix-nav" (landing)."#])
        XCTAssertEqual(failed.first?.facts["error"], "timeout")
    }

    /// A failed turn, a stopped one, and a very long one; turn starts say
    /// nothing of the gap; a thread with no workspace is named by its
    /// project.
    func testTurnEnds() {
        hook(.turnStart, workspace: nil)
        rig.wait(5000)
        let failed = hook(.turnFailed, workspace: nil, error: "rate_limit").first
        XCTAssertEqual(failed?.line, #"claude finished turn 1 on "landing": failed, a short turn, no tool calls."#)
        XCTAssertEqual(failed?.facts["error"], "rate_limit")
        rig.wait(30_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 2 on "landing"."#)
        rig.wait(90_000)
        let stopped = hook(.turnStopped, workspace: nil, tool: "Bash")
        XCTAssertEqual(stopped.first?.line, #"claude finished turn 2 on "landing": stopped, a long turn, no tool calls."#)
        rig.wait(20 * 60_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 3 on "landing"."#)
        rig.wait(6 * 60_000)
        XCTAssertEqual(hook(.turnEnd, workspace: nil).first?.line,
                       #"claude finished turn 3 on "landing": done, a very long turn, no tool calls."#)
    }

    /// EVENTS.md §6: nothing but a poke wakes the brain while something
    /// needs you, and nothing with no brain; the view events still come.
    /// "Needs you" is kept as the tool call's wait, from the core's action.
    func testGates() {
        hook(.turnStart)
        let asked = hook(.needsYou, tool: "Bash")
        XCTAssertEqual(asked.map(\.line), [#"claude needs you on "fix-nav" (landing)."#])
        XCTAssertEqual(asked.map(\.name), ["tool wait"])
        XCTAssertFalse(asked[0].wakesBrain)
        XCTAssertEqual(rig.ruleActions, ["needs_you start"])
        XCTAssertFalse(hook(.turnStart, session: "s2").first!.wakesBrain, "something needs you")
        XCTAssertTrue(events(rig.poke()).first!.wakesBrain, "a poke wakes it even so")
        hook(.activity, tool: "Bash")
        XCTAssertEqual(rig.ruleActions, ["needs_you start", "needs_you end"], "answered")
        XCTAssertTrue(hook(.turnStart, session: "s3").first!.wakesBrain)
        rig.pipeline.brain = false
        XCTAssertFalse(hook(.turnStart, session: "s4").first!.wakesBrain, "no key")
        XCTAssertFalse(events(rig.poke()).first!.wakesBrain, "no key, not even a poke")
    }

    /// Pokes (EVENTS.md §4, BEHAVIORS.md §3.3): every one wakes the brain,
    /// counted in a row, and its wiggle goes under it.
    func testPokes() {
        let one = events(rig.poke())
        XCTAssertEqual(one.map(\.line), ["You poked Boop."])
        XCTAssertEqual(one.map(\.name), ["poke"])
        XCTAssertTrue(one[0].wakesBrain)
        XCTAssertEqual(rig.view.event(one[0].id)?.did.map(\.message), ["Boop wiggled on its own."])
        XCTAssertEqual(rig.view.event(one[0].id)?.did.map(\.by), ["rule"])
        var last: [ViewEvent] = []
        for _ in 0..<3 { rig.wait(1000); last = events(rig.poke()) }
        XCTAssertEqual(last.map(\.line), ["You poked Boop 4 times in a row."])
        XCTAssertEqual(last[0].facts["in_a_row"], .int(4))
        XCTAssertTrue(last[0].wakesBrain, "no limit")
        rig.wait(3000)
        XCTAssertEqual(events(rig.poke()).map(\.line), ["You poked Boop."], "3 s apart starts again")
        // While something needs you there's no wiggle.
        hook(.turnStart)
        hook(.needsYou, tool: "Bash")
        let seen = events(rig.poke())
        XCTAssertEqual(rig.view.event(seen[0].id)?.did, [])
    }

    /// What you say to Boop (EVENTS.md §4, §8): one line, quoted and cut to
    /// 300 characters like your prompt, that always wakes the brain, even
    /// while something needs you. The raw event keeps 2,000 characters, and
    /// words that are only space make no view event.
    func testWhatYouSay() throws {
        let said = events(rig.said("are the tests\npassing yet?"))
        XCTAssertEqual(said.map(\.line), [#"You said to Boop: "are the tests passing yet?""#])
        XCTAssertEqual(said.map(\.name), ["talk"])
        XCTAssertTrue(said[0].wakesBrain)
        XCTAssertNil(said[0].about)
        XCTAssertEqual(said[0].facts["words"], "are the tests\npassing yet?")
        XCTAssertEqual(said[0].facts["by"], "device")
        let raw = try XCTUnwrap(rig.pipeline.transcript.events.last)
        XCTAssertEqual(raw.source, .mic)
        XCTAssertEqual(raw.type, .talk)
        XCTAssertEqual(raw.specificType, "device")

        let long = try XCTUnwrap(events(rig.said(String(repeating: "a", count: 2500), by: .app)).first)
        XCTAssertEqual(long.line.count, #"You said to Boop: """#.count + EventLine.messageMax)
        XCTAssertTrue(long.line.hasSuffix(#"…""#))
        XCTAssertEqual(rig.pipeline.transcript.events.last?["words"]?.string?.count, 2000)
        XCTAssertEqual(long.facts["by"], "app")

        XCTAssertEqual(events(rig.said(" \n ")), [])

        hook(.turnStart)
        hook(.needsYou, tool: "Bash")
        XCTAssertEqual(events(rig.said("ok")).map(\.wakesBrain), [true], "even while something needs you")
    }

    /// EVENTS.md §7: a reaction a tap cut short stays in progress while
    /// the pokes go on (3 s apart at most), so the barrage gets it once;
    /// it reads as done once they stop, or once anything else happens.
    func testAReactionATapCutStaysInProgressWhileThePokesGoOn() {
        func react(to poke: ViewEvent) -> Int {
            rig.pipeline.record(Event(ts: rig.now, source: .boop, type: .action, phase: .start, specificType: "react",
                                      data: ["for": .int(Int64(poke.seq)), "by": "brain", "ok": true,
                                             "message": "Boop made a grumpy face."])).seq
        }
        func cut(_ seq: Int) {
            rig.pipeline.record(Event(ts: rig.now, source: .boop, type: .action, phase: .end, specificType: "react",
                                      data: ["for": .int(Int64(seq)), "by": "brain", "outcome": "failed",
                                             "why": .string(TranscriptView.cutByTap)]))
        }
        func state(_ poke: ViewEvent) -> [ViewEvent.Did.State] {
            rig.view.event(poke.id)!.did.filter { $0.by == "brain" }.map(\.state)
        }
        let first = events(rig.poke())[0]
        cut(react(to: first))
        rig.wait(2900)
        _ = rig.poke()
        XCTAssertEqual(state(first), [.inProgress], "the pokes go on")
        rig.wait(3000)
        _ = rig.poke()
        XCTAssertEqual(state(first), [.done], "3 s apart is a new run")

        let again = events(rig.poke())[0]
        cut(react(to: again))
        hook(.turnStart)
        XCTAssertEqual(state(again), [.done], "something else happened")

        rig.wait(1000)
        let other = events(rig.poke())[0]
        rig.pipeline.record(Event(ts: rig.now, source: .boop, type: .action, phase: .end, specificType: "react",
                                  data: ["for": .int(Int64(react(to: other))), "by": "brain", "outcome": "failed",
                                         "why": "cut short: something newer played"]))
        XCTAssertEqual(state(other), [], "any other cut is gone")
    }

    /// EVENTS.md §6: a poke doesn't wake the brain while the brain's
    /// reaction to its run's pokes in a row, from the third
    /// (`answersRunFrom`), is in progress, a tap-cut one included, unless
    /// the mood changed since it started. The first two pokes' reactions
    /// don't count, and a new run (3 s apart) wakes it.
    func testAPokeWaitsWhileItsRunIsBeingAnswered() {
        func react(to poke: ViewEvent, _ name: String = "react", started: Bool = true) -> Int {
            rig.pipeline.record(Event(ts: rig.now, source: .boop, type: .action, phase: started ? .start : nil,
                                      specificType: name, data: ["for": .int(Int64(poke.seq)), "by": "brain", "ok": true,
                                                                 "message": "Boop did it."])).seq
        }
        func end(_ seq: Int, _ why: String? = nil) {
            rig.pipeline.record(Event(ts: rig.now, source: .boop, type: .action, phase: .end, specificType: "react",
                                      data: ["for": .int(Int64(seq)), "by": "brain", "outcome": why == nil ? "done" : "failed",
                                             "why": why.map { .string($0) } ?? .null]))
        }
        let answering = "Boop is answering these pokes"
        let single = events(rig.poke())[0]
        XCTAssertTrue(single.wakesBrain)
        end(react(to: single), TranscriptView.cutByTap)
        rig.wait(500)
        let second = events(rig.poke())[0]
        XCTAssertTrue(second.wakesBrain, "a single poke's reaction doesn't answer the run")
        end(react(to: second), TranscriptView.cutByTap)
        rig.wait(500)
        let third = events(rig.poke())[0]
        XCTAssertEqual(third.facts["in_a_row"], .int(3))
        XCTAssertTrue(third.wakesBrain, "nor does two pokes' reaction")
        let happy = react(to: third)
        rig.wait(500)
        var next = events(rig.poke())[0]
        XCTAssertFalse(next.wakesBrain, "three pokes' reaction is playing")
        XCTAssertEqual(rig.pipeline.whyNotWake(next), answering)
        end(happy, TranscriptView.cutByTap)
        rig.wait(500)
        next = events(rig.poke())[0]
        XCTAssertFalse(next.wakesBrain, "cut short by a tap, it's still in progress")

        _ = react(to: next, MoodAction.actionName, started: false)
        rig.wait(500)
        next = events(rig.poke())[0]
        XCTAssertTrue(next.wakesBrain, "the mood changed since")
        let grumpy = react(to: next)
        rig.wait(500)
        XCTAssertFalse(events(rig.poke())[0].wakesBrain, "the new reaction answers the run")
        end(grumpy)
        rig.wait(500)
        XCTAssertTrue(events(rig.poke())[0].wakesBrain, "it played out")

        let last = events(rig.poke())[0]
        end(react(to: last), TranscriptView.cutByTap)
        rig.wait(2900)
        XCTAssertFalse(events(rig.poke())[0].wakesBrain, "within 3 s, the same run")
        rig.wait(3000)
        XCTAssertTrue(events(rig.poke())[0].wakesBrain, "3 s apart is a new run")
    }

    /// EVENTS.md §4: an hour with nothing happening, and no thread working,
    /// brings a heartbeat, and so does every hour after that. While a
    /// thread works, the working heartbeat comes instead.
    func testHeartbeats() {
        let idle = { (views: [ViewEvent]) in views.filter { $0.type == .heartbeat && $0.facts["idle_hours"] != nil } }
        hook(.turnStart)
        rig.wait(50 * 60_000)
        XCTAssertEqual(idle(rig.views), [], "a thread was working")
        let working = rig.views.filter { $0.type == .heartbeat }
        XCTAssertGreaterThan(working.count, 10, "the working heartbeat instead")
        XCTAssertTrue(working.allSatisfy { $0.line.hasPrefix(#"claude is still working on "fix-nav" (landing), a "#) && $0.wakesBrain })
        XCTAssertEqual(working.last?.line, #"claude is still working on "fix-nav" (landing), a very long turn."#)
        hook(.turnEnd)
        let beats = idle(events(rig.wait(2 * 60 * 60_000 + 1000)))
        XCTAssertEqual(beats.map(\.line), ["Nothing has happened for 1 hour.", "Nothing has happened for 2 hours."])
        XCTAssertTrue(beats.allSatisfy(\.wakesBrain))
        rig.poke()
        XCTAssertEqual(idle(events(rig.wait(59 * 60_000))), [], "a poke starts the hour again")
    }

    /// EVENTS.md §5's length band, at its edges: short under a minute,
    /// long under 5, very long from 5, as the moods read it.
    func testBands() {
        XCTAssertEqual(Band.length(ms: 59_999), "short")
        XCTAssertEqual(Band.length(ms: 60_000), "long")
        XCTAssertEqual(Band.length(ms: 299_999), "long")
        XCTAssertEqual(Band.length(ms: 300_000), "very long")
    }

    /// HARNESS.md §5: the transcript keeps a file a day, reads the last two
    /// back, and a fresh view folded from them says what the old one did:
    /// turn numbers go on across a restart. An action left in progress is
    /// ended as failed; older files are deleted.
    func testTheTranscriptPersistsAndReplays() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-tr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time)), transcript: Transcript(folder: dir, time: time), view: TranscriptView())
        }
        let first = pipeline()
        rig = CoreRig()
        first.agent(rig.event(.turnStart))
        let start = first.record(Event(ts: rig.now, source: .boop, type: .action, phase: .start, specificType: "react",
                                       data: ["for": 1, "by": "brain", "ok": true, "message": "Boop smiled."]))
        XCTAssertEqual(start.seq, 2)
        first.agent(rig.event(.turnEnd))
        let old = dir.appendingPathComponent("2026-09-01.jsonl")
        try "{}\n".write(to: old, atomically: true, encoding: .utf8)

        let file = dir.appendingPathComponent(time.day(rig.now) + ".jsonl")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix(#"{"seq":1,"ts":"#), String(lines[0]))
        try (String(contentsOf: file, encoding: .utf8) + #"{"seq":4,"ts":"#).write(to: file, atomically: true, encoding: .utf8)

        let second = pipeline()
        let loaded = second.transcript.load(now: rig.now)
        XCTAssertEqual(loaded.map(\.seq), [1, 2, 3], "the torn line is skipped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "past 14 days")
        second.replay(loaded, now: rig.now)
        XCTAssertEqual(second.transcript.events.last?.data["why"], "Boop restarted")
        XCTAssertEqual(second.transcript.events.last?.seq, 4, "seq goes on")
        XCTAssertEqual(second.view.events.first?.did, [], "a reaction that can't end now isn't shown")
        rig.wait(1000)
        let next = second.agent(rig.event(.turnStart)).views
        XCTAssertEqual(next.map(\.line), [#"claude started turn 2 on "landing"."#])
    }
}
