import Foundation
import XCTest
@testable import BoopKit

/// A brain that answers from a script, after a delay.
struct FakeBrain: TextBrain {
    let id = "fake@1"
    var delayMs: Int = 0
    var answer: @Sendable (String) throws -> String

    func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                  deadline: Duration) async throws -> String {
        if delayMs > 0 { try await Task.sleep(for: .milliseconds(delayMs)) }
        return try answer(Prompt.now(in: user))
    }
}

/// Records what the harness hands off, touched only on the harness's queue.
final class HarnessRig: @unchecked Sendable {
    let home = DispatchQueue(label: "test.harness")
    var handled: [ToolCall] = []
    var records: [Harness.Record] = []
    var logs: [String] = []
    /// What the memory store would supply; change it on `home` between calls.
    var memory: Prompt.Memory
    var harness: Harness!

    init(brain: any Brain, memory: Prompt.Memory = Prompt.Memory(steering: "# Boop\n", longTerm: "## Boop\n", shortTerm: "## Today\n"),
         debugLog: URL? = nil, conversation: Conversation = Conversation()) {
        self.memory = memory
        let tools = [
            ToolDefinition(name: "say", description: "Mumble.", parameters: [
                .init("feeling", .choice(["happy", "proud"])), .init("word", .choice(["tests", "yay"]), optional: true),
            ]),
            ToolDefinition(name: "face", description: "Face.", parameters: [.init("name", .choice(["happy", "sulky"]))]),
            ToolDefinition(name: "quiet", description: "Quiet.", parameters: [.init("minutes", .number([15, 30]))]),
            ToolDefinition(name: "note", description: "Note.", parameters: [.init("text", .text(maxLength: 10))]),
        ].map { d in Harness.Tool(definition: d, handle: { [unowned self] call in handled.append(call); return .done("ok") }) }
        harness = Harness(brain: brain, tools: tools, memory: { [unowned self] _ in self.memory }, home: home, debugLog: debugLog,
                          conversation: conversation, log: { [unowned self] in logs.append($0) })
        harness.onRecord = { [unowned self] in records.append($0) }
    }

    func submit(_ trigger: Trigger) { home.sync { harness.submit(trigger) } }

    /// Waits until nothing is running or waiting.
    func settle(timeoutMs: Int = 3000) async {
        for _ in 0..<(timeoutMs / 10) {
            if home.sync(execute: { harness.idle }) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("harness didn't settle")
    }

    var snapshot: (handled: [ToolCall], records: [Harness.Record]) { home.sync { (handled, records) } }
}

func trigger(_ kind: Trigger.Kind, _ line: String, words: String? = nil) -> Trigger {
    Trigger(kind: kind, line: line, words: words, ts: 0)
}

final class HarnessTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let steering = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../plan/steering.md").standardizedFileURL

    let tools = [
        ToolDefinition(name: "say", description: "", parameters: [
            .init("feeling", .choice(["happy", "proud"])), .init("word", .choice(["tests"]), optional: true),
        ]),
        ToolDefinition(name: "quiet", description: "", parameters: [.init("minutes", .number([15, 30]))]),
        ToolDefinition(name: "note", description: "", parameters: [.init("text", .text(maxLength: 10))]),
    ]

    // MARK: Shape check

