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

    func event(_ kind: Event.Kind, at minutes: Int64, _ line: String, reaction: String? = nil, wakes: Bool = true) -> Event {
        Event(kind, at: Self.t0 + minutes * 60_000, line: line, reaction: reaction, wakesBrain: wakes)
    }

    static let parts = StateText.Parts(guide: "You are the mind of Boop.", personality: "PERSONALITY\nCurious.",
                                       mood: "MOOD\nHappy.", status: "Working now: nothing else.",
                                       workingSince: nil, clock: "14:23, Tuesday")

    /// harness/HARNESS.md §5.3: HISTORY and NOW, built step by step from
    /// the typed entries: only events, oldest first, relative times, what
    /// Boop did indented under what it answered (its rule reaction first,
    /// then its successful actions), failed actions and passes left out.
    func testTheTextFormFollowsTheSteps() {
        let t = Transcript()
        let start = t.append(.event(event(.turnStart, at: 5, #"claude started turn 7 on "fix-nav" (landing)."#)), at: Self.t0 + 5 * 60_000)
        t.append(.pass(.init(forSeq: start.seq, answers: [:], dropped: nil, latencyMs: 200)), at: Self.t0)
        let failed = t.append(.event(event(.toolUse, at: 14, #"claude's tests failed again on "fix-nav" (landing), 2 in a row."#)),
                              at: Self.t0 + 14 * 60_000)
        t.append(.action(.init(forSeq: failed.seq, name: "react", result: .done(#"Boop made a grumpy face and mumbled "…tests!""#), latencyMs: 1)), at: Self.t0)
        t.append(.action(.init(forSeq: failed.seq, name: "mood", result: .failed("couldn't save the mood: disk full"), latencyMs: 1)), at: Self.t0)
        t.append(.event(event(.tap, at: 19, "You tapped Boop.", reaction: "Boop wiggled on its own.", wakes: false)),
                 at: Self.t0 + 19 * 60_000)
        let end = t.append(.event(event(.turnEnd, at: 23, #"claude finished turn 7 on "fix-nav" (landing): done."#,
                                        reaction: "Boop cheered on its own.")), at: Self.t0 + 23 * 60_000)
        var parts = Self.parts
        parts.workingSince = Self.t0 + 5 * 60_000  // the turn is still working, so HISTORY reaches back to its start
        let state = StateText.build(t.entries, now: end, at: Self.t0 + 23 * 60_000 + 5000, parts)
        XCTAssertEqual(state, """
            You are the mind of Boop.
            \(StateText.reading)
            \(EventLine.words)

            PERSONALITY
            Curious.

            MOOD
            Happy.

            HISTORY (oldest first; indented lines are what Boop did)
            18 min ago: claude started turn 7 on "fix-nav" (landing).
            9 min ago: claude's tests failed again on "fix-nav" (landing), 2 in a row.
              Boop made a grumpy face and mumbled "…tests!"
            4 min ago: You tapped Boop.
              Boop wiggled on its own.
            Working now: nothing else.

            NOW (14:23, Tuesday)
            claude finished turn 7 on "fix-nav" (landing): done.
            Boop cheered on its own.
            """)
    }

    /// §5.3: HISTORY reaches back 10 minutes, or to the oldest working
    /// turn, whichever is further, and holds at most 40 events.
    func testHistoryReachesBackTenMinutesOrToTheOldestWorkingTurn() {
        XCTAssertEqual(StateText.historyMs, 600_000)
        XCTAssertEqual(StateText.historyLimit, 40)
        let t = Transcript()
        let old = t.append(.event(event(.turnStart, at: 0, "old")), at: Self.t0)
        _ = old
        for i in 1...50 { t.append(.event(event(.tap, at: 20, "tap \(i)", wakes: false)), at: Self.t0 + 20 * 60_000) }
        let now = t.append(.event(event(.heartbeat, at: 21, "now")), at: Self.t0 + 21 * 60_000)
        let recent = StateText.history(t.entries, now: now, at: Self.t0 + 21 * 60_000, status: "s", workingSince: nil)
        XCTAssertFalse(recent.contains(": old"), "21 minutes ago is past the 10")
        XCTAssertEqual(recent.split(separator: "\n").count, 1 + 40 + 1, "a heading, 40 events, the status line")
        XCTAssertTrue(recent.contains("tap 50") && !recent.contains("tap 10\n"), "the newest 40")
        let working = StateText.history(t.entries, now: now, at: Self.t0 + 21 * 60_000, status: "s", workingSince: Self.t0)
        XCTAssertTrue(working.contains("21 min ago: old") || !working.contains("tap 1\n"), "the working turn's start counts, within the 40")
        XCTAssertEqual(StateText.ago(59_999), "just now")
        XCTAssertEqual(StateText.ago(9 * 60_000), "9 min ago")
        XCTAssertEqual(StateText.ago(2 * 3_600_000 + 5), "2 h ago")
    }

    /// §5.3 step 2: an event whose started action is still in progress
    /// stays in HISTORY past the newest 40, so a pass still sees the face
    /// Boop is making. With chatter's `tool_uses: all`, 40 routine calls
    /// can land during one face held four times, and the reaction dropped
    /// out of HISTORY: Jev could call for the same face again
    /// (harness/DECISIONS.md §5, react's `none`).
    func testAReactionInProgressStaysInHistory() {
        let t = Transcript()
        let failed = t.append(.event(event(.toolUse, at: 20, "tests failed")), at: Self.t0 + 20 * 60_000)
        t.append(.action(.init(forSeq: failed.seq, name: "react", result: .started("Boop made a proud face.", Pending()),
                               latencyMs: 1)), at: Self.t0 + 20 * 60_000)
        let done = t.append(.event(event(.toolUse, at: 20, "tests failed again")), at: Self.t0 + 20 * 60_000)
        t.append(.action(.init(forSeq: done.seq, name: "react", result: .done("Boop mumbled."), latencyMs: 1)),
                 at: Self.t0 + 20 * 60_000)
        for i in 1...45 { t.append(.event(event(.toolUse, at: 20, "read \(i)")), at: Self.t0 + 20 * 60_000) }
        let now = t.append(.event(event(.toolUse, at: 20, "now")), at: Self.t0 + 20 * 60_000 + 30_000)
        let history = StateText.history(t.entries, now: now, at: now.receivedAtMs, status: "s", workingSince: nil)
        let lines = history.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "just now: tests failed", "the oldest, kept for its reaction")
        XCTAssertEqual(lines[2], "  Boop made a proud face. (in progress)")
        XCTAssertEqual(lines[3], "just now: read 6", "then the newest 40")
        XCTAssertFalse(history.contains("tests failed again"), "a finished one isn't kept")
        XCTAssertEqual(lines.count, 1 + 2 + 40 + 1)
    }

    // MARK: The harness

    func harness(_ brain: (any Brain)?, _ actions: [any Action]) -> (Harness, DispatchQueue) {
        let home = DispatchQueue(label: "test.home")
        let h = Harness(brain: brain, actions: actions, parts: { _ in Self.parts }, home: home, clock: { harnessT0 })
        return (h, home)
    }

    /// HARNESS.md §2–4: one request with every action's questions; each
    /// action gets only its own answers, in order; a nil result records
    /// nothing, and every result is recorded under its event.
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
        let recordResult = await h.respond(to: event(.turnStart, at: 0, "it happened"))
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(seen.all, ["one,two,three"], "one request")
        XCTAssertEqual(first.got, [["one": Answer(choice: "a"), "two": Answer(choice: "b")]])
        XCTAssertEqual(second.got, [["three": Answer(choice: "a")]])
        XCTAssertEqual(record.actions.map(\.name), ["first"], "nil is nothing to record")
        XCTAssertEqual(record.logLine, "brain turn_start \(record.pass.latencyMs) ms → first")
        home.sync {
            XCTAssertEqual(h.transcript.entries.count, 3, "the event, the pass, one action")
            if case .action(let a) = h.transcript.entries[2].body { XCTAssertEqual(a.forSeq, 1) } else { XCTFail() }
        }
    }

    /// An event that doesn't wake the brain, or no brain, gets no pass; a
    /// brain that fails drops the pass and runs no action.
    func testNoPassWithoutWakingOrABrainAndNoActionWhenItFails() async throws {
        let a = Recorder("a", keys: ["k"], result: .done("x"))
        let (h, _) = harness(ScriptedBrain(always: [:]), [a])
        let tap = await h.respond(to: event(.tap, at: 0, "You tapped Boop.", wakes: false))
        XCTAssertNil(tap)
        let (none, _) = harness(nil, [a])
        let nothing = await none.respond(to: event(.turnStart, at: 0, "x"))
        XCTAssertNil(nothing)
        let (broken, _) = harness(ScriptedBrain { _, _ in throw BrainError("jev: HTTP 500") }, [a])
        let recordResult = await broken.respond(to: event(.turnStart, at: 0, "x"))
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(record.pass.dropped, "jev: HTTP 500")
        XCTAssertEqual(record.actions, [])
        XCTAssertEqual(a.got.count, 0)
        XCTAssertEqual(record.logLine, "brain turn_start \(record.pass.latencyMs) ms → dropped: jev: HTTP 500")
    }

    /// HARNESS.md §7: a pass that runs past 1.25 s is dropped.
    func testALateAnswerIsDropped() async throws {
        XCTAssertEqual(Harness.deadlineMs, 1250)
        let (h, _) = harness(SlowBrain(ms: 3000), [Recorder("a", keys: ["k"], result: .done("x"))])
        let recordResult = await h.respond(to: event(.turnStart, at: 0, "x"))
        let record = try XCTUnwrap(recordResult)
        XCTAssertEqual(record.pass.dropped, "late: no answer within 1250 ms")
    }

    /// HARNESS.md §7: the deadline cuts a pass off at 1.25 s. Its timer
    /// had the system's default leeway, so it fired at 1.25–1.33 s: an
    /// answer at 1.3 s was kept or dropped by chance, and every dropped
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
        let home = DispatchQueue(label: "test.home")
        let h = Harness(brain: SlowBrain(ms: 1400), actions: [Recorder("a", keys: ["k"], result: .done("x"))],
                        parts: { _ in Self.parts }, home: home, clock: { harnessT0 }, log: { logged.add($0) })
        home.sync { h.take(event(.turnStart, at: 0, "x")) }
        eventually("the late answer's line", timeout: 4) { logged.all.contains { $0.hasPrefix("harness: slow answered after 14") } }
        XCTAssertTrue(logged.all.contains { $0.hasSuffix("dropped: late: no answer within 1250 ms") }, "\(logged.all)")
    }

    /// HARNESS.md §2: one pass runs at a time, and a newer event replaces
    /// one that's waiting; the replaced one is still recorded.
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
        home.sync {
            h.onRecord = { records.append($0) }
            h.take(event(.turnStart, at: 0, "first"))
            h.take(event(.turnStart, at: 0, "second"))
            h.take(event(.turnStart, at: 0, "third"))
        }
        Thread.sleep(forTimeInterval: 0.1)
        gate.signal()
        eventually("two passes") { home.sync { records.count } >= 2 }
        XCTAssertEqual(seen.all, ["first", "third"], "second was replaced while it waited")
        home.sync {
            XCTAssertTrue(h.idle)
            XCTAssertEqual(h.transcript.entries.filter { if case .event = $0.body { true } else { false } }.count, 3)
        }
    }

    /// HARNESS.md §2, EVENTS.md §6: no event wakes the brain while
    /// something needs you. An event that woke it before, and waited
    /// behind a running pass, doesn't start its pass once something needs
    /// you: it's recorded as a pass dropped for that. Before, it asked Jev
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
        home.sync {
            h.mayStart = { !needsYou }
            h.onRecord = { records.append($0) }
            h.take(event(.turnStart, at: 0, "first"))
            h.take(event(.toolUse, at: 0, "second"))
            needsYou = true
        }
        gate.signal()
        eventually("both recorded") { home.sync { records.count } == 2 }
        XCTAssertEqual(seen.all, ["first"], "no request for the second")
        XCTAssertEqual(records.last?.pass.dropped, "something needs you")
        XCTAssertEqual(records.last?.logLine, "brain tool_use 0 ms → dropped: something needs you")
        home.sync {
            XCTAssertTrue(h.idle)
            needsYou = false
            h.take(event(.toolUse, at: 1, "third"))
        }
        gate.signal()
        eventually("the next pass, once nothing needs you") { home.sync { records.count } == 3 }
        XCTAssertEqual(seen.all, ["first", "third"])
    }

    // MARK: Forced passes (DASHBOARD.md §4)

    /// A forced pass needs no brain: each choice gets probability 1 and
    /// goes to the action that asked it, as Jev's answers would; a choice
    /// that isn't an option is left out. It's recorded for no event, by
    /// the dashboard, and its results show in the next state's HISTORY as
    /// Boop's own, under the latest event before them, with no marker.
    func testAForcedPassRunsWithNoBrain() throws {
        let a = Recorder("a", keys: ["one"], result: .done("Boop did one."))
        let b = Recorder("b", keys: ["two"], result: .failed("not now"))
        let (h, home) = harness(nil, [a, b])
        let ran = home.sync {
            h.take(event(.turnStart, at: 1, "it started"))
            return h.force(["one": "b", "two": "nope", "three": "a"])
        }
        XCTAssertEqual(a.got, [["one": Answer(choice: "b", probabilities: ["b": 1])]])
        XCTAssertEqual(b.got, [[:]], "its answer wasn't an option")
        XCTAssertEqual(ran.map(\.name), ["a", "b"])
        let entries = home.sync { h.transcript.entries }
        XCTAssertEqual(entries.count, 4, "the event, the pass and both results")
        XCTAssertEqual(entries[1].body, .pass(.init(forSeq: nil, answers: ["one": Answer(choice: "b", probabilities: ["b": 1])],
                                                     dropped: nil, latencyMs: 0)))
        let pass = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Transcript.json(entries[1], extra: ["questions": ["one"]]).utf8))
                                 as? [String: Any])["pass"] as? [String: Any]
        XCTAssertTrue(pass?["for"] is NSNull)
        XCTAssertEqual(pass?["by"] as? String, "dashboard")
        XCTAssertTrue(Transcript.json(entries[2]).contains(#""by":"dashboard","for":null"#), Transcript.json(entries[2]))
        XCTAssertFalse(Transcript.json(entries[0]).contains(#""by""#), "other entries don't change")

        let next = home.sync { h.transcript.append(.event(event(.turnEnd, at: 2, "it ended")), at: Self.t0 + 2 * 60_000) }
        let state = StateText.build(home.sync { h.transcript.entries }, now: next, at: Self.t0 + 2 * 60_000, Self.parts)
        XCTAssertTrue(state.contains("1 min ago: it started\n  Boop did one.\nWorking now"), state)
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
        home.sync {
            h.onRecord = { records.append($0) }
            h.take(event(.turnStart, at: 0, "first"))
            h.take(event(.turnStart, at: 0, "second"))
            let (running, waiting) = (h.running, h.waiting?.seq)
            XCTAssertEqual(h.force(["k": "a"]).count, 1)
            XCTAssertEqual(h.running, running)
            XCTAssertEqual(h.waiting?.seq, waiting)
            XCTAssertEqual(waiting, 2)
            XCTAssertEqual(records.count, 0, "a forced pass isn't one of Jev's")
        }
        gate.signal()
        gate.signal()
        eventually("two passes") { home.sync { records.count } >= 2 }
        XCTAssertEqual(records.map(\.event.line), ["first", "second"], "both of Jev's passes still ran")
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
        home.sync {
            h.onRecord = { records.append($0) }
            h.take(event(.turnStart, at: 0, "first"))
            XCTAssertEqual(h.force(a) { .done("The dashboard did a.") }, .done("The dashboard did a."))
            XCTAssertEqual(h.force(refused) { .failed("not now") }, .failed("not now"), "refused, so it changed nothing")
        }
        gate.signal()
        eventually("the pass") { home.sync { records.count } == 1 }
        XCTAssertEqual(a.got, [], "a sat it out")
        XCTAssertEqual(b.got.count, 1)
        XCTAssertEqual(refused.got.count, 1)
        XCTAssertEqual(records.first?.actions.map(\.name), ["b", "refused"])
        home.sync { h.take(event(.turnEnd, at: 1, "next")) }
        gate.signal()
        eventually("the next pass") { home.sync { records.count } == 2 }
        XCTAssertEqual(a.got.count, 1, "the next pass's state saw the change")
    }

    // MARK: Started actions (HARNESS.md §4–5)

    /// HISTORY as a pass a minute after `t0` would show it, for a NOW that
    /// comes after every entry.
    func history(_ h: Harness, _ home: DispatchQueue) -> String {
        home.sync {
            let now = Transcript.Entry(seq: Int.max, receivedAtMs: Self.t0 + 60_000, body: .event(event(.heartbeat, at: 1, "now")))
            return StateText.history(h.transcript.entries, now: now, at: Self.t0 + 60_000, status: "Working now: nothing else.",
                                     workingSince: nil)
        }
    }

    /// §4, §5.2–5.3: a started result is logged `pending` and shows
    /// `(in progress)` until its handle ends; the end is a `settle` entry
    /// for the action's `seq`, after which the line is plain if it was
    /// done, or says it didn't happen and why. Only the first end counts.
    func testAStartedActionIsInProgressUntilItSettles() async throws {
        let first = Pending()
        let a = Recorder("a", keys: ["k"], result: .started("Boop did it.", first))
        let (h, home) = harness(ScriptedBrain(always: [:]), [a])
        let lines = Lines()
        home.sync { h.onDebugLine = { lines.add($0) } }
        _ = await h.respond(to: event(.turnStart, at: 0, "it started"))
        let action = try XCTUnwrap(lines.all.last)
        XCTAssertTrue(action.contains(#""message":"Boop did it.","name":"a","ok":true,"pending":true},"received_at_ms":1790000000000,"seq":3}"#), action)
        XCTAssertEqual(home.sync { Array(h.open.keys) }, [3])
        XCTAssertEqual(history(h, home), """
            HISTORY (oldest first; indented lines are what Boop did)
            1 min ago: it started
              Boop did it. (in progress)
            Working now: nothing else.
            """)

        home.sync { first.finish(.done) }
        XCTAssertEqual(lines.all.last, #"{"received_at_ms":1790000000000,"seq":4,"settle":{"end":"done","for":3}}"#)
        XCTAssertEqual(home.sync { h.transcript.entries.last?.body }, .settle(.init(forSeq: 3, end: .done)))
        XCTAssertTrue(home.sync { h.open.isEmpty })
        XCTAssertTrue(history(h, home).contains("\n  Boop did it.\nWorking now"), "the marker is gone")
        home.sync { first.finish(.failed("too late")) }
        XCTAssertEqual(home.sync { h.transcript.entries.count }, 4, "only the first end counts")

        let second = Pending()
        a.result = .started("Boop did it again.", second)
        _ = await h.respond(to: event(.turnEnd, at: 0, "it ended"))
        home.sync { second.finish(.failed("waited too long")) }
        XCTAssertEqual(lines.all.last, #"{"received_at_ms":1790000000000,"seq":8,"settle":{"end":"failed","for":7,"why":"waited too long"}}"#)
        XCTAssertEqual(history(h, home), """
            HISTORY (oldest first; indented lines are what Boop did)
            1 min ago: it started
              Boop did it.
            1 min ago: it ended
              Boop did it again. (didn't happen: waited too long)
            Working now: nothing else.
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
        _ = await h.respond(to: event(.turnStart, at: 0, "it started"))
        let bodies = home.sync { h.transcript.entries.map(\.body) }
        XCTAssertEqual(bodies.count, 4, "the event, the pass, the action and its settle")
        XCTAssertEqual(bodies.last, .settle(.init(forSeq: 3, end: .failed("no device connected"))))
        XCTAssertTrue(home.sync { h.open.isEmpty })
        XCTAssertTrue(history(h, home).contains("\n  Boop did it. (didn't happen: no device connected)\n"))
    }

    /// §5.1: a started action still in progress a minute
    /// (`Harness.pendingMaxMs`) after its result is ended as failed, and
    /// logged; its own end after that is ignored. A forced one is started
    /// and ended as Jev's are, and its settle is by the dashboard too.
    func testAnActionStillInProgressAfterAMinuteIsEnded() {
        XCTAssertEqual(Harness.pendingMaxMs, 60_000)
        let pending = Pending()
        let a = Recorder("a", keys: ["k"], result: .started("Boop did it.", pending))
        let home = DispatchQueue(label: "test.home")
        let log = Lines()
        let h = Harness(brain: nil, actions: [a], parts: { _ in Self.parts }, home: home, clock: { harnessT0 },
                        log: { log.add($0) })
        let lines = Lines()
        home.sync {
            h.onDebugLine = { lines.add($0) }
            h.take(event(.turnStart, at: 0, "it started"))
            XCTAssertEqual(h.force(["k": "a"]).count, 1)
        }
        XCTAssertTrue(lines.all.last?.contains(#""pending":true"#) == true)
        XCTAssertTrue(history(h, home).contains("\n  Boop did it. (in progress)\n"), "a forced one too")
        home.sync { h.tick(now: harnessT0 + 59_999) }
        XCTAssertEqual(home.sync { Array(h.open.keys) }, [3], "still open at 59,999 ms")
        home.sync { h.tick(now: harnessT0 + 60_000) }
        XCTAssertTrue(home.sync { h.open.isEmpty }, "ended at 60,000 ms")
        XCTAssertEqual(lines.all.last, #"{"received_at_ms":1790000000000,"seq":4,"settle":{"by":"dashboard","end":"failed","for":3,"why":"no word it finished"}}"#)
        XCTAssertEqual(log.all, ["harness: a was still in progress after 60000 ms; ended it"])
        XCTAssertTrue(history(h, home).contains("\n  Boop did it. (didn't happen: no word it finished)\n"))
        home.sync {
            pending.finish(.done)
            h.tick(now: harnessT0 + 120_000)
        }
        XCTAssertEqual(home.sync { h.transcript.entries.count }, 4, "ended once")

        // One forced action on its own, as the dashboard's mood is.
        let alone = Pending()
        home.sync {
            XCTAssertNotNil(h.force(a) { .started("Boop did that.", alone) })
            alone.finish(.done)
        }
        XCTAssertEqual(lines.all.last, #"{"received_at_ms":1790000000000,"seq":6,"settle":{"by":"dashboard","end":"done","for":5}}"#)
    }

    /// §5.3, §9: a replay rebuilds a logged pass's state exactly from the
    /// log's entries up to the pass line's `seen`, a started action and its
    /// settle included, and leaves out a settle recorded while the brain
    /// answered, which lands before the pass line but wasn't in its state.
    func testALoggedStateIsRebuiltFromTheLogWithItsSettles() async throws {
        let pending = Pending(), during = Pending()
        let home = DispatchQueue(label: "test.home")
        // The second pass's brain hears the first action end while it answers.
        let brain = ScriptedBrain { state, _ in
            if state.contains("\nit ended\n") { home.sync { during.finish(.done) } }
            return [:]
        }
        let started = Recorder("a", keys: ["k"], result: .started("Boop did it.", pending))
        let h = Harness(brain: brain, actions: [started], parts: { _ in Self.parts }, home: home, clock: { harnessT0 })
        let lines = Lines()
        home.sync { h.onDebugLine = { lines.add($0) } }
        _ = await h.respond(to: event(.turnStart, at: -3, "it started"))
        home.sync { pending.finish(.failed("the device disconnected")) }
        started.result = .started("Boop did more.", during)
        _ = await h.respond(to: event(.toolUse, at: -2, "it went on"))
        started.result = nil
        _ = await h.respond(to: event(.turnEnd, at: 0, "it ended", reaction: "Boop cheered on its own."))
        let objects = lines.all.map { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let (i, pass) = try XCTUnwrap(objects.enumerated().compactMap { i, o in (o?["pass"] as? [String: Any]).map { (i, $0) } }.last)
        let logged = try XCTUnwrap(pass["state"] as? String)
        XCTAssertTrue(logged.contains("3 min ago: it started\n  Boop did it. (didn't happen: the device disconnected)\n"), logged)
        XCTAssertTrue(logged.contains("  Boop did more. (in progress)\n"), "its settle came while the brain answered: \(logged)")
        let before = Self.entries(fromLog: Array(lines.all[..<i]))
        XCTAssertTrue(before.contains { if case .settle(let s) = $0.body { s.end == .done } else { false } }, "logged before the pass")
        let seen = try XCTUnwrap(pass["seen"] as? Int)
        let entries = before.filter { $0.seq <= seen }
        let now = try XCTUnwrap(entries.first { $0.seq == pass["for"] as? Int })
        XCTAssertEqual(StateText.build(entries, now: now, at: harnessT0, Self.parts), logged)
        XCTAssertNotEqual(StateText.build(before, now: now, at: harnessT0, Self.parts), logged, "without `seen`, not exact")
    }

    /// Transcript entries back from `debug.jsonl` lines, as far as the
    /// state needs them: what a replay of the log reads.
    static func entries(fromLog lines: [String]) -> [Transcript.Entry] {
        lines.compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let seq = o["seq"] as? Int,
                  let ms = (o["received_at_ms"] as? NSNumber)?.int64Value else { return nil }
            let body: Transcript.Body
            if let e = o["event"] as? [String: Any], let kind = Event.Kind(rawValue: e["kind"] as? String ?? "") {
                body = .event(Event(kind, at: ms, line: e["line"] as? String ?? "", reaction: e["reaction"] as? String,
                                    wakesBrain: e["wakes_brain"] as? Bool ?? false))
            } else if let p = o["pass"] as? [String: Any] {
                body = .pass(.init(forSeq: p["for"] as? Int, answers: [:], dropped: p["dropped"] as? String, latencyMs: 0))
            } else if let a = o["action"] as? [String: Any] {
                let message = a["message"] as? String ?? ""
                let result: ActionResult = a["ok"] as? Bool != true ? .failed(message)
                    : a["pending"] as? Bool == true ? .started(message, Pending()) : .done(message)
                body = .action(.init(forSeq: a["for"] as? Int, name: a["name"] as? String ?? "", result: result, latencyMs: 0))
            } else if let s = o["settle"] as? [String: Any], let action = s["for"] as? Int {
                body = .settle(.init(forSeq: action, end: s["end"] as? String == "done" ? .done : .failed(s["why"] as? String ?? "")))
            } else {
                return nil
            }
            return Transcript.Entry(seq: seq, receivedAtMs: ms, body: body)
        }
    }

    // MARK: The debug log (HARNESS.md §9)

    /// The printer reads transcript entries as it always has, a started
    /// action with `…` and a settle by its action's name, and skips the
    /// dashboard's lines.
    func testThePrinterSkipsTheDashboardsLines() {
        let printer = DebugLog.Printer()
        let stateJSON = #"You are.\nPERSONALITY\nx\n\nHISTORY (oldest first)\nh\n\nNOW (14:23, Tuesday)\nn"#
        let lines: [(String, String?)] = [
            (#"{"event":{"facts":{},"kind":"turn_end","line":"claude finished turn 1.","reaction":"Boop cheered on its own.","wakes_brain":true},"received_at_ms":5,"seq":3}"#,
             "▸ 3 turn_end: claude finished turn 1.\n    Boop cheered on its own."),
            (#"{"event":{"facts":{},"kind":"tap","line":"You tapped Boop.","reaction":null,"wakes_brain":false},"received_at_ms":6,"seq":4}"#,
             "▸ 4 tap (no pass): You tapped Boop."),
            (#"{"pass":{"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.9,"grumpy":0.1}},"react":{"choice":"excited","p":{"excited":1}}},"brain":"scripted","dropped":null,"for":3,"latency_ms":12,"questions":["mood","react"],"state":""# + stateJSON + #""},"received_at_ms":7,"seq":5}"#,
             "  pass scripted 12 ms: mood cheerful 0.90 · react excited 1.00\n    │ You are.\n    │ PERSONALITY\n    │ x\n    │ \n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"pass":{"answers":{},"brain":"jev:jev-latest","dropped":"late: no answer within 1250 ms","for":3,"latency_ms":1250,"questions":["mood"],"state":""# + stateJSON + #""},"received_at_ms":8,"seq":6}"#,
             "  pass jev:jev-latest 1250 ms: dropped: late: no answer within 1250 ms\n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"action":{"for":3,"latency_ms":0,"message":"Boop made an excited face and mumbled \"…yay!\"","name":"react","ok":true},"received_at_ms":9,"seq":7}"#,
             "  ✓ react: Boop made an excited face and mumbled \"…yay!\""),
            (#"{"action":{"for":3,"latency_ms":0,"message":"changed 3 min ago","name":"mood","ok":false},"received_at_ms":9,"seq":8}"#,
             "  ✗ mood: changed 3 min ago"),
            ("not json", "not json"),
            (#"{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":9}"#, nil),
            (#"{"status":{"brain":"none","connected":false,"mood":"cheerful","personality":"boop","sessions":[]},"received_at_ms":9}"#, nil),
            (#"{"questions":[],"received_at_ms":9}"#, nil),
            (#"{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react"]},"received_at_ms":10,"seq":9}"#,
             "  pass dashboard 0 ms: react grumpy 1.00"),
            (#"{"action":{"for":3,"latency_ms":0,"message":"Boop made an excited face and mumbled \"…yay!\"","name":"react","ok":true,"pending":true},"received_at_ms":11,"seq":10}"#,
             "  … react: Boop made an excited face and mumbled \"…yay!\""),
            (#"{"received_at_ms":12,"seq":11,"settle":{"end":"done","for":10}}"#, "  ✓ react (10) done"),
            (#"{"received_at_ms":13,"seq":12,"settle":{"by":"dashboard","end":"failed","for":10,"why":"waited too long"}}"#,
             "  ✗ react (10) didn't happen: waited too long"),
            (#"{"received_at_ms":14,"seq":13,"settle":{"end":"done","for":2}}"#, "  ✓ ? (2) done"),
        ]
        for (line, readable) in lines { XCTAssertEqual(printer.readable(line), readable, line) }
    }

    func testQuestionKeysMustBeUniqueAcrossActions() {
        XCTAssertEqual(Set(Self.realActions().flatMap { $0.questions().map(\.key) }).count, 5)
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
        XCTAssertNil(react.run(["react": a("none")]))
        starts(["react": a("grumpy"), "word.feeling": a("again", 0.57), "word.about": a("tests", 0.81),
                "react.loops": a("twice")],
               #"Boop made a grumpy face, held twice, and mumbled "…again!""#)
        starts(["react": a("curious"), "word.feeling": a("again", 0.31), "word.about": a("tests", 0.79)],
               #"Boop made a curious face, held once, and mumbled "…tests!""#)
        starts(["react": a("happy"), "word.feeling": a("none"), "word.about": a("docs", 0.2), "react.loops": a("four times")],
               "Boop made a happy face, held four times, and mumbled.")
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(Set(queued.map { ObjectIdentifier($0.pending) }).count, 3, "a handle each")
        XCTAssertEqual(sent[0].say?.word, "again")
        XCTAssertNil(sent[0].anim, "a mumble plays over the face")
        XCTAssertEqual(sent.map(\.mood), ["grumpy", "curious", "happy"], "each wears its face")
        XCTAssertEqual(sent.map(\.loops), [2, 1, 4], "for its loops")
        XCTAssertEqual(sent[0].say?.tune, .flat, "grumpy mumbles in annoyed's voice")
        XCTAssertTrue(sent[0].jsonLine.hasSuffix(#","mood":"grumpy","loops":2}"#), sent[0].jsonLine)
        XCTAssertNil(react.run(["react": a("annoyed")]), "annoyed was a feeling, not a face")
        starts(["react": a("excited"), "react.loops": a("three times")], "Boop made an excited face, held three times, and mumbled.")
        XCTAssertEqual(queued.last?.moment.loops, 3)
        queued.removeLast()
        why = "something needs you"
        for expression in ReactAction.expressions.map(\.name) {
            XCTAssertEqual(react.run(["react": a(expression)]), .failed("something needs you"))
        }
        XCTAssertEqual(sent.count, 3, "no face or mumble while something needs you")
        XCTAssertEqual(react.questions().map(\.key), ["react", "react.loops", "word.feeling", "word.about"])
        XCTAssertEqual(react.questions()[0].options.map(\.name), ["none"] + MoodAction.moods.map(\.name),
                       "the faces are the seven moods'")
        XCTAssertEqual(react.questions()[1].options.map(\.name), ["once", "twice", "three times", "four times"])
        XCTAssertEqual(react.questions()[2].options.map(\.name), ["none", "finally", "yay", "oops", "again", "ugh", "nope", "hmm"])
        XCTAssertEqual(react.questions()[3].options.map(\.name), ["none", "tests", "build", "deploy", "docs"])
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
        XCTAssertEqual(voices, ["happy": .happy, "excited": .excited, "proud": .proud, "curious": .curious,
                                "determined": .happy, "grumpy": .annoyed, "sad": .sad])
    }

    /// PROTOCOL.md §3: only the brain's mumbles carry an expression; the
    /// rules' moments (the cheer, a wiggle, working chatter) never do.
    func testRuleMomentsCarryNoExpression() {
        XCTAssertEqual(DeviceMoment(anim: "cheer").jsonLine, #"{"t":"moment","anim":"cheer"}"#)
        let line = VoiceLine(groups: [["bi", "da"]], word: nil, at: 2, tune: .bounce, ms: 125)
        XCTAssertEqual(DeviceMoment(say: line).jsonLine, #"{"t":"moment","say":{"syl":"bi-da","tune":"bounce","ms":125}}"#)
        XCTAssertEqual(DeviceMoment(say: line, mood: "grumpy").jsonLine,
                       #"{"t":"moment","say":{"syl":"bi-da","tune":"bounce","ms":125},"mood":"grumpy"}"#)
    }

    /// DECISIONS.md §4: the seven moods; the current mood is nothing to do,
    /// and any other changes the file, and MOOD with it, however recently
    /// it last changed (how long a mood lasts is the steering's call).
    func testMood() throws {
        XCTAssertEqual(MoodAction.moods.map(\.name), ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"])
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
        try Data("delighted\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "an unknown one reads as happy")
    }

    /// DECISIONS.md §4, DASHBOARD.md §4: the mood the dashboard sets
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
        let answers = try await jev.answer(state: "s", questions: q, deadline: .milliseconds(1250))
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
            _ = try await down.answer(state: "s", questions: q, deadline: .milliseconds(1250))
            XCTFail("no answer")
        } catch let error as BrainError {
            XCTAssertEqual(error.description, "jev: HTTP 500", "only the status")
        }
    }

    /// The transcript keeps its newest thousand entries.
    func testTheTranscriptLetsTheOldestGo() {
        let t = Transcript()
        for i in 0..<1005 { t.append(.event(event(.tap, at: 0, "\(i)", wakes: false)), at: 0) }
        XCTAssertEqual(t.entries.count, 1000)
        XCTAssertEqual(t.entries.first?.seq, 6)
    }
}
