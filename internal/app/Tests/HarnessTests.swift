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
        t.append(.action(.init(forSeq: failed.seq, name: "react", result: .done(#"Boop mumbled, annoyed: "…tests!""#), latencyMs: 1)), at: Self.t0)
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
              Boop mumbled, annoyed: "…tests!"
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

    // MARK: The harness

    func harness(_ brain: (any Brain)?, _ actions: [any Action]) -> (Harness, DispatchQueue) {
        let home = DispatchQueue(label: "test.home")
        let h = Harness(brain: brain, actions: actions, parts: { _ in Self.parts }, home: home, clock: { harnessT0 })
        return (h, home)
    }

    /// HARNESS.md §3–4: one request with every action's questions; each
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

    /// HARNESS.md §3: one pass runs at a time, and a newer event replaces
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
        let deadline = Date().addingTimeInterval(3)
        while home.sync(execute: { records.count }) < 2 && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(seen.all, ["first", "third"], "second was replaced while it waited")
        home.sync {
            XCTAssertTrue(h.idle)
            XCTAssertEqual(h.transcript.entries.filter { if case .event = $0.body { true } else { false } }.count, 3)
        }
    }

    func testQuestionKeysMustBeUniqueAcrossActions() {
        XCTAssertEqual(Set(Self.realActions().flatMap { $0.questions().map(\.key) }).count, 4)
    }

    static func realActions() -> [any Action] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-mood-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return [MoodAction(store: MoodStore(stateDir: dir)),
                ReactAction(voice: Voice(dialect: Dialect(seed: 1)), queue: { _ in }, blocked: { nil })]
    }

    // MARK: The actions (DECISIONS.md §4–5)

    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// DECISIONS.md §5: `none` does nothing; the word is the exclamation
    /// over 0.35, else the topic, else none; a blocked mumble fails.
    func testReact() {
        XCTAssertEqual(ReactAction.wordFloor, 0.35)
        var sent: [DeviceMoment] = []
        var why: String?
        let react = ReactAction(voice: Voice(dialect: Dialect(seed: 1)), queue: { sent.append($0) }, blocked: { why })
        XCTAssertNil(react.run(["react": a("none")]))
        XCTAssertEqual(react.run(["react": a("annoyed"), "word.feeling": a("again", 0.57), "word.about": a("tests", 0.81)]),
                       .done(#"Boop mumbled, annoyed: "…again!""#))
        XCTAssertEqual(react.run(["react": a("curious"), "word.feeling": a("again", 0.31), "word.about": a("tests", 0.79)]),
                       .done(#"Boop mumbled, curious: "…tests!""#))
        XCTAssertEqual(react.run(["react": a("happy"), "word.feeling": a("none"), "word.about": a("docs", 0.2)]),
                       .done("Boop mumbled, happy."))
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0].say?.word, "again")
        XCTAssertNil(sent[0].anim, "a mumble plays over the face")
        why = "something needs you"
        XCTAssertEqual(react.run(["react": a("proud")]), .failed("something needs you"))
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(react.questions().map(\.key), ["react", "word.feeling", "word.about"])
        XCTAssertEqual(react.questions()[0].options.map(\.name), ["none", "happy", "excited", "proud", "curious", "annoyed"])
        XCTAssertEqual(react.questions()[1].options.map(\.name), ["none", "finally", "yay", "oops", "again", "ugh", "nope", "hmm"])
        XCTAssertEqual(react.questions()[2].options.map(\.name), ["none", "tests", "build", "deploy", "docs"])
        for word in ReactAction.exclamations.map(\.name) + ReactAction.topics.map(\.name) {
            XCTAssertTrue(Sounds.vocabulary.contains(word), "\(word) is one of Voice's words")
        }
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
        let mood = MoodAction(store: store)
        XCTAssertNil(mood.run(["mood": a("happy")]))
        XCTAssertEqual(mood.run(["mood": a("determined")]), .done("Boop's mood changed: happy → determined."))
        XCTAssertEqual(mood.run(["mood": a("proud")]), .done("Boop's mood changed: determined → proud."), "straight after, too")
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("mood"), encoding: .utf8), "proud\n")
        XCTAssertNil(mood.run(["mood": a("sulky")]), "not a mood")
        try Data("grumpy\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "grumpy", "it survives a restart")
        try Data("cheerful\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "cheerful, its old name, reads as happy")
        try Data("delighted\n".utf8).write(to: dir.appendingPathComponent("mood"))
        XCTAssertEqual(MoodStore(stateDir: dir).current, "happy", "an unknown one reads as happy")
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
