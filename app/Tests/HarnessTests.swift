import Foundation
import XCTest
@testable import BoopKit

/// A classifier that answers from a script, after a delay, and keeps what it saw.
final class FakeClassifier: Classifier, @unchecked Sendable {
    let id = "fake-classifier@1"
    let delayMs: Int
    let answer: @Sendable (Input) throws -> [ToolCall]
    let lock = NSLock()
    var seen: [Context] = []

    init(delayMs: Int = 0, _ answer: @escaping @Sendable (Input) throws -> [ToolCall]) {
        self.delayMs = delayMs
        self.answer = answer
    }

    func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        lock.withLock { seen.append(context) }
        if delayMs > 0 { try await Task.sleep(for: .milliseconds(delayMs)) }
        return Classification(calls: try answer(context.input), evidence: "scripted")
    }
}

/// A writer that fills slots from a script, and keeps what it was asked.
final class FakeWriter: Writer, @unchecked Sendable {
    let id = "fake-writer@1"
    let answer: @Sendable ([Slot]) throws -> [String: String]
    let lock = NSLock()
    var asked: [(context: Context, slots: [Slot])] = []

    init(_ answer: @escaping @Sendable ([Slot]) throws -> [String: String] = { _ in [:] }) {
        self.answer = answer
    }

    func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        lock.withLock { asked.append((context, slots)) }
        return Writing(values: try answer(slots), raw: "scripted")
    }

    var calls: Int { lock.withLock { asked.count } }
}

/// Records what the harness hands off, touched only on the harness's queue.
final class HarnessRig: @unchecked Sendable {
    let home = DispatchQueue(label: "test.harness")
    var handled: [ToolCall] = []
    var records: [Harness.Record] = []
    var logs: [String] = []
    var memory = Prompt.Memory(steering: "# Boop\n", longTerm: "## Boop\n", shortTerm: "## Today\n")
    var harness: Harness!

    init(classifier: any Classifier, writer: any Writer = FakeWriter(), debugLog: URL? = nil) {
        let tools = [
            ToolDefinition(name: "react", description: "React.", parameters: [
                .init("feeling", .choice(["happy", "sulky", "proud"])),
                .init("word", .choice(["hi", "finally"]), optional: true, role: .written),
            ]),
            ToolDefinition(name: "quiet", description: "Quiet.", parameters: [.init("minutes", .number([15, 30]))]),
            ToolDefinition(name: "remember", description: "Remember.", parameters: [
                .init("where", .choice(["today", "about_you", "preference"])),
                .init("text", .text(maxLength: 20, by: "where", limits: ["today": 10]), role: .written),
            ]),
        ].map { d in Harness.Tool(definition: d, handle: { [unowned self] call in handled.append(call); return .done("ok") }) }
        harness = Harness(classifier: classifier, writer: writer, tools: tools, memory: { [unowned self] _ in self.memory },
                          home: home, debugLog: debugLog, log: { [unowned self] in logs.append($0) })
        harness.onRecord = { [unowned self] in records.append($0) }
    }

    func submit(_ input: Input) { home.sync { harness.submit(input) } }

    /// Waits until nothing is running or waiting.
    func settle(timeoutMs: Int = 3000) async {
        for _ in 0..<(timeoutMs / 10) {
            if home.sync(execute: { harness.idle }) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("harness didn't settle")
    }

    var snapshot: (handled: [ToolCall], records: [Harness.Record]) { home.sync { (handled, records) } }
    var entries: [Transcript.Entry] { home.sync { harness.transcript.entries } }
}

func input(_ kind: Input.Kind, words: String? = nil, yelled: Bool = false, outcome: Input.Outcome? = nil,
           tookMs: Int64? = nil, rules: String? = nil, at minutes: Double = 0) -> Input {
    Input(kind, agent: kind == .agentStarted || kind == .agentFinished ? "claude" : nil,
          project: kind == .agentStarted || kind == .agentFinished ? "jetpack" : nil,
          outcome: kind == .agentFinished ? outcome ?? .done : nil, tookMs: tookMs, words: words, yelled: yelled,
          clock: "14:05", weekday: "Tuesday", rules: rules, ts: Int64(minutes * 60_000))
}

final class HarnessTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let steering = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../plan/steering.md").standardizedFileURL

