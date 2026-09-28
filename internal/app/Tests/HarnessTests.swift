import Foundation
import XCTest
@testable import BoopKit

/// The harness, its state text, the actions and Jev's wire format
/// (harness/HARNESS.md, harness/DECISIONS.md).
let harnessT0: Int64 = 1_790_000_000_000

/// An action that records the answers it gets. Not nested in a test: the
/// shim's runner generator would take it for the test class.
final class Recorder: Action {
    let name: String
    let keys: [String]
    var got: [Answers] = []
    var result: ActionResult?
    init(_ name: String, keys: [String], result: ActionResult?) {
        self.name = name
        self.keys = keys
        self.result = result
    }
    func questions() -> [Question] {
        keys.map { Question(key: $0, text: "?", about: "the NOW section", judgeBy: "x", options: [Option("a", "A"), Option("b", "B")]) }
    }
    func run(_ answers: Answers) -> ActionResult? {
        got.append(answers)
        return result
    }
}

struct SlowBrain: Brain {
    let id = "slow"
    let ms: Int
    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try await Task.sleep(for: .milliseconds(ms))
        return [:]
    }
}

final class HarnessTests: XCTestCase {
    static var t0: Int64 { harnessT0 }

    static let parts = StateText.Parts(guide: "You are the mind of Boop.", personality: "PERSONALITY\nCurious.",
                                       mood: "MOOD\nHappy.", closing: "Boop has been grumpy for 2 min.",
                                       workingSince: nil, clock: "14:23, Tuesday")

    static func pipeline() -> Pipeline {
        Pipeline(core: Core(config: .init(time: LocalTime(timeZone: TimeZone(identifier: "UTC")!))), view: TranscriptView())
    }

    /// A view event with any line, `minutes` after `t0`: a raw event the
    /// view reads nothing from, kept with that line.
    @discardableResult
    static func happen(_ p: Pipeline, at minutes: Int64, _ line: String, notes: [String] = [], wakes: Bool = true) -> ViewEvent {
        let e = p.record(Event(ts: t0 + minutes * 60_000, source: .claude, type: .turn, phase: .start, specificType: "test"))
        p.view.add(e, line: line, notes: notes, wakes: wakes)
        return p.view.events.last!
    }

    /// An action about the view event `about`, as the harness records one.
    @discardableResult
    static func did(_ p: Pipeline, _ about: ViewEvent?, _ message: String, name: String = "react", ok: Bool = true,
                    started: Bool = false, by: String = "brain") -> Event {
        p.record(Event(ts: t0, source: .boop, type: .action, phase: started ? .start : nil, specificType: name,
                       data: ["for": about.map { .int(Int64($0.seq)) } ?? .null, "by": .string(by), "ok": .bool(ok),
                              "message": .string(message)]))
    }