    func testTheShapeCheckAcceptsGoodAnswers() throws {
        let ok = try Answer.check(#"{"calls":[{"tool":"say","feeling":"proud","word":"tests"},{"tool":"quiet","minutes":30}]}"#,
                                  tools: tools).get()
        XCTAssertEqual(ok, [ToolCall("say", ["feeling": .string("proud"), "word": .string("tests")]),
                            ToolCall("quiet", ["minutes": .number(30)])])
        let empty = try Answer.check(#"{"calls":[]}"#, tools: tools).get()
        XCTAssertEqual(empty, [])
        // Digits as text count as the number; a null optional is left out.
        let loose = try Answer.check(#"{"calls":[{"tool":"quiet","minutes":"15"},{"tool":"say","feeling":"happy","word":null}]}"#,
                                     tools: tools).get()
        XCTAssertEqual(loose, [ToolCall("quiet", ["minutes": .string("15")]), ToolCall("say", ["feeling": .string("happy")])])
    }

    func testTheShapeCheckDropsTheWholeAnswer() {
        let bad = [
            "", "calls", "[]", #"{"calls":{}}"#, #"{"calls":[],"extra":1}"#,
            #"{"calls":[{"feeling":"happy"}]}"#,                                        // no tool
            #"{"calls":[{"tool":"face","name":"happy"}]}"#,                              // not offered
            #"{"calls":[{"tool":"say","feeling":"sad"}]}"#,                              // not a choice
            #"{"calls":[{"tool":"say"}]}"#,                                              // missing
            #"{"calls":[{"tool":"say","feeling":"happy","volume":"loud"}]}"#,            // unknown
            #"{"calls":[{"tool":"quiet","minutes":45}]}"#,                               // not a choice
            #"{"calls":[{"tool":"quiet","minutes":15.5}]}"#,                             // not whole
            #"{"calls":[{"tool":"quiet","minutes":true}]}"#,                             // not a number
            #"{"calls":[{"tool":"note","text":"far too long for it"}]}"#,               // too long
            #"{"calls":[{"tool":"say","feeling":"happy"},{"tool":"say","feeling":"happy"},{"tool":"say","feeling":"happy"},{"tool":"say","feeling":"happy"}]}"#,
            #"{"calls":[{"tool":"say","feeling":"happy"},{"tool":"say","feeling":"sad"}]}"#, // one bad call
        ]
        for raw in bad {
            if case .success(let calls) = Answer.check(raw, tools: tools) { XCTFail("accepted \(raw) as \(calls)") }
        }
        XCTAssertEqual(Answer.check(#"{"calls":[{"tool":"say"},{"tool":"say"},{"tool":"say"},{"tool":"say"}]}"#,
                                    tools: tools).failureReason, "4 calls, more than 3")
    }

    func testAnswersRoundTrip() throws {
        let calls = [ToolCall("say", ["feeling": .string("proud"), "word": .string("tests")]), ToolCall("quiet", ["minutes": .number(15)])]
        XCTAssertEqual(Answer.json(calls), #"{"calls":[{"tool":"say","feeling":"proud","word":"tests"},{"tool":"quiet","minutes":15}]}"#)
        let back = try Answer.check(Answer.json(calls), tools: tools).get()
        XCTAssertEqual(back, calls)
    }

    // MARK: One call

    func testCallsAreHandedOffInOrder() async {
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"face","name":"sulky"},{"tool":"quiet","minutes":30}]}"# })
        rig.submit(trigger(.talk, "talk · 13:10 Tuesday", words: "shut up"))
        await rig.settle()
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [ToolCall("face", ["name": .string("sulky")]), ToolCall("quiet", ["minutes": .number(30)])])
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].validShape)
        XCTAssertEqual(records[0].tools, ["say", "face", "quiet", "note"])
    }

    func testEveryConversationCallIsOfferedTheSameToolsWithLimitsNamed() async {
        // `quiet` is offered on a tap but named as a limit, so that one call is dropped.
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"face","name":"happy"},{"tool":"quiet","minutes":30}]}"# })
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [ToolCall("face", ["name": .string("happy")])])
        XCTAssertEqual(records.first?.tools, ["say", "face", "quiet", "note"])
        XCTAssertEqual(Prompt.now(in: records.first?.prompt.user ?? ""),
                       "tapped · 09:30 Tuesday\nquiet limit: only on talk\nnote limit: only on talk")
        XCTAssertEqual(records.first?.ran.map(\.outcome), [.done("ok"), .dropped("quiet limit: only on talk")])
        XCTAssertTrue(records.first?.validShape ?? false)
    }

    func testTheShapeCheckStillDropsToolsThatArentOffered() async {
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"face","name":"happy"},{"tool":"remember","text":"hi"}]}"# })
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        XCTAssertEqual(rig.snapshot.handled, [])
        XCTAssertEqual(rig.snapshot.records.first?.dropped, "shape: remember isn't offered")
        XCTAssertTrue(rig.home.sync { rig.logs.contains { $0.contains("answer dropped") } })
    }

    func testMoreThanThreeCallsAreDropped() async {
        let four = Answer.json(Array(repeating: ToolCall("face", ["name": .string("happy")]), count: 4))
        let rig = HarnessRig(brain: FakeBrain { _ in four })
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        XCTAssertEqual(rig.snapshot.handled, [])
        XCTAssertEqual(rig.snapshot.records.first?.dropped, "shape: 4 calls, more than 3")
    }

    func testBrainErrorsAndLateAnswersAreDropped() async {
        let failing = HarnessRig(brain: FakeBrain { _ in throw BrainError("offline") })
        failing.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await failing.settle()
        XCTAssertEqual(failing.snapshot.records.first?.dropped, "offline")

        // A brain that ignores its deadline: the answer comes too late.
        let slow = HarnessRig(brain: FakeBrain(delayMs: 60_000) { _ in #"{"calls":[]}"# })
        let h = slow.harness!
        let start = ContinuousClock.now
        let (answer, _) = await h.ask(Situation(trigger: trigger(.tap, "tapped · 09:30 Tuesday"),
                                                memory: .init(steering: "", longTerm: "", shortTerm: "")),
                                      Menu(tools: []), deadline: 50)
        XCTAssertEqual(answer.failureReason, "late: no answer within 50 ms")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    // MARK: Scheduling

    func testANewerTriggerReplacesTheWaitingOne() async {
        let rig = HarnessRig(brain: FakeBrain(delayMs: 150) { now in
            now.hasPrefix("tapped") ? #"{"calls":[{"tool":"face","name":"happy"}]}"# : #"{"calls":[]}"#
        })
        rig.submit(trigger(.event, "turn started · claude · a · 09:00 Tuesday"))
        rig.submit(trigger(.event, "turn finished · claude · a · took 12 s · 09:00 Tuesday"))
        rig.submit(trigger(.tap, "tapped · 09:00 Tuesday"))
        await rig.settle()
        let records = rig.snapshot.records
        XCTAssertEqual(records.map(\.trigger.line), ["turn started · claude · a · 09:00 Tuesday", "tapped · 09:00 Tuesday"])
        XCTAssertEqual(rig.snapshot.handled, [ToolCall("face", ["name": .string("happy")])])
        XCTAssertTrue(rig.home.sync { rig.logs.contains("harness: event replaced by a newer tap") })
    }

    func testTalkCancelsWhateverIsRunning() async {
        let rig = HarnessRig(brain: FakeBrain(delayMs: 300) { now in
            now.hasPrefix("talk") ? #"{"calls":[{"tool":"face","name":"sulky"}]}"# : #"{"calls":[{"tool":"face","name":"happy"}]}"#
        })
        rig.submit(trigger(.event, "turn started · claude · a · 09:00 Tuesday"))
        try? await Task.sleep(for: .milliseconds(50))
        rig.submit(trigger(.talk, "talk · 09:00 Tuesday", words: "hush"))
        await rig.settle()
        try? await Task.sleep(for: .milliseconds(400)) // the cancelled call's answer would be in by now
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [ToolCall("face", ["name": .string("sulky")])])
        XCTAssertEqual(records.map(\.trigger.kind), [.event, .talk])
        XCTAssertEqual(records[0].dropped, "cancelled by talk")
    }

    // MARK: Limits

    /// Speaks unless the prompt names a `say` limit, and adds a face.
    struct ChattyBrain: TextBrain {
        let id = "chatty@1"
        func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                      deadline: Duration) async throws -> String {
            !Prompt.now(in: user).contains("say limit: ")
                ? #"{"calls":[{"tool":"say","feeling":"happy"},{"tool":"face","name":"happy"}]}"#
                : #"{"calls":[{"tool":"face","name":"happy"}]}"#
        }
    }

    /// Always tries to speak, limit or not.
    struct StubbornBrain: TextBrain {
        let id = "stubborn@1"
        func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                      deadline: Duration) async throws -> String {
            #"{"calls":[{"tool":"say","feeling":"happy"},{"tool":"face","name":"happy"}]}"#
        }
    }

    func sayLimited(_ r: Harness.Record) -> Bool { Prompt.now(in: r.prompt.user).contains("say limit: ") }

    func at(_ minutes: Double, _ kind: Trigger.Kind, _ line: String, words: String? = nil) -> Trigger {
        Trigger(kind: kind, line: line, words: words, ts: Int64(minutes * 60_000))
    }

    func testEventSpeechIsLimitedOnTheTriggersClock() async {
        let rig = HarnessRig(brain: ChattyBrain())
        let events = [
            at(0, .event, "turn finished · claude · a · took 12 s · 09:00 Tuesday"),
            at(1, .event, "turn finished · claude · a · took 12 s · 09:01 Tuesday"),
            at(9.9, .event, "turn failed · claude · a · 09:09 Tuesday"),
            at(10, .event, "turn started · claude · a · 09:10 Tuesday"),
            at(10.5, .event, "turn finished · claude · a · took 30 s · 09:10 Tuesday"),
            at(11, .event, "turn finished · claude · a · took 30 s · 09:11 Tuesday"),
            at(40, .event, "turn started · claude · a · 09:40 Tuesday"),
        ]
        for e in events {
            rig.submit(e)
            await rig.settle()
        }
        let records = rig.snapshot.records
        XCTAssertTrue(records.allSatisfy { $0.tools == ["say", "face", "quiet", "note"] })
        XCTAssertEqual(records.map(sayLimited), [false, true, true, true, false, true, true])
        // The example in HARNESS.md §4.
        XCTAssertEqual(Prompt.now(in: records[1].prompt.user),
                       "turn finished · claude · a · took 12 s · 09:01 Tuesday\nsay limit: once every 10 min on event, next in 9 min\n"
                       + "quiet limit: only on talk\nnote limit: only on talk")
        XCTAssertEqual(Prompt.now(in: records[3].prompt.user).components(separatedBy: "\n")[1],
                       "say limit: not on turn started")
        XCTAssertEqual(records.map { $0.ran.map(\.call.name) },
                       [["say", "face"], ["face"], ["face"], ["face"], ["say", "face"], ["face"], ["face"]])
        XCTAssertTrue(records.allSatisfy(\.validShape))
    }

    func testTapSpeechIsLimitedAndTalkIsNot() async {
        let rig = HarnessRig(brain: ChattyBrain())
        for t in [at(0, .tap, "tapped · 09:00 Tuesday"), at(4, .tap, "tapped · 09:04 Tuesday"),
                  at(5, .tap, "tapped · 09:05 Tuesday"),
                  at(5, .talk, "talk · 09:05 Tuesday", words: "hi"), at(5.1, .talk, "talk · 09:05 Tuesday", words: "hi")] {
            rig.submit(t)
            await rig.settle()
        }
        XCTAssertEqual(rig.snapshot.records.map { !sayLimited($0) }, [true, false, true, true, true])
    }

    func testSpeechPastItsLimitIsDroppedEvenWhenTheBrainTriesAnyway() async {
        let rig = HarnessRig(brain: StubbornBrain())
        for t in [at(0, .tap, "tapped · 09:00 Tuesday"), at(2, .tap, "tapped · 09:02 Tuesday")] {
            rig.submit(t)
            await rig.settle()
        }
        let records = rig.snapshot.records
        XCTAssertEqual(records[1].ran.map(\.outcome), [.dropped("say limit: once every 5 min on tap, next in 3 min"), .done("ok")])
        XCTAssertEqual(rig.snapshot.handled.map(\.name), ["say", "face", "face"])
    }

    func testASecondSayInOneAnswerIsDroppedAndDroppedSpeechDoesntCount() async {
        let home = DispatchQueue(label: "test.limits")
        var outcomes: [ActionOutcome] = [.dropped("quiet mode"), .done("said"), .done("said")]
        let say = ToolDefinition(name: "say", description: "", parameters: [.init("feeling", .choice(["happy"]))])
        let harness = Harness(brain: FakeBrain { _ in #"{"calls":[{"tool":"say","feeling":"happy"},{"tool":"say","feeling":"happy"}]}"# },
                              tools: [Harness.Tool(definition: say, handle: { _ in outcomes.removeFirst() })],
                              memory: { _ in Prompt.Memory(steering: "", longTerm: "", shortTerm: "") }, home: home)
        let r = await harness.respond(to: at(0, .tap, "tapped · 09:00 Tuesday"))
        // The first say was dropped by its action, so the second may still run.
        XCTAssertEqual(r.ran.map(\.outcome), [.dropped("quiet mode"), .done("said")])
        let r2 = await harness.respond(to: at(20, .tap, "tapped · 09:20 Tuesday"))
        XCTAssertEqual(r2.ran.map(\.outcome), [.done("said"), .dropped("say limit: once every 5 min on tap, next in 5 min")])
    }

    // MARK: Prompt

    func testThePromptHasItsFixedLayout() {
        let memory = Prompt.Memory(steering: "<!-- for maintainers -->\n# Boop\nBe nice.\n", longTerm: "## Boop\nname: Pip\n",
                                   shortTerm: "## Today\n2026-10-14\n")
        let p = Prompt(trigger: trigger(.talk, "talk · 13:10 Tuesday", words: "shut \"up\"\nnow"), memory: memory)
        XCTAssertEqual(p.system, Prompt.preamble + "\n\n# Boop\nBe nice.")
        XCTAssertEqual(Prompt.preamble.components(separatedBy: "\n").count, 3)
        XCTAssertEqual(p.user, "## Boop\nname: Pip\n\n## Today\n2026-10-14\n\n--- now ---\ntalk · 13:10 Tuesday\nthey said: \"shut 'up' now\"")
        XCTAssertEqual(Prompt.now(in: p.user), "talk · 13:10 Tuesday\nthey said: \"shut 'up' now\"")

        let r = Prompt(trigger: trigger(.reflect, "reflect · yesterday 2026-10-14"), memory: memory)
        XCTAssertTrue(r.user.contains("Yesterday's short-term memory, to reflect on:\n\n## Today\n2026-10-14"))
    }

    /// The real steering.md and the sample memory fit every budget in
    /// HARNESS.md §4, with every trigger in the fixtures.
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
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: store)
        for t in try Self.fixtureTriggers() {
            let tools = actions.filter { t.kind.offered.contains($0.name) }.map(\.definition)
            XCTAssertEqual(Prompt.overBudget(t, store.promptMemory(for: t.kind), tools: tools), [], t.line)
        }
    }

    // MARK: Fixtures

    static func fixtureTriggers() throws -> [Trigger] {
        let dir = fixtures.appendingPathComponent("triggers")
        var out: [Trigger] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where file.hasSuffix(".jsonl") {
            for line in try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8).split(separator: "\n") {
                let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                out.append(Trigger(kind: Trigger.Kind(rawValue: o["kind"] as! String)!, line: o["line"] as! String,
                                   words: o["words"] as? String, ts: 0))
            }
        }
        return out
    }

    func testThereAreFiftyFixtureTriggersOfEveryKind() throws {
        let triggers = try Self.fixtureTriggers()
        XCTAssertGreaterThanOrEqual(triggers.count, 50)
        XCTAssertEqual(Set(triggers.map(\.kind)), [.event, .tap, .talk, .reflect])
        for what in ["turn started", "turn finished", "turn failed"] {
            XCTAssertTrue(triggers.contains { $0.line.hasPrefix(what) }, what)
        }
        XCTAssertTrue(triggers.filter { $0.kind == .talk }.allSatisfy { $0.words != nil })
    }

    // MARK: Logging

    func testDebugModeLogsOneJSONLinePerCall() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("boop-harness-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: log) }
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"say","feeling":"sad"}]}"# }, debugLog: log)
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        rig.submit(trigger(.talk, "talk · 09:31 Tuesday", words: "hi"))
        await rig.settle()
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        XCTAssertEqual(first["brain"] as? String, "fake@1")
        XCTAssertEqual(first["raw"] as? String, #"{"calls":[{"tool":"say","feeling":"sad"}]}"#)
        XCTAssertTrue((first["dropped"] as? String)?.hasPrefix("shape: say: feeling") ?? false)
        XCTAssertNotNil(first["system"])
        XCTAssertEqual(first["history"] as? Int, 0)
        XCTAssertNotNil(first["user"])
        XCTAssertNotNil(first["latency_ms"])
    }

    func testWithoutDebugModeNothingIsWritten() async {
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[]}"# })
        XCTAssertNil(rig.harness.debugLog)
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        XCTAssertEqual(rig.snapshot.records.count, 1)
        XCTAssertTrue(rig.snapshot.records[0].silent)
        XCTAssertTrue(rig.snapshot.records[0].logLine.hasSuffix(" ms → quiet"), rig.snapshot.records[0].logLine)
    }

    /// HARNESS.md §8: outside debug mode "nothing is written to disk,
    /// because talk entries contain what you said". The app's log (boop.log)
    /// gets each call's line, the harness's own lines and every action's
    /// drop reasons: they name tools and reasons, never an argument's text.
    func testTheLogNeverGetsWhatYouSaid() async throws {
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var all: [String] = []
            func add(_ line: String) { lock.withLock { all.append(line) } }
        }
        let said = "PRIVATE_sam moves to Lisbon"
        let answers = [
            // A note that's kept, then the same note again, which the store refuses.
            Answer.json([ToolCall("say", ["feeling": .string("happy")]), ToolCall("note", ["text": .string(said)])]),
            Answer.json([ToolCall("note", ["text": .string(said)])]),
            // A note the store refuses as code, and an answer the shape check drops.
            Answer.json([ToolCall("note", ["text": .string(said + " `x`")])]),
            Answer.json([ToolCall("say", ["feeling": .string(said)])]),
        ]
        let memory = try MemoryRig()
        let lines = Lines()
        for answer in answers {
            let context = ActionContext(send: { _ in }, today: { "2026-10-14" }, log: lines.add)
            let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
            let harness = Harness(brain: FakeBrain { _ in answer }, tools: actions.map(Harness.Tool.init),
                                  memory: { memory.store.promptMemory(for: $0.kind) },
                                  home: DispatchQueue(label: "test.log"), log: lines.add)
            harness.onRecord = { lines.add($0.logLine) }  // as the Runtime wires it
            _ = await harness.respond(to: trigger(.talk, "talk · 13:10 Tuesday", words: said))
        }
        XCTAssertEqual(memory.store.shortTerm?.notes, [said], "the note itself was kept")
        let logged = lines.lock.withLock { lines.all }
        for line in logged { XCTAssertFalse(line.contains("PRIVATE_") || line.contains("Lisbon"), line) }
        let brain = logged.filter { $0.hasPrefix("brain talk ") }
        XCTAssertEqual(brain.count, 4)
        XCTAssertTrue(brain[0].hasSuffix(" ms → say, note"), brain[0])
        XCTAssertTrue(brain[1].hasSuffix(" ms → note (dropped)"), brain[1])
        XCTAssertTrue(brain[3].hasSuffix(" ms → dropped: shape: say: feeling isn't one of its choices"), brain[3])
        XCTAssertTrue(logged.contains("note: dropped: already noted"), "\(logged)")
        XCTAssertTrue(logged.contains("note: dropped: looks like code"), "\(logged)")
    }
}