    func run(_ rig: HarnessRig, _ inputs: [Input]) async -> [Harness.Record] {
        for i in inputs {
            rig.submit(i)
            await rig.settle()
        }
        return rig.snapshot.records
    }

    // MARK: One pass

    /// HARNESS.md §3: Stage 1's calls run in the menu's order (quiet, react,
    /// remember), with Stage 2's words filled in.
    func testCallsRunInTheMenusOrderWithTheirWords() async {
        let writer = FakeWriter { slots in Dictionary(uniqueKeysWithValues: slots.map { ($0.key, $0.key == "react.word" ? "hi" : "demo Thu") }) }
        let rig = HarnessRig(classifier: FakeClassifier { _ in
            [remember("today"), react("happy"), ToolCall("quiet", ["minutes": .number(30)])]
        }, writer: writer)
        let records = await run(rig, [input(.said, words: "be quiet, and remember the demo")])
        XCTAssertEqual(rig.snapshot.handled, [ToolCall("quiet", ["minutes": .number(30)]), react("happy", word: "hi"),
                                              remember("today", "demo Thu")])
        XCTAssertEqual(records[0].slots, ["react.word", "remember.text"])
        XCTAssertEqual(records[0].wrote, ["react.word": "hi", "remember.text": "demo Thu"])
        XCTAssertTrue(records[0].answered)
        XCTAssertEqual(records[0].logLine, "brain you said \(records[0].latencyMs) ms → quiet, react, remember")
    }

    /// HARNESS.md §3 step 5: Stage 2 runs only when something needs words.
    func testAQuietNeedsNoWriter() async {
        let writer = FakeWriter()
        let rig = HarnessRig(classifier: FakeClassifier { _ in [ToolCall("quiet", ["minutes": .number(15)])] }, writer: writer)
        _ = await run(rig, [input(.said, words: "be quiet")])
        XCTAssertEqual(writer.calls, 0)
        XCTAssertEqual(rig.snapshot.handled.count, 1)
    }

    /// The writer sees everything: the input, the rules' reaction, and
    /// Stage 1's decision it's writing for.
    func testTheWriterSeesTheDecision() async throws {
        let writer = FakeWriter { _ in ["react.word": "finally"] }
        let rig = HarnessRig(classifier: FakeClassifier { _ in [react("proud")] }, writer: writer)
        let finished = input(.agentFinished, tookMs: 1_080_000, rules: "cheer")
        _ = await run(rig, [finished])
        let asked = try XCTUnwrap(writer.asked.first)
        XCTAssertEqual(asked.context.window, [.input(finished), .rules("cheer"),
                                              .decided(by: "fake-classifier@1", [react("proud")], evidence: "scripted")])
        XCTAssertEqual(asked.slots.map(\.key), ["react.word"])
        XCTAssertEqual(asked.slots[0].kind, .word(["hi", "finally"]))
        XCTAssertEqual(rig.entries.suffix(2), [.wrote(by: "fake-writer@1", ["react.word": "finally"]),
                                               .ran(react("proud", word: "finally"), .done("ok"))])
    }

    /// HARNESS.md §3 step 4: one bad call drops them all.
    func testCallsOffTheMenuAreAllDropped() async {
        let cases: [(Input, [ToolCall], String)] = [
            (input(.agentFinished), [react("happy"), ToolCall("quiet", ["minutes": .number(15)])], "quiet isn't on the menu"),
            // HARNESS.md §2: quiet is on the menu only when the words ask for it.
            (input(.said, words: "shut up"), [ToolCall("quiet", ["minutes": .number(15)])], "quiet isn't on the menu"),
            (input(.said), [react("happy", word: "hi")], "react: word is the writer's"),
            (input(.said), [remember("moment")], "remember: where isn't one of its choices"),
            (input(.said), [remember("today", "x")], "remember: text is the writer's"),
            (input(.said), [react("happy"), react("happy")], "react twice"),
            (input(.said), [react("happy"), react("sulky")], "react twice"),
            (input(.said), [react("angry")], "react: feeling isn't one of its choices"),
            (input(.said), [ToolCall("react")], "react: feeling is missing"),
        ]
        for (i, calls, why) in cases {
            let rig = HarnessRig(classifier: FakeClassifier { _ in calls })
            let records = await run(rig, [i])
            XCTAssertEqual(records.first?.dropped, "off the menu: \(why)")
            XCTAssertEqual(rig.snapshot.handled, [])
            XCTAssertEqual(rig.entries.last, .dropped("off the menu: \(why)"))
        }
    }