    /// harness/HARNESS.md §5.3: HISTORY and NOW, built step by step from
    /// the view: oldest first, relative times, notes then what Boop did
    /// indented under what it answered (rule actions and the brain's, in
    /// order), failed actions left out.
    func testTheTextFormFollowsTheSteps() {
        let p = Self.pipeline()
        let start = Self.happen(p, at: 5, #"claude started turn 7 on "fix-nav" (landing)."#, notes: [#"You asked: "fix the nav""#])
        let failed = Self.happen(p, at: 14, #"claude's tests failed on "fix-nav" (landing)."#)
        Self.did(p, failed, #"Boop made a grumpy face and mumbled "…tests!""#)
        Self.did(p, failed, "couldn't save the mood: disk full", name: "mood", ok: false)
        let poke = Self.happen(p, at: 19, "You poked Boop.")
        Self.did(p, poke, "Boop wiggled on its own.", name: "wiggle", by: "rule")
        let end = Self.happen(p, at: 23, #"claude finished turn 7 on "fix-nav" (landing): done, a very long turn, 12 tool calls."#,
                              notes: [#"Its last message: "Done.""#])
        _ = start
        var parts = Self.parts
        parts.workingSince = Self.t0 + 5 * 60_000  // the turn is still working, so HISTORY reaches back to its start
        let state = StateText.build(p.view.events, now: p.view.event(end.id)!, at: Self.t0 + 23 * 60_000 + 5000, parts)
        XCTAssertEqual(state, """
            You are the mind of Boop.
            \(StateText.reading)
            \(EventLine.words)

            PERSONALITY
            Curious.

            MOOD
            Happy.

            HISTORY (oldest first; indented lines add to the line above)
            18 min ago: claude started turn 7 on "fix-nav" (landing).
              You asked: "fix the nav"
            9 min ago: claude's tests failed on "fix-nav" (landing).
              Boop made a grumpy face and mumbled "…tests!"
            4 min ago: You poked Boop.
              Boop wiggled on its own.
            Boop has been grumpy for 2 min.

            NOW (14:23, Tuesday)
            claude finished turn 7 on "fix-nav" (landing): done, a very long turn, 12 tool calls.
              Its last message: "Done."
            Boop did nothing on its own.
            """)
        let poked = StateText.nowSection(p.view.event(poke.id)!, clock: "c")
        XCTAssertEqual(poked, "NOW (c)\nYou poked Boop.\nBoop wiggled on its own.", "a rule's action is NOW's last line")
    }

    /// §5.3: HISTORY reaches back 10 minutes, or to the oldest working
    /// turn, whichever is further, and holds at most 40 events.
    func testHistoryReachesBackTenMinutesOrToTheOldestWorkingTurn() {
        XCTAssertEqual(StateText.historyMs, 600_000)
        XCTAssertEqual(StateText.historyLimit, 40)
        let p = Self.pipeline()
        Self.happen(p, at: 0, "old")
        for i in 1...50 { Self.happen(p, at: 20, "poke \(i)", wakes: false) }
        let now = Self.happen(p, at: 21, "now")
        let recent = StateText.history(p.view.events, now: now, at: Self.t0 + 21 * 60_000, closing: "s", workingSince: nil)
        XCTAssertFalse(recent.contains(": old"), "21 minutes ago is past the 10")
        XCTAssertEqual(recent.split(separator: "\n").count, 1 + 40 + 1, "a heading, 40 events, the closing line")
        XCTAssertTrue(recent.contains("poke 50") && !recent.contains("poke 10\n"), "the newest 40")
        let working = StateText.history(p.view.events, now: now, at: Self.t0 + 21 * 60_000, closing: "s", workingSince: Self.t0)
        XCTAssertTrue(working.contains("21 min ago: old") || !working.contains("poke 1\n"), "the working turn's start counts, within the 40")
        XCTAssertEqual(StateText.ago(59_999), "just now")
        XCTAssertEqual(StateText.ago(9 * 60_000), "9 min ago")
        XCTAssertEqual(StateText.ago(2 * 3_600_000 + 5), "2 h ago")
    }

    /// §5.3 step 2: a view event whose started action is still in progress
    /// stays in HISTORY past the newest 40, so a pass still sees the face
    /// Boop is making. With chatter's `tool_uses: all`, 40 routine calls
    /// can land during one face held four times, and the reaction dropped
    /// out of HISTORY: Jev could call for the same face again
    /// (harness/DECISIONS.md §5, react's `none`).
    func testAReactionInProgressStaysInHistory() {
        let p = Self.pipeline()
        let failed = Self.happen(p, at: 20, "tests failed")
        Self.did(p, failed, "Boop made a proud face.", started: true)
        let done = Self.happen(p, at: 20, "tests failed again")
        Self.did(p, done, "Boop mumbled.")
        for i in 1...45 { Self.happen(p, at: 20, "read \(i)") }
        let now = Self.happen(p, at: 20, "now")
        let history = StateText.history(p.view.events, now: now, at: now.ts + 30_000, closing: "s", workingSince: nil)
        let lines = history.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "just now: tests failed", "the oldest, kept for its reaction")
        XCTAssertEqual(lines[2], "  Boop made a proud face. (in progress)")
        XCTAssertEqual(lines[3], "just now: read 6", "then the newest 40")
        XCTAssertFalse(history.contains("tests failed again"), "a finished one isn't kept")
        XCTAssertEqual(lines.count, 1 + 2 + 40 + 1)
    }

    // MARK: The harness

    func harness(_ brain: (any Brain)?, _ actions: [any Action], log: @escaping (String) -> Void = { _ in })
        -> (Harness, DispatchQueue) {
        let home = DispatchQueue(label: "test.home")
        let h = Harness(brain: brain, actions: actions, pipeline: Self.pipeline(), parts: { _ in Self.parts }, home: home,
                        clock: { harnessT0 }, log: log)
        return (h, home)
    }

    /// A view event with `line` in the harness's view.
    func event(_ h: Harness, _ home: DispatchQueue, at minutes: Int64 = 0, _ line: String, wakes: Bool = true) -> ViewEvent {
        home.sync { Self.happen(h.pipeline, at: minutes, line, wakes: wakes) }
    }

    /// The actions recorded, as `name phase: for`.
    func actions(_ h: Harness, _ home: DispatchQueue) -> [Event] {
        home.sync { h.pipeline.transcript.events.filter { $0.type == .action } }
    }

    /// HARNESS.md §2–4: one request with every action's questions; each
    /// action gets only its own answers, in order; a nil result records
    /// nothing, and every result is recorded as an action for its view
    /// event's raw event.
    func testAPassAsksEveryQuestionAndHandsEachActionItsOwn() async throws {
        let seen = Lines()
        let brain = ScriptedBrain { state, questions in
            seen.add(questions.map(\.key).joined(separator: ","))
            XCTAssertTrue(state.hasSuffix("NOW (14:23, Tuesday)\nit happened\nBoop did nothing on its own."))
            return ["one": Answer(choice: "a"), "two": Answer(choice: "b"), "three": Answer(choice: "a")]
        }
        let first = Recorder("first", keys: ["one", "two"], result: .done("Boop did one."))
        let second = Recorder("second", keys: ["three"], result: nil)
        let (h, home) = harness(brain, [first, second])
        let now = event(h, home, "it happened")
        let recordResult = await h.respond(to: now)
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(seen.all, ["one,two,three"], "one request")
        XCTAssertEqual(first.got, [["one": Answer(choice: "a"), "two": Answer(choice: "b")]])
        XCTAssertEqual(second.got, [["three": Answer(choice: "a")]])
        XCTAssertEqual(record.actions.map(\.name), ["first"], "nil is nothing to record")
        XCTAssertEqual(record.logLine, "brain turn start \(record.pass.latencyMs) ms → first")
        let recorded = actions(h, home)
        XCTAssertEqual(recorded.count, 1, "one action; the pass isn't in the transcript")
        XCTAssertEqual(recorded.first?["for"], .int(Int64(now.seq)))
        XCTAssertEqual(recorded.first?["by"], "brain")
        XCTAssertEqual(recorded.first?.specificType, "first")
        XCTAssertNil(recorded.first?.phase, "done at once")
    }

    /// EVENTS.md §6, DECISIONS.md §4: a poke's pass asks the mood question
    /// like any other, so it can make Boop grumpy.
    func testAPokeCanMakeBoopGrumpy() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-mood-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MoodStore(stateDir: dir)
        let seen = Lines()
        let brain = ScriptedBrain { _, questions in
            seen.add(questions.map(\.key).joined(separator: ","))
            return ["mood": Answer(choice: "grumpy")]
        }
        let (h, home) = harness(brain, [MoodAction(store: store)])
        let poke = try XCTUnwrap(home.sync { h.pipeline.poke(at: Self.t0).views.first })
        XCTAssertEqual(poke.name, "poke")
        let pass = await h.respond(to: poke)
        let poked = try XCTUnwrap(pass)
        XCTAssertEqual(seen.all, ["mood"], "the mood question is asked")
        XCTAssertEqual(poked.actions.map(\.name), ["mood"])
        XCTAssertEqual(store.current, "grumpy")
    }

    /// A view event that doesn't wake the brain, or no brain, gets no pass;
    /// a brain that fails drops the pass and runs no action.
    func testNoPassWithoutWakingOrABrainAndNoActionWhenItFails() async throws {
        let a = Recorder("a", keys: ["k"], result: .done("x"))
        let (h, home) = harness(ScriptedBrain(always: [:]), [a])
        let quiet = await h.respond(to: event(h, home, "needs you", wakes: false))
        XCTAssertNil(quiet)
        let (none, noneHome) = harness(nil, [a])
        let nothing = await none.respond(to: event(none, noneHome, "x"))
        XCTAssertNil(nothing)
        let (broken, brokenHome) = harness(ScriptedBrain { _, _ in throw BrainError("jev: HTTP 500") }, [a])
        let recordResult = await broken.respond(to: event(broken, brokenHome, "x"))
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(record.pass.dropped, "jev: HTTP 500")
        XCTAssertEqual(record.actions, [])
        XCTAssertEqual(a.got.count, 0)
        XCTAssertEqual(record.logLine, "brain turn start \(record.pass.latencyMs) ms → dropped: jev: HTTP 500")
    }

    /// HARNESS.md §7: the popover says Jev isn't answering at once for a
    /// status only the person can fix (401, 402, 403), and for anything
    /// else after 3 dropped passes in a row. A pass that runs clears it, a
    /// pass that never asked Jev doesn't count, and a new key starts over.
    func testBrainTroubleShowsAtOnceForTheAccountAndAfterThreeInARowElse() async throws {
        XCTAssertEqual(BrainTrouble.showAfter, 3)
        let fail = Lines()
        let brain = ScriptedBrain { _, _ in
            guard let status = fail.all.last.flatMap(Int.init) else { return [:] }
            throw BrainError("jev: HTTP \(status)", status: status)
        }
        let (h, home) = harness(brain, [Recorder("a", keys: ["k"], result: .done("x"))])
        func pass(_ status: Int?) async -> BrainTrouble? {
            fail.add(status.map(String.init) ?? "ok")
            _ = await h.respond(to: event(h, home, "x"))
            return home.sync { h.trouble }
        }
        let credit = await pass(402)
        XCTAssertEqual(credit, BrainTrouble(kind: .credit, why: "jev: HTTP 402", inARow: 1))
        let ok = await pass(nil)
        XCTAssertNil(ok)
        let key = await pass(401)
        XCTAssertEqual(key?.kind, .key)
        _ = await pass(nil)
        let first = await pass(503)
        let second = await pass(503)
        let third = await pass(503)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(third, BrainTrouble(kind: .failing, why: "jev: HTTP 503", inARow: 3))
        // A waiting pass that never asked Jev leaves it as it was.
        let waited = event(h, home, "x")
        home.sync { h.finish(waited, nil, .failure(BrainError("something needs you")), latencyMs: 0) }
        XCTAssertEqual(home.sync { h.trouble }?.inARow, 3)
        home.sync { h.use(brain) }
        XCTAssertNil(home.sync { h.trouble })
    }

    /// HARNESS.md §7: a pass that runs past 1.5 s is dropped.
    func testALateAnswerIsDropped() async throws {
        XCTAssertEqual(Harness.deadlineMs, 1500)
        let (h, home) = harness(SlowBrain(ms: 3000), [Recorder("a", keys: ["k"], result: .done("x"))])
        let recordResult = await h.respond(to: event(h, home, "x"))
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(record.pass.dropped, "late: no answer within 1500 ms")
    }

    /// HARNESS.md §7: the deadline cuts a pass off at 1.5 s. Its timer
    /// had the system's default leeway, so it fired up to 7% late: an
    /// answer just past it was kept or dropped by chance, and every dropped
    /// pass logged the timer's time as the brain's.
    func testTheDeadlineComesOnTime() async {
        let ms = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let started = ContinuousClock.now
                    _ = await Harness.race(Harness.deadlineMs) { () async throws -> Int in
                        try await Task.sleep(for: .seconds(3))
                        return 0
                    }
                    return (ContinuousClock.now - started).ms
                }
            }
            var all: [Int] = []
            for await one in group { all.append(one) }
            return all
        }
        XCTAssertLessThan(ms.max() ?? 0, Harness.deadlineMs + 40, "\(ms)")
    }