extension Result where Failure == BrainError {
    var failureReason: String? {
        if case .failure(let e) = self { return e.description }
        return nil
    }
}

final class BrainTests: XCTestCase {
    func steering() throws -> String { try String(contentsOf: HarnessTests.steering, encoding: .utf8) }

    func ask(_ brain: any Brain, _ t: Trigger, tools: [String]? = nil, limits: [String] = []) async throws -> String {
        let memory = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        let defs = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
            .filter { (tools ?? t.kind.tools).contains($0.name) }.map(\.definition)
        let situation = Situation(trigger: t, memory: .init(steering: try steering(), longTerm: "", shortTerm: ""))
        return Answer.json(try await brain.decide(situation, Menu(tools: defs, limits: limits), deadline: .seconds(1)).calls)
    }

    func testTheRulesBrainReadsTheFallbackTable() throws {
        let rows = RulesBrain.fallbacks(try steering())
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[4].condition, #"Talk containing "shut up" or "quiet""#)
        XCTAssertEqual(rows[4].calls, [ToolCall("face", ["name": .string("sulky")]), ToolCall("quiet", ["minutes": .number(30)])])
        XCTAssertEqual(rows[6].calls, [])
    }

    func testTheRulesBrainAnswersEachRow() async throws {
        let b = RulesBrain()
        let cases: [(Trigger, String)] = [
            (trigger(.event, "turn finished · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday"),
             #"{"calls":[{"tool":"say","feeling":"proud","word":"finally"}]}"#),
            (trigger(.event, "turn finished · claude · jetpack · took 4 min · 14:05 Tuesday"), #"{"calls":[]}"#),
            (trigger(.event, "turn finished · claude · jetpack · took 45 s · 14:05 Tuesday"), #"{"calls":[]}"#),
            (trigger(.event, "turn failed · codex · landing · topic: tests · 14:02 Tuesday"),
             #"{"calls":[{"tool":"face","name":"side_eye"}]}"#),
            (trigger(.event, "turn started · claude · jetpack · 09:12 Tuesday"), #"{"calls":[]}"#),
            (trigger(.tap, "tapped · 09:30 Tuesday"), #"{"calls":[{"tool":"face","name":"happy"}]}"#),
            (trigger(.tap, "tapped · 12:15 Tuesday · hungry"), #"{"calls":[{"tool":"say","feeling":"hopeful","word":"food"}]}"#),
            (trigger(.tap, "tapped · 12:15 Tuesday · starving"), #"{"calls":[{"tool":"say","feeling":"hopeful","word":"food"}]}"#),
            (trigger(.talk, "talk · 13:10 Tuesday", words: "Shut up for an hour"),
             #"{"calls":[{"tool":"face","name":"sulky"},{"tool":"quiet","minutes":30}]}"#),
            (trigger(.talk, "talk · 13:10 Tuesday", words: "be quiet"),
             #"{"calls":[{"tool":"face","name":"sulky"},{"tool":"quiet","minutes":30}]}"#),
            (trigger(.talk, "talk · 13:10 Tuesday", words: "good job"),
             #"{"calls":[{"tool":"face","name":"curious"},{"tool":"say","feeling":"curious"}]}"#),
            (trigger(.reflect, "reflect · yesterday 2026-10-14"), #"{"calls":[]}"#),
        ]
        for (t, expected) in cases {
            let answer = try await ask(b, t)
            XCTAssertEqual(answer, expected, t.line)
        }
        // Calls to tools that aren't offered, or that the menu names as past a limit, are left out.
        let answer = try await ask(b, trigger(.talk, "talk · 13:10 Tuesday", words: "quiet"), tools: ["face"])
        XCTAssertEqual(answer, #"{"calls":[{"tool":"face","name":"sulky"}]}"#)
        let limited = try await ask(b, trigger(.tap, "tapped · 12:15 Tuesday · hungry"),
                                    limits: ["say limit: once every 5 min on tap, next in 2 min"])
        XCTAssertEqual(limited, #"{"calls":[]}"#)
    }

    /// HARNESS.md §7: rules are "used when Apple's model can't run",
    /// including when it stops being able to after launch: that call gets
    /// the rules brain's answer instead of being dropped. Never reaches the
    /// model.
    func testAppleAnswersWithTheRulesWhenItsModelIsUnavailable() async throws {
        let apple = AppleBrain(unavailable: { "the model is updating" })
        XCTAssertTrue(apple.id.hasPrefix("apple:"))
        let cases = [
            trigger(.tap, "tapped · 09:30 Tuesday"),
            trigger(.talk, "talk · 13:10 Tuesday", words: "be quiet"),
            trigger(.event, "turn failed · codex · landing · topic: tests · 14:02 Tuesday"),
        ]
        for t in cases {
            let answer = try await ask(apple, t)
            let rules = try await ask(RulesBrain(), t)
            XCTAssertEqual(answer, rules, t.line)
        }
        let tap = try await ask(apple, cases[0])
        XCTAssertEqual(tap, #"{"calls":[{"tool":"face","name":"happy"}]}"#)
    }

    func testTheCloudBrainIsDisabled() async {
        do {
            _ = try await CloudBrain(model: "any").complete(system: "", history: [], user: "", tools: [], deadline: .seconds(1))
            XCTFail("the cloud brain answered")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("the cloud brain isn't available yet"))
        }
        XCTAssertEqual(Brains.make("rules").id, "rules@1")
        XCTAssertEqual(Brains.make("cloud:some-model").id, "cloud:some-model")
    }

    #if canImport(FoundationModels)
    /// The runtime schema builds for every trigger's tools, and `none`
    /// leaves out an optional choice or drops the call. Doesn't call the
    /// model.
    func testTheAppleSchemaBuildsForEveryTrigger() throws {
        let memory = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
        for kind in [Trigger.Kind.event, .tap, .talk, .reflect] {
            _ = try (AppleBrain.schema(actions.filter { kind.offered.contains($0.name) }.map(\.definition)))
        }
        // Writing a call Jev decided on: that tool only, and it must be called.
        _ = try AppleBrain.schema(actions.filter { $0.name == "note" }.map(\.definition), decided: true)
        // Earlier answers are shown in the shape this brain answers in.
        XCTAssertEqual(AppleBrain.toList(#"{"calls":[]}"#), #"{"react":"stay quiet","calls":[]}"#)
        XCTAssertEqual(AppleBrain.toList(#"{"calls":[{"tool":"face","name":"happy"}]}"#),
                       #"{"react":"react","calls":[{"name":"happy","tool":"face"}]}"#)
        let transcript = AppleBrain.transcript("System", [Exchange(user: "u1", answer: #"{"calls":[]}"#)])
        XCTAssertEqual(transcript.count, 3)
        XCTAssertEqual(AppleBrain.fromList(#"{"react":"stay quiet","calls":[{"tool":"face","name":"happy"}]}"#), #"{"calls":[]}"#)
        XCTAssertEqual(AppleBrain.fromList(#"{"react":"react","calls":[{"tool":"face","name":"happy"}]}"#),
                       #"{"calls":[{"name":"happy","tool":"face"}]}"#)
        let tools = actions.map(\.definition)
        XCTAssertEqual(AppleBrain.fromList(#"{"react":"react","calls":[{"tool":"say","feeling":"happy","word":"none"},{"tool":"face","name":"none"}]}"#, tools: tools),
                       #"{"calls":[{"feeling":"happy","tool":"say"}]}"#)
    }
    #endif
}