    /// A line left empty drops only its own call.
    func testAnEmptyLineDropsOnlyItsCall() async {
        let writer = FakeWriter { _ in ["react.word": "hi"] }
        let rig = HarnessRig(classifier: FakeClassifier { _ in [react("happy"), remember("today")] }, writer: writer)
        let records = await run(rig, [input(.said, words: "remember")])
        XCTAssertEqual(records[0].slots, ["react.word", "remember.text"])
        XCTAssertEqual(records[0].ran.map(\.outcome), [.done("ok"), .dropped("nothing was written")])
        XCTAssertEqual(rig.snapshot.handled, [react("happy", word: "hi")])
    }

    /// A text that doesn't fit its section's limit counts as empty.
    func testWordsThatDontFitAreLeftEmpty() async {
        let writer = FakeWriter { _ in ["react.word": "kubernetes", "remember.text": "far too long for today"] }
        let rig = HarnessRig(classifier: FakeClassifier { _ in [react("happy"), remember("today")] }, writer: writer)
        let records = await run(rig, [input(.said, words: "hi")])
        XCTAssertEqual(records[0].wrote, ["react.word": "", "remember.text": ""])
        XCTAssertEqual(rig.snapshot.handled, [react("happy")])
    }

    /// HARNESS.md §3: when Stage 2 fails, a mumble goes without its word and
    /// nothing is remembered.
    func testAFailedWriterLeavesEverySlotEmpty() async {
        let writer = FakeWriter { _ in throw BrainError("offline") }
        let rig = HarnessRig(classifier: FakeClassifier { _ in [react("happy"), remember("today")] }, writer: writer)
        let records = await run(rig, [input(.said, words: "remember x")])
        XCTAssertEqual(records[0].writeFailed, "offline")
        XCTAssertEqual(rig.snapshot.handled, [react("happy")])
        XCTAssertEqual(records[0].ran.last?.outcome, .dropped("nothing was written"))
        XCTAssertTrue(rig.entries.contains(.writeFailed(by: "fake-writer@1", "offline")))
        XCTAssertTrue(records[0].logLine.hasSuffix("→ react, remember (dropped) (writer failed: offline)"), records[0].logLine)
    }

    func testClassifierErrorsAndLateAnswersAreDropped() async {
        let failing = HarnessRig(classifier: FakeClassifier { _ in throw BrainError("offline") })
        let records = await run(failing, [input(.agentStarted)])
        XCTAssertEqual(records.first?.dropped, "offline")
        XCTAssertEqual(failing.entries.last, .dropped("offline"))

        // Work that ignores its deadline: the answer comes too late.
        let start = ContinuousClock.now
        let late: Result<Int, BrainError> = await Harness.race(50) {
            try await Task.sleep(for: .seconds(60))
            return 1
        }
        XCTAssertEqual(late.failureReason, "late: no answer within 50 ms")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testStayingQuietIsNoCalls() async {
        let rig = HarnessRig(classifier: FakeClassifier { _ in [] })
        let records = await run(rig, [input(.agentStarted)])
        XCTAssertTrue(records[0].silent)
        XCTAssertTrue(records[0].logLine.hasSuffix(" ms → nothing"), records[0].logLine)
        XCTAssertEqual(rig.entries.last, .decided(by: "fake-classifier@1", [], evidence: "scripted"))
    }

    // MARK: Scheduling

    func testANewerInputReplacesTheWaitingOne() async {
        let rig = HarnessRig(classifier: FakeClassifier(delayMs: 150) { i in i.kind == .agentFinished ? [react("happy")] : [] })
        rig.submit(input(.agentStarted))
        rig.submit(input(.agentStarted))
        rig.submit(input(.agentFinished))
        await rig.settle()
        let records = rig.snapshot.records
        XCTAssertEqual(records.map(\.input.kind), [.agentStarted, .agentFinished])
        XCTAssertEqual(rig.snapshot.handled, [react("happy")])
        XCTAssertTrue(rig.home.sync { rig.logs.contains("harness: agent started replaced by a newer agent finished") })
    }

    /// HARNESS.md §4: asides don't move the window, so at most eight follow
    /// an input; a burst of taps can't crowd out the prompt.
    func testABurstOfAsidesIsCapped() async {
        let rig = HarnessRig(classifier: FakeClassifier { _ in [] })
        for i in 0..<30 { rig.home.sync { rig.harness.note("tapped \(i)", at: Int64(i)) } }
        XCTAssertEqual(rig.entries.count, Transcript.asidesPerInput)
        _ = await run(rig, [input(.agentStarted)])
        rig.home.sync { rig.harness.note("tapped again", at: 99) }
        XCTAssertTrue(rig.entries.contains(.aside("tapped again", ts: 99)), "an input makes room again")
    }

    func testYouTalkingCancelsWhateverIsRunning() async {
        let rig = HarnessRig(classifier: FakeClassifier(delayMs: 300) { i in
            i.kind == .said ? [react("sulky")] : [react("happy")]
        })
        rig.submit(input(.agentStarted))
        try? await Task.sleep(for: .milliseconds(50))
        rig.submit(input(.said, words: "hush"))
        await rig.settle()
        try? await Task.sleep(for: .milliseconds(400)) // the cancelled pass's answer would be in by now
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [react("sulky")])
        XCTAssertEqual(records.map(\.input.kind), [.agentStarted, .said])
        XCTAssertEqual(records[0].dropped, "cancelled by you talking")
        XCTAssertTrue(rig.entries.contains(.dropped("cancelled by you talking")))
    }