    /// HARNESS.md §7: a request the deadline passed goes on to its end,
    /// off the pass, so the app log says when the brain did answer: the
    /// pass's latency is the deadline's, and says nothing about the brain.
    /// Its answer is still thrown away.
    func testALateAnswerIsStillTimed() async throws {
        let late = Lines()
        let result = await Harness.race(100, late: { ms, result in
            late.add("\(ms / 100) \((try? result.get()) ?? -1)")
        }) { () async throws -> Int in
            try await Task.sleep(for: .milliseconds(300))
            return 7
        }
        guard case .failure(let error) = result else {
            XCTFail("\(result)")
            return
        }
        XCTAssertEqual(error.description, "late: no answer within 100 ms")
        eventually("the answer, when it came") { late.all == ["3 7"] }

        let logged = Lines()
        let (h, home) = harness(SlowBrain(ms: 1700), [Recorder("a", keys: ["k"], result: .done("x"))], log: { logged.add($0) })
        let now = event(h, home, "x")
        home.sync { h.take([now]) }
        eventually("the late answer's line", timeout: 4) {
            logged.all.contains { line in
                line.hasPrefix("harness: slow answered after ")
                    && (Int(line.dropFirst(29).prefix { $0.isNumber }).map { $0 >= 1700 } ?? false)
            }
        }
        XCTAssertTrue(logged.all.contains { $0.hasSuffix("dropped: late: no answer within 1500 ms") }, "\(logged.all)")
    }

    /// HARNESS.md §2: one pass runs at a time, and a newer view event
    /// replaces one that's waiting; the replaced one is still in the view.
    func testOnePassAtATimeAndTheNewestWaits() throws {
        let seen = Lines()
        let gate = DispatchSemaphore(value: 0)
        let brain = ScriptedBrain { state, _ in
            seen.add(String(state.split(separator: "\n").reversed()[1]))
            if seen.all.count == 1 { gate.wait() }
            return [:]
        }
        let (h, home) = harness(brain, [Recorder("a", keys: ["k"], result: nil)])
        var records: [Harness.Record] = []
        let views = ["first", "second", "third"].map { event(h, home, $0) }
        home.sync {
            h.onRecord = { records.append($0) }
            for v in views { h.take([v]) }
        }
        Thread.sleep(forTimeInterval: 0.1)
        gate.signal()
        eventually("two passes") { home.sync { records.count } >= 2 }
        XCTAssertEqual(seen.all, ["first", "third"], "second was replaced while it waited")
        home.sync {
            XCTAssertTrue(h.idle)
            XCTAssertEqual(h.pipeline.view.events.count, 3)
        }
    }

    /// HARNESS.md §2, EVENTS.md §6: no view event but a poke wakes the brain
    /// while something needs you. One that woke it before, and waited
    /// behind a running pass, doesn't start its pass once something needs
    /// you: it's logged as a pass dropped for that. Before, it asked Jev
    /// with the amber showing, and its mood answer changed the face of the
    /// request on screen.
    func testAWaitingPassDoesntStartWhileSomethingNeedsYou() throws {
        let seen = Lines()
        let gate = DispatchSemaphore(value: 0)
        let brain = ScriptedBrain { state, _ in
            seen.add(String(state.split(separator: "\n").reversed()[1]))
            gate.wait()
            return [:]
        }
        let (h, home) = harness(brain, [Recorder("a", keys: ["k"], result: nil)])
        var needsYou = false
        var records: [Harness.Record] = []
        let first = event(h, home, "first"), second = event(h, home, "second")
        home.sync {
            h.whyNotStart = { _ in needsYou ? "something needs you" : nil }
            h.onRecord = { records.append($0) }
            h.take([first])
            h.take([second])
            needsYou = true
        }
        gate.signal()
        eventually("both recorded") { home.sync { records.count } == 2 }
        XCTAssertEqual(seen.all, ["first"], "no request for the second")
        XCTAssertEqual(records.last?.pass.dropped, "something needs you")
        XCTAssertEqual(records.last?.logLine, "brain turn start 0 ms → dropped: something needs you")
        let third = event(h, home, at: 1, "third")
        home.sync {
            XCTAssertTrue(h.idle)
            needsYou = false
            h.take([third])
        }
        gate.signal()
        eventually("the next pass, once nothing needs you") { home.sync { records.count } == 3 }
        XCTAssertEqual(seen.all, ["first", "third"])
    }

    // MARK: Forced passes