    /// Taps and "needs you" go in the transcript, and start no pass.
    func testAsidesJoinTheTranscriptOnly() async {
        let classifier = FakeClassifier { _ in [] }
        let rig = HarnessRig(classifier: classifier)
        rig.home.sync { rig.harness.note("tapped · 14:07 Tuesday: Boop wiggled", at: 60_000) }
        _ = await run(rig, [input(.agentStarted, at: 2)])
        XCTAssertEqual(rig.snapshot.records.count, 1)
        XCTAssertEqual(classifier.seen.first?.window.first, .aside("tapped · 14:07 Tuesday: Boop wiggled", ts: 60_000))
    }

    /// BEHAVIORS.md §6: a new mode's brains take the next pass; one already
    /// running finishes with the brains it started with.
    func testNewBrainsTakeTheNextPass() async {
        let old = FakeClassifier(delayMs: 200) { _ in [react("happy")] }
        let new = FakeClassifier { _ in [react("sulky")] }
        let rig = HarnessRig(classifier: old)
        rig.submit(input(.agentStarted))
        rig.home.sync { rig.harness.use(new, FakeWriter()) }
        rig.submit(input(.agentFinished))
        await rig.settle()
        XCTAssertEqual(rig.snapshot.handled, [react("happy"), react("sulky")])
        XCTAssertEqual(old.seen.count, 1)
        XCTAssertEqual(new.seen.map(\.input.kind), [.agentFinished])
    }

    // MARK: Logging

    func testDebugModeLogsOneJSONLinePerPass() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("boop-harness-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: log) }
        let rig = HarnessRig(classifier: FakeClassifier { _ in [react("proud")] }, writer: FakeWriter { _ in ["react.word": "finally"] },
                             debugLog: log)
        _ = await run(rig, [input(.agentFinished, tookMs: 600_000), input(.said, words: "hi")])
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        XCTAssertEqual(first["classifier"] as? String, "fake-classifier@1")
        XCTAssertEqual(first["writer"] as? String, "fake-writer@1")
        XCTAssertEqual(first["decided"] as? [String], ["react(feeling: proud)"])
        XCTAssertEqual(first["wrote"] as? [String: String], ["react.word": "finally"])
        XCTAssertEqual(first["window"] as? Int, 1)
        XCTAssertEqual((first["input"] as? [String: Any])?["line"] as? String,
                       "agent finished · done · claude · jetpack · a very long turn (10 min) · 14:05 Tuesday")
        XCTAssertNotNil(first["latency_ms"])
        let second = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as! [String: Any]
        XCTAssertEqual(second["window"] as? Int, 2)
    }

    func testWithoutDebugModeNothingIsWritten() async {
        let rig = HarnessRig(classifier: FakeClassifier { _ in [] })
        XCTAssertNil(rig.harness.debugLog)
        _ = await run(rig, [input(.agentStarted)])
        XCTAssertEqual(rig.snapshot.records.count, 1)
    }

    /// HARNESS.md §8: outside debug mode "the words you said and what the
    /// brain answered never reach the log". The app's log gets each pass's
    /// line, the harness's own lines and every action's drop reasons: they
    /// name outputs and reasons, never an argument's text.
    func testTheLogNeverGetsWhatYouSaid() async throws {
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var all: [String] = []
            func add(_ line: String) { lock.withLock { all.append(line) } }
        }
        let said = "PRIVATE_sam moves to Lisbon"
        // A note that's kept, then the same note again, which the store
        // refuses, then one it refuses as code.
        let notes = [said, said, said + " `x`"]
        let memory = try MemoryRig()
        let lines = Lines()
        for note in notes {
            let context = ActionContext(send: { _ in }, today: { "2026-10-14" }, log: lines.add)
            let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
            let harness = Harness(classifier: FakeClassifier { _ in [react("happy"), remember("today")] },
                                  writer: FakeWriter { _ in ["react.word": "hi", "remember.text": note] },
                                  tools: actions.map(Harness.Tool.init), memory: { _ in memory.store.promptMemory() },
                                  home: DispatchQueue(label: "test.log"), log: lines.add)
            harness.onRecord = { lines.add($0.logLine) }  // as the Runtime wires it
            _ = await harness.respond(to: input(.said, words: said))
        }
        XCTAssertEqual(memory.store.shortTerm?.notes, [said], "the note itself was kept")
        let logged = lines.lock.withLock { lines.all }
        for line in logged { XCTAssertFalse(line.contains("PRIVATE_") || line.contains("Lisbon"), line) }
        let brain = logged.filter { $0.hasPrefix("brain you said ") }
        XCTAssertEqual(brain.count, 3)
        XCTAssertTrue(brain[0].hasSuffix(" ms → react, remember"), brain[0])
        XCTAssertTrue(brain[1].hasSuffix(" ms → react, remember (dropped)"), brain[1])
        XCTAssertTrue(logged.contains("remember: dropped: already noted"), "\(logged)")
        XCTAssertTrue(logged.contains("remember: dropped: looks like code"), "\(logged)")
    }

    // MARK: Budgets and fixtures

    /// The real steering.md and the sample memory fit every budget in
    /// HARNESS.md §4, with every input in the fixtures.
    func testTheSampleFitsTheBudgets() throws {
        let steering = try String(contentsOf: Self.steering, encoding: .utf8)
        let rig = try MemoryRig(setUp: false)
        for file in ["long-term.md", "short-term.md"] {
            try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("memory/" + file),
                                             to: rig.dir.appendingPathComponent(file))
        }
        let store = try MemoryStore(directory: rig.dir, steering: steering)
        XCTAssertNotNil(store.longTerm)
        XCTAssertNotNil(store.shortTerm)
        for i in try Self.fixtureInputs() {
            XCTAssertEqual(Prompt.overBudget(i, store.promptMemory()), [], i.line)
        }
    }

    static func fixtureInputs() throws -> [Input] {
        let dir = fixtures.appendingPathComponent("inputs")
        var out: [Input] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where file.hasSuffix(".jsonl") {
            for line in try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8).split(separator: "\n") {
                out.append(try XCTUnwrap(Input.fixture(String(line)), String(line)))
            }
        }
        return out
    }

    func testThereAreFiftyFixtureInputsOfEveryKind() throws {
        let inputs = try Self.fixtureInputs()
        XCTAssertGreaterThanOrEqual(inputs.count, 50)
        XCTAssertEqual(Set(inputs.map(\.kind)), Set(Input.Kind.allCases))
        XCTAssertTrue(inputs.contains { $0.outcome == .failed })
        XCTAssertTrue(inputs.filter { $0.kind == .said }.allSatisfy { $0.words != nil })
    }
}

extension Result where Failure == BrainError {
    var failureReason: String? {
        if case .failure(let e) = self { return e.description }
        return nil
    }
}