    /// A forced pass needs no brain: each choice gets probability 1 and
    /// goes to the action that asked it, as Jev's answers would; a choice
    /// that isn't an option is left out. Its pass is logged for no view
    /// event, by the dashboard, its actions are `by` it, and its results
    /// show in the next state's HISTORY as Boop's own, under the latest
    /// view event before them, with no marker.
    func testAForcedPassRunsWithNoBrain() throws {
        let a = Recorder("a", keys: ["one"], result: .done("Boop did one."))
        let b = Recorder("b", keys: ["two"], result: .failed("not now"))
        let (h, home) = harness(nil, [a, b])
        let lines = Lines()
        _ = event(h, home, at: 1, "it started")
        let ran = home.sync {
            h.onDebugLine = { lines.add($0) }
            return h.force(["one": "b", "two": "nope", "three": "a"])
        }
        XCTAssertEqual(a.got, [["one": Answer(choice: "b", probabilities: ["b": 1])]])
        XCTAssertEqual(b.got, [[:]], "its answer wasn't an option")
        XCTAssertEqual(ran.map(\.name), ["a", "b"])
        let recorded = actions(h, home)
        XCTAssertEqual(recorded.map { $0["by"] }, ["dashboard", "dashboard"])
        XCTAssertEqual(recorded.map { $0["for"] }, [.null, .null])
        let pass = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines.all[0].utf8)) as? [String: Any])["pass"] as? [String: Any]
        XCTAssertTrue(pass?["for"] is NSNull)
        XCTAssertEqual(pass?["by"] as? String, "dashboard")

        let next = event(h, home, at: 2, "it ended")
        let state = StateText.build(home.sync { h.pipeline.view.events }, now: next, at: Self.t0 + 2 * 60_000, Self.parts)
        XCTAssertTrue(state.contains("1 min ago: it started\n  Boop did one.\nBoop has been grumpy"), state)
        XCTAssertFalse(state.contains("dashboard") || state.contains("not now"))
    }

    /// A forced pass runs at once, on `home`, and leaves the pass running
    /// and the one waiting alone.
    func testAForcedPassLeavesTheRunningAndWaitingPassesAlone() throws {
        let gate = DispatchSemaphore(value: 0)
        let brain = ScriptedBrain { _, _ in
            gate.wait()
            return [:]
        }
        let a = Recorder("a", keys: ["k"], result: .done("Boop did it."))
        let (h, home) = harness(brain, [a])
        var records: [Harness.Record] = []
        let first = event(h, home, "first"), second = event(h, home, "second")
        home.sync {
            h.onRecord = { records.append($0) }
            h.take([first])
            h.take([second])
            let (running, waiting) = (h.running, h.waiting?.id)
            XCTAssertEqual(h.force(["k": "a"]).count, 1)
            XCTAssertEqual(h.running, running)
            XCTAssertEqual(h.waiting?.id, waiting)
            XCTAssertEqual(waiting, second.id)
            XCTAssertEqual(records.count, 0, "a forced pass isn't one of Jev's")
        }
        gate.signal()
        gate.signal()
        eventually("two passes") { home.sync { records.count } >= 2 }
        XCTAssertEqual(records.map(\.now.line), ["first", "second"], "both of Jev's passes still ran")
        XCTAssertTrue(home.sync { h.idle })
    }

    /// HARNESS.md §2: a pass's state is fixed when it starts, so an action
    /// the dashboard makes act while the pass runs (a mood it sets, or a
    /// forced pass's) has changed since the state the pass's answers are
    /// about. That action sits the pass's answers out: "stay happy" from a
    /// state that showed happy would otherwise undo the dashboard's grumpy.
    /// The other actions, and the next pass, get theirs as usual.
    func testAnActionTheDashboardChangedDuringAPassSitsItOut() throws {
        let gate = DispatchSemaphore(value: 0)
        let brain = ScriptedBrain { _, _ in
            gate.wait()
            return ["k": Answer(choice: "a"), "j": Answer(choice: "b")]
        }
        let a = Recorder("a", keys: ["k"], result: .done("Boop did a."))
        let b = Recorder("b", keys: ["j"], result: .done("Boop did b."))
        let refused = Recorder("refused", keys: ["r"], result: .failed("not now"))
        let (h, home) = harness(brain, [a, b, refused])
        var records: [Harness.Record] = []
        let first = event(h, home, "first")
        home.sync {
            h.onRecord = { records.append($0) }
            h.take([first])
            XCTAssertEqual(h.force(a) { .done("The dashboard did a.") }, .done("The dashboard did a."))
            XCTAssertEqual(h.force(refused) { .failed("not now") }, .failed("not now"), "refused, so it changed nothing")
        }
        gate.signal()
        eventually("the pass") { home.sync { records.count } == 1 }
        XCTAssertEqual(a.got, [], "a sat it out")
        XCTAssertEqual(b.got.count, 1)
        XCTAssertEqual(refused.got.count, 1)
        XCTAssertEqual(records.first?.actions.map(\.name), ["b", "refused"])
        let next = event(h, home, at: 1, "next")
        home.sync { h.take([next]) }
        gate.signal()
        eventually("the next pass") { home.sync { records.count } == 2 }
        XCTAssertEqual(a.got.count, 1, "the next pass's state saw the change")
    }

    // MARK: Started actions (HARNESS.md §4–5)

    /// HISTORY as a pass a minute after `t0` would show it, for a NOW that
    /// comes after every view event.
    func history(_ h: Harness, _ home: DispatchQueue) -> String {
        home.sync {
            let now = ViewEvent(id: Int.max, type: .heartbeat, phase: nil, from: [], ts: Self.t0 + 60_000, line: "now",
                                wakesBrain: true)
            return StateText.history(h.pipeline.view.events, now: now, at: Self.t0 + 60_000,
                                     closing: "Boop has been grumpy for 2 min.", workingSince: nil)
        }
    }

    /// §4, §5.2–5.3: a started result is recorded as an action `start` and
    /// shows `(in progress)` until its handle ends; the end is an action
    /// `end` for the start's `seq`, after which the line is plain if it was
    /// done, or gone if it didn't happen. Only the first end counts.
    func testAStartedActionIsInProgressUntilItEnds() async throws {
        let first = Pending()
        let a = Recorder("a", keys: ["k"], result: .started("Boop did it.", first))
        let (h, home) = harness(ScriptedBrain(always: [:]), [a])
        _ = await h.respond(to: event(h, home, "it started"))
        let start = try XCTUnwrap(actions(h, home).last)
        XCTAssertEqual(start.jsonLine, #"{"seq":2,"ts":1790000000000,"source":"boop","type":"action","phase":"start","specific_type":"a","data":{"by":"brain","for":1,"latency_ms":0,"message":"Boop did it.","ok":true}}"#)
        XCTAssertEqual(home.sync { Array(h.open.keys) }, [2])
        XCTAssertEqual(history(h, home), """
            HISTORY (oldest first; indented lines add to the line above)
            1 min ago: it started
              Boop did it. (in progress)
            Boop has been grumpy for 2 min.
            """)

        home.sync { first.finish(.done) }
        XCTAssertEqual(actions(h, home).last?.jsonLine,
                       #"{"seq":3,"ts":1790000000000,"source":"boop","type":"action","phase":"end","specific_type":"a","data":{"by":"brain","for":2,"outcome":"done"}}"#)
        XCTAssertTrue(home.sync { h.open.isEmpty })
        XCTAssertTrue(history(h, home).contains("\n  Boop did it.\nBoop has been grumpy"), "the marker is gone")
        home.sync { first.finish(.failed("too late")) }
        XCTAssertEqual(actions(h, home).count, 2, "only the first end counts")

        let second = Pending()
        a.result = .started("Boop did it again.", second)
        _ = await h.respond(to: event(h, home, "it ended"))
        home.sync { second.finish(.failed("waited too long")) }
        XCTAssertEqual(actions(h, home).last?.data, ["by": "brain", "for": 5, "outcome": "failed", "why": "waited too long"])
        XCTAssertEqual(history(h, home), """
            HISTORY (oldest first; indented lines add to the line above)
            1 min ago: it started
              Boop did it.
            1 min ago: it ended
            Boop has been grumpy for 2 min.
            """)
        XCTAssertEqual(a.result, .started("Boop did it again.", second), "the same handle")
        XCTAssertNotEqual(a.result, .started("Boop did it again.", Pending()), "results compare their handle")
        XCTAssertNotEqual(a.result, .done("Boop did it again."))
    }

    /// §4: an end that comes before the harness has the result is kept
    /// and recorded right after it; a handle ends once.
    func testAnEndBeforeTheResultIsKept() async throws {
        var got: [Pending.End] = []
        let early = Pending()
        early.finish(.failed("first"))
        early.finish(.done)
        early.bind { got.append($0) }
        XCTAssertEqual(got, [.failed("first")])
        let late = Pending()
        late.bind { got.append($0) }
        late.finish(.done)
        late.finish(.failed("second"))
        XCTAssertEqual(got, [.failed("first"), .done])

        let pending = Pending()
        pending.finish(.failed("no device connected"))
        let (h, home) = harness(ScriptedBrain(always: [:]), [Recorder("a", keys: ["k"], result: .started("Boop did it.", pending))])
        _ = await h.respond(to: event(h, home, "it started"))
        let recorded = actions(h, home)
        XCTAssertEqual(recorded.map { $0.phase }, [.start, .end], "the action and its end")
        XCTAssertEqual(recorded.last?["why"], "no device connected")
        XCTAssertTrue(home.sync { h.open.isEmpty })
        XCTAssertTrue(history(h, home).contains("it started\nBoop has been grumpy"), "one that didn't happen isn't shown")
    }

    /// §5.1: a started action still in progress a minute
    /// (`Harness.pendingMaxMs`) after its result is ended as failed, and
    /// logged; its own end after that is ignored. A forced one is started
    /// and ended as Jev's are, and its end is by the dashboard too.
    func testAnActionStillInProgressAfterAMinuteIsEnded() {
        XCTAssertEqual(Harness.pendingMaxMs, 60_000)
        let pending = Pending()
        let a = Recorder("a", keys: ["k"], result: .started("Boop did it.", pending))
        let log = Lines()
        let (h, home) = harness(nil, [a], log: { log.add($0) })
        _ = event(h, home, "it started")
        home.sync { XCTAssertEqual(h.force(["k": "a"]).count, 1) }
        XCTAssertEqual(actions(h, home).last?.phase, .start)
        XCTAssertTrue(history(h, home).contains("\n  Boop did it. (in progress)\n"), "a forced one too")
        home.sync { h.tick(now: harnessT0 + 59_999) }
        XCTAssertEqual(home.sync { Array(h.open.keys) }, [2], "still open at 59,999 ms")
        home.sync { h.tick(now: harnessT0 + 60_000) }
        XCTAssertTrue(home.sync { h.open.isEmpty }, "ended at 60,000 ms")
        XCTAssertEqual(actions(h, home).last?.data, ["by": "dashboard", "for": 2, "outcome": "failed", "why": "no word it finished"])
        XCTAssertEqual(log.all, ["harness: a was still in progress after 60000 ms; ended it"])
        XCTAssertTrue(history(h, home).contains("it started\nBoop has been grumpy"), "ended, it didn't happen")
        home.sync {
            pending.finish(.done)
            h.tick(now: harnessT0 + 120_000)
        }
        XCTAssertEqual(actions(h, home).count, 2, "ended once")

        // One forced action on its own, as the dashboard's mood is.
        let alone = Pending()
        home.sync {
            XCTAssertNotNil(h.force(a) { .started("Boop did that.", alone) })
            alone.finish(.done)
        }
        XCTAssertEqual(actions(h, home).last?.data, ["by": "dashboard", "for": 4, "outcome": "done"])
    }

    /// §5.3, §9: a replay rebuilds a logged pass's state exactly: the
    /// log's events up to the pass line's `seen`, folded into a fresh view,
    /// an action's end included, and none recorded while the brain
    /// answered, which lands before the pass line but wasn't in its state.
    func testALoggedStateIsRebuiltFromTheLogWithItsEnds() async throws {
        let pending = Pending(), during = Pending()
        let home = DispatchQueue(label: "test.home")
        // The second pass's brain hears the first action end while it answers.
        let brain = ScriptedBrain { state, _ in
            if state.contains("\nclaude finished turn 1 on") { home.sync { during.finish(.done) } }
            return [:]
        }
        let started = Recorder("a", keys: ["k"], result: .started("Boop did it.", pending))
        let p = Self.pipeline()
        let h = Harness(brain: brain, actions: [started], pipeline: p, parts: { _ in Self.parts }, home: home, clock: { harnessT0 })
        let lines = Lines()
        home.sync {
            h.onDebugLine = { lines.add($0) }
            p.onRecord = { lines.add(DebugLog.event($0)) }
        }
        func hook(_ type: Event.Kind, _ phase: Event.Phase, _ specific: String, at minutes: Int64,
                  _ data: [String: JSONValue] = [:]) async {
            let views = home.sync {
                p.agent(Event(ts: Self.t0 + minutes * 60_000, source: .claude, type: type, phase: phase, specificType: specific,
                              session: "s1", cwd: "/w/landing", data: data)).waking
            }
            for v in views { _ = await h.respond(to: v) }
        }
        await hook(.turn, .start, "UserPromptSubmit", at: -3)
        home.sync { pending.finish(.failed("the device disconnected")) }
        started.result = .started("Boop did more.", during)
        await hook(.tool, .start, "PreToolUse", at: -2, ["tool": "Bash", "topic": "tests", "tool_use_id": "t"])
        await hook(.tool, .end, "PostToolUseFailure", at: -2, ["tool": "Bash", "tool_use_id": "t", "failed": true])
        started.result = nil
        await hook(.turn, .end, "Stop", at: 0, ["outcome": "done"])
        let objects = lines.all.map { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let (i, pass) = try XCTUnwrap(objects.enumerated().compactMap { i, o in (o?["pass"] as? [String: Any]).map { (i, $0) } }.last)
        let logged = try XCTUnwrap(pass["state"] as? String)
        XCTAssertTrue(logged.contains("3 min ago: claude started turn 1 on \"landing\".\n2 min ago: claude's tests failed on"),
                      "one that didn't happen isn't shown: \(logged)")
        XCTAssertTrue(logged.contains("  Boop did more. (in progress)\n"), "its end came while the brain answered: \(logged)")
        let before = objects[..<i].compactMap { ($0?["event"] as? [String: Any]).flatMap(Event.init(json:)) }
        XCTAssertTrue(before.contains { $0["outcome"] == "done" && $0.type == .action }, "logged before the pass")
        let seen = try XCTUnwrap(pass["seen"] as? Int)
        func rebuilt(_ events: [Event]) -> String {
            let view = TranscriptView()
            for e in events { view.take(e) }
            let now = view.events.last { $0.seq == pass["for"] as? Int }!
            return StateText.build(view.events, now: now, at: harnessT0, Self.parts)
        }
        XCTAssertEqual(rebuilt(before.filter { $0.seq <= seen }), logged)
        XCTAssertNotEqual(rebuilt(before), logged, "without `seen`, not exact")
    }

    // MARK: The debug log (HARNESS.md §9)

    /// The printer reads view events, passes and actions, a started action
    /// with `…` and an end by its action's name, and skips the other raw
    /// events and the dashboard's lines.
    func testThePrinterSkipsTheDashboardsLines() {
        let printer = DebugLog.Printer()
        let stateJSON = #"You are.\nPERSONALITY\nx\n\nHISTORY (oldest first)\nh\n\nNOW (14:23, Tuesday)\nn"#
        let lines: [(String, String?)] = [
            (#"{"view":{"facts":{},"from":[3],"id":1,"line":"claude finished turn 1.","notes":["Its last message: \"ok\""],"phase":"end","type":"turn","wakes_brain":true},"received_at_ms":5}"#,
             "▸ 1 turn end: claude finished turn 1.\n    Its last message: \"ok\""),
            (#"{"view":{"facts":{},"from":[4],"id":2,"line":"claude needs you.","notes":[],"phase":"wait","type":"tool","wakes_brain":false},"received_at_ms":6}"#,
             "▸ 2 tool wait (no pass): claude needs you."),
            (#"{"event":{"seq":4,"ts":6,"source":"claude","type":"turn","phase":"end","specific_type":"Stop","session":"s","data":{}},"received_at_ms":6}"#, nil),
            (#"{"pass":{"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.9,"grumpy":0.1}},"react":{"choice":"excited","p":{"excited":1}}},"brain":"scripted","dropped":null,"for":3,"latency_ms":12,"questions":["mood","react"],"state":""# + stateJSON + #""},"received_at_ms":7}"#,
             "  pass scripted 12 ms: mood cheerful 0.90 · react excited 1.00\n    │ You are.\n    │ PERSONALITY\n    │ x\n    │ \n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"pass":{"answers":{},"brain":"jev:jev-latest","dropped":"late: no answer within 1500 ms","for":3,"latency_ms":1500,"questions":["mood"],"state":""# + stateJSON + #""},"received_at_ms":8}"#,
             "  pass jev:jev-latest 1500 ms: dropped: late: no answer within 1500 ms\n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"event":{"seq":7,"ts":9,"source":"boop","type":"action","specific_type":"react","data":{"by":"brain","for":3,"message":"Boop made an excited face and mumbled \"…yay!\"","ok":true}},"received_at_ms":9}"#,
             "  ✓ react: Boop made an excited face and mumbled \"…yay!\""),
            (#"{"event":{"seq":8,"ts":9,"source":"boop","type":"action","specific_type":"mood","data":{"by":"brain","for":3,"message":"changed 3 min ago","ok":false}},"received_at_ms":9}"#,
             "  ✗ mood: changed 3 min ago"),
            (#"{"event":{"seq":9,"ts":9,"source":"boop","type":"action","specific_type":"wiggle","data":{"by":"rule","for":4,"message":"Boop wiggled on its own.","ok":true}},"received_at_ms":9}"#,
             "  ✓ wiggle (rule): Boop wiggled on its own."),
            ("not json", "not json"),
            (#"{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":9}"#, nil),
            (#"{"status":{"brain":"none","connected":false,"mood":"cheerful","personality":"boop","sessions":[]},"received_at_ms":9}"#, nil),
            (#"{"questions":[],"received_at_ms":9}"#, nil),
            (#"{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react"]},"received_at_ms":10}"#,
             "  pass dashboard 0 ms: react grumpy 1.00"),
            (#"{"event":{"seq":10,"ts":11,"source":"boop","type":"action","phase":"start","specific_type":"react","data":{"by":"brain","for":3,"message":"Boop made an excited face and mumbled \"…yay!\"","ok":true}},"received_at_ms":11}"#,
             "  … react: Boop made an excited face and mumbled \"…yay!\""),
            (#"{"event":{"seq":11,"ts":12,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"brain","for":10,"outcome":"done"}},"received_at_ms":12}"#,
             "  ✓ react (10) done"),
            (#"{"event":{"seq":12,"ts":13,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"dashboard","for":10,"outcome":"failed","why":"waited too long"}},"received_at_ms":13}"#,
             "  ✗ react (10) didn't happen: waited too long"),
            (#"{"event":{"seq":13,"ts":14,"source":"boop","type":"action","phase":"end","specific_type":"needs_you","session":"s","data":{"by":"rule","outcome":"done"}},"received_at_ms":14}"#,
             "  · needs_you (rule) ended"),
        ]
        for (line, readable) in lines { XCTAssertEqual(printer.readable(line), readable, line) }
    }

    func testQuestionKeysMustBeUniqueAcrossActions() {
        XCTAssertEqual(Set(Self.realActions().flatMap { $0.questions().map(\.key) }).count, 6)
    }

    static func realActions() -> [any Action] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-mood-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return [MoodAction(store: MoodStore(stateDir: dir)),
                ReactAction(voice: Voice(dialect: Dialect(seed: 1)), queue: { _, _ in }, blocked: { nil })]
    }

    // MARK: The actions (DECISIONS.md §4–5)

    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// DECISIONS.md §5: `none` does nothing; the word is the exclamation
    /// over 0.35, else the topic, else none; the moment carries the
    /// expression as its `mood` and `react.loops`' pick as its loops (once
    /// to four times: 1–4, and once when it's missing), and goes to the
    /// queue with the handle the result is started with; a blocked mumble
    /// fails, with no handle.
    func testReact() {
        XCTAssertEqual(ReactAction.wordFloor, 0.35)
        var queued: [(moment: DeviceMoment, pending: Pending)] = []
        var sent: [DeviceMoment] { queued.map(\.moment) }
        var why: String?
        let react = ReactAction(voice: Voice(dialect: Dialect(seed: 1)), queue: { queued.append(($0, $1)) }, blocked: { why })
        /// Runs `answers`, and checks the result is started with `message`
        /// and the handle its moment was queued with.
        func starts(_ answers: Answers, _ message: String, line: UInt = #line) {
            let before = queued.count
            let result = react.run(answers)
            XCTAssertEqual(queued.count, before + 1, "one moment queued", line: line)
            XCTAssertEqual(result, queued.last.map { .started(message, $0.pending) }, line: line)
        }
        XCTAssertNil(react.run(["react.mood": a("none")]))
        starts(["react.mood": a("grumpy"), "word.feeling": a("again", 0.57), "word.about": a("tests", 0.81),
                "react.loops": a("twice")],
               #"Boop made a grumpy face, held twice, and mumbled "…again!""#)
        starts(["react.mood": a("proud"), "word.feeling": a("again", 0.31), "word.about": a("tests", 0.79)],
               #"Boop made a proud face, held once, and mumbled "…tests!""#)
        starts(["react.mood": a("happy"), "word.feeling": a("none"), "word.about": a("docs", 0.2), "react.loops": a("four times")],
               "Boop made a happy face, held four times, and mumbled.")
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(Set(queued.map { ObjectIdentifier($0.pending) }).count, 3, "a handle each")
        XCTAssertEqual(sent[0].say?.word, "again")
        XCTAssertNil(sent[0].anim, "a mumble plays over the face")
        XCTAssertEqual(sent.map(\.mood), ["grumpy", "proud", "happy"], "each wears its face")
        XCTAssertEqual(sent.map(\.loops), [2, 1, 4], "for its loops")
        XCTAssertEqual(sent[0].say?.tune, .flat, "grumpy mumbles in annoyed's voice")
        XCTAssertTrue(sent[0].jsonLine.hasSuffix(#","mood":"grumpy","loops":2}"#), sent[0].jsonLine)
        XCTAssertNil(react.run(["react.mood": a("annoyed")]), "annoyed was a feeling, not a face")
        starts(["react.mood": a("excited"), "react.loops": a("three times")], "Boop made an excited face, held three times, and mumbled.")
        XCTAssertEqual(queued.last?.moment.loops, 3)
        queued.removeLast()
        // DECISIONS.md §3, §5: `react.animation` plays the cheer in the face;
        // `none`, a missing answer or an animation the device doesn't play
        // is just the face.
        XCTAssertEqual(ReactAction.animations.map(\.name), ["cheer"])
        starts(["react.mood": a("proud"), "react.animation": a("cheer"), "react.loops": a("twice"), "word.feeling": a("finally")],
               #"Boop played a cheer in a proud face, held twice, and mumbled "…finally!""#)
        XCTAssertEqual(queued.last?.moment.anim, "cheer")
        XCTAssertTrue(queued.last!.moment.jsonLine.hasPrefix(#"{"t":"moment","anim":"cheer","say":"#), queued.last!.moment.jsonLine)
        let first = try! XCTUnwrap(queued.last?.moment.variant)
        XCTAssertTrue(queued.last!.moment.jsonLine.hasSuffix(#","mood":"proud","loops":2,"variant":"# + "\(first)}"),
                      queued.last!.moment.jsonLine)
        queued.removeLast()
        // BEHAVIORS.md §5: each cheer is one of the cheer's variations at
        // random, never the last one again.
        var cheers = [first]
        for _ in 0..<30 {
            _ = react.run(["react.mood": a("proud"), "react.animation": a("cheer")])
            cheers.append(queued.removeLast().moment.variant!)
        }
        XCTAssertEqual(Set(cheers), Set(1...FaceLoops.count(state: "task_complete")))
        XCTAssertTrue(zip(cheers, cheers.dropFirst()).allSatisfy { $0 != $1 }, "\(cheers)")
        for pick in ["none", "wiggle", "confetti"] {
            starts(["react.mood": a("happy"), "react.animation": a(pick)], "Boop made a happy face, held once, and mumbled.")
            XCTAssertNil(queued.last?.moment.anim, pick)
            queued.removeLast()
        }
        XCTAssertNil(react.run(["react.mood": a("proud-cheer")]), "a face and an animation are separate questions")
        why = "something needs you"
        for expression in ReactAction.expressions.map(\.name) {
            XCTAssertEqual(react.run(["react.mood": a(expression)]), .failed("something needs you"))
        }
        XCTAssertEqual(sent.count, 3, "no face or mumble while something needs you")
        XCTAssertEqual(react.questions().map(\.key), ["react.mood", "react.animation", "react.loops", "word.feeling", "word.about"])
        XCTAssertEqual(react.questions()[0].options.map(\.name), ["none"] + MoodAction.moods.map(\.name),
                       "the faces are the six moods'")
        XCTAssertNil(react.run(["react.mood": a("curious")]), "curious isn't a face the brain can pick (DECISIONS.md §3)")
        XCTAssertEqual(react.questions()[1].options.map(\.name), ["none", "cheer"])
        XCTAssertEqual(react.questions()[2].options.map(\.name), ["once", "twice", "three times", "four times"])
        XCTAssertEqual(react.questions()[3].options.map(\.name), ["none", "finally", "yay", "nice", "oops", "again", "ugh", "nope", "hmm"])
        XCTAssertEqual(react.questions()[4].options.map(\.name), ["none", "tests", "build", "deploy", "docs", "bug", "merge", "review"])
        XCTAssertEqual(ReactAction.holds.indices.map { ReactAction.loops(["react.loops": a(ReactAction.holds[$0].name)]) },
                       [1, 2, 3, 4])
        XCTAssertEqual(ReactAction.loops([:]), 1)
        XCTAssertLessThanOrEqual(ReactAction.holds.count, DeviceMoment.maxLoops, "the device plays them all")
        for word in ReactAction.exclamations.map(\.name) + ReactAction.topics.map(\.name) {
            XCTAssertTrue(Sounds.vocabulary.contains(word), "\(word) is one of Voice's words")
        }
    }

    /// VOICE.md §4: a mood's face mumbles in the feeling of the same name,
    /// grumpy in annoyed's, and a mood with no voice of its own in the
    /// temporary default, happy's.
    func testEachMoodHasAVoice() {
        let voices = Dictionary(uniqueKeysWithValues: MoodAction.moods.map { ($0.name, Voice.feeling(forMood: $0.name)) })
        XCTAssertEqual(voices, ["happy": .happy, "excited": .excited, "proud": .proud,
                                "determined": .happy, "grumpy": .annoyed, "sad": .sad])
    }

    /// PROTOCOL.md §3: only the brain's moments carry an expression; the
    /// dashboard's cheer or wiggle never does.
    func testRuleMomentsCarryNoExpression() {
        XCTAssertEqual(DeviceMoment(anim: "cheer").jsonLine, #"{"t":"moment","anim":"cheer"}"#)
        let line = VoiceLine(groups: [["bi", "da"]], word: nil, at: 2, tune: .bounce, ms: 125)
        XCTAssertEqual(DeviceMoment(say: line).jsonLine, #"{"t":"moment","say":{"syl":"bi-da","tune":"bounce","ms":125}}"#)
        XCTAssertEqual(DeviceMoment(say: line, mood: "grumpy").jsonLine,
                       #"{"t":"moment","say":{"syl":"bi-da","tune":"bounce","ms":125},"mood":"grumpy"}"#)
    }

    /// DECISIONS.md §2.3, §4: the six moods; the current mood is nothing to do,
    /// and any other changes the file, and MOOD with it, however recently
    /// it last changed (how long a mood lasts is the steering's call).
    func testMood() throws {
        XCTAssertEqual(MoodAction.moods.map(\.name), ["happy", "excited", "proud", "determined", "grumpy", "sad"])
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-mood-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MoodStore(stateDir: dir)
        XCTAssertEqual(store.current, "happy", "a new state directory starts happy")
        var told: [String] = []
        let mood = MoodAction(store: store, changed: { told.append($0) })
        XCTAssertNil(mood.run(["mood": a("happy")]))
        XCTAssertEqual(mood.run(["mood": a("determined")]), .done("Boop's mood changed: happy → determined."))
        XCTAssertEqual(mood.run(["mood": a("proud")]), .done("Boop's mood changed: determined → proud."), "straight after, too")
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("mood"), encoding: .utf8), "proud\n")
        XCTAssertEqual(told, ["determined", "proud"], "each saved change is passed on, for the device")
        XCTAssertNil(mood.run(["mood": a("sulky")]), "not a mood")
        try Data("grumpy\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "grumpy", "it survives a restart")
        try Data("cheerful\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "cheerful, its old name, reads as happy")
        try Data("curious\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "curious, no longer a mood, reads as happy")
        XCTAssertNil(mood.run(["mood": a("curious")]), "curious isn't a mood")
        try Data("delighted\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "an unknown one reads as happy")
    }

    /// DECISIONS.md §4: the mood the dashboard sets
    /// changes as Jev's does, device included, and it's told why when it
    /// can't: the mood it already is, or one that isn't a mood.
    func testAForcedMoodChangesItAsJevsDoes() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-mood-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var told: [String] = []
        let mood = MoodAction(store: MoodStore(stateDir: dir), changed: { told.append($0) })
        XCTAssertEqual(mood.change(to: "grumpy"), .done("Boop's mood changed: happy → grumpy."))
        XCTAssertEqual(mood.change(to: "grumpy"), .failed("already grumpy"))
        XCTAssertEqual(mood.change(to: "sulky"), .failed("sulky isn't a mood"))
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("mood"), encoding: .utf8), "grumpy\n")
        XCTAssertEqual(mood.run(["mood": a("proud")]), .done("Boop's mood changed: grumpy → proud."), "Jev's, right after")
        XCTAssertEqual(told, ["grumpy", "proud"], "the device hears each change")
    }

    // MARK: Jev (HARNESS.md §7)

    /// Each `Question` becomes a choice question: its options' meanings are
    /// the criteria, with `not_for` when there is one.
    func testJevsRequest() throws {
        let q = Question(key: "word.feeling", text: "Which exclamation fits NOW?", about: "the NOW section",
                         judgeBy: "the PERSONALITY section", options: [Option("none", "No exclamation fits NOW."),
                                                                       Option("finally", "Something worked after failing.", notFor: "A first try.")])
        let body = JevBrain.body(model: "jev-latest", state: "STATE", questions: [q])
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(o["model"] as? String, "jev-latest")
        XCTAssertEqual(o["state"] as? String, "STATE")
        let question = try XCTUnwrap((o["questions"] as? [String: Any])?["word.feeling"] as? [String: Any])
        XCTAssertEqual(question["type"] as? String, "choice")
        let criteria = try XCTUnwrap(question["criteria"] as? [String: Any])
        XCTAssertEqual(criteria["none"] as? String, "No exclamation fits NOW.")
        XCTAssertEqual(criteria["finally"] as? [String: String], ["what": "Something worked after failing.", "not_for": "A first try."])
        XCTAssertEqual(question["instructions"] as? [String: String],
                       ["question": "Which exclamation fits NOW?", "about": "the NOW section", "judge_by": "the PERSONALITY section"])
    }

    /// The answer's choices and probabilities; one missing, or off its
    /// options, fails it. A 429 is tried once more; only the status is kept.
    func testJevsAnswerAndRetry() async throws {
        let q = [Question(key: "react", text: "?", about: "a", judgeBy: "b", options: [Option("none", "n"), Option("proud", "p")])]
        let good = Data(#"{"answers":{"react":{"choice":"proud","probabilities":{"proud":0.7,"none":0.3}}}}"#.utf8)
        try XCTAssertEqual(try JevBrain.answers(good, q), ["react": Answer(choice: "proud", probabilities: ["proud": 0.7, "none": 0.3])])
        try XCTAssertThrowsError(try JevBrain.answers(Data(#"{"answers":{"react":{"choice":"sad"}}}"#.utf8), q))
        try XCTAssertThrowsError(try JevBrain.answers(Data(#"{"answers":{}}"#.utf8), q))
        let calls = Lines()
        let jev = JevBrain(key: "k") { request in
            calls.add(request.value(forHTTPHeaderField: "Authorization") ?? "")
            return calls.all.count == 1 ? (Data("PRIVATE".utf8), 429) : (good, 200)
        }
        let answers = try await jev.answer(state: "s", questions: q, deadline: .milliseconds(Harness.deadlineMs))
        XCTAssertEqual(answers["react"]?.choice, "proud")
        XCTAssertEqual(calls.all, ["Bearer k", "Bearer k"])
        // No retry the deadline would cut off: it would only cost a request.
        let slow = Lines()
        let late = JevBrain(key: "k") { _ in
            slow.add("sent")
            try await Task.sleep(for: .milliseconds(150))
            return (Data(), 503)
        }
        do {
            _ = try await late.answer(state: "s", questions: q, deadline: .milliseconds(400))
            XCTFail("no answer")
        } catch let error as BrainError {
            XCTAssertEqual(error.description, "jev: HTTP 503")
        }
        XCTAssertEqual(slow.all, ["sent"], "150 ms, and 300 more, is past the 400")
        let down = JevBrain(key: "k") { _ in (Data("PRIVATE".utf8), 500) }
        do {
            _ = try await down.answer(state: "s", questions: q, deadline: .milliseconds(Harness.deadlineMs))
            XCTFail("no answer")
        } catch let error as BrainError {
            XCTAssertEqual(error.description, "jev: HTTP 500", "only the status")
            XCTAssertEqual(error.status, 500)
        }
    }

    /// The transcript keeps its newest thousand events in memory.
    func testTheTranscriptLetsTheOldestGo() {
        let t = Transcript()
        for _ in 0..<1005 { t.append(Event(ts: 0, source: .device, type: .poke, specificType: "input")) }
        XCTAssertEqual(t.events.count, 1000)
        XCTAssertEqual(t.events.first?.seq, 6)
    }
}
