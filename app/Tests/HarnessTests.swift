import Foundation
import XCTest
@testable import BoopKit

/// A brain that answers from a script, after a delay.
struct FakeBrain: Brain {
    let id = "fake@1"
    var delayMs: Int = 0
    var answer: @Sendable (String) throws -> String

    func complete(system: String, user: String, tools: [ToolDefinition], deadline: Duration) async throws -> String {
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
    var harness: Harness!

    init(brain: any Brain, memory: Prompt.Memory = Prompt.Memory(steering: "# Boop\n", longTerm: "## Boop\n", shortTerm: "## Today\n"),
         debugLog: URL? = nil) {
        let tools = [
            ToolDefinition(name: "say", description: "Mumble.", parameters: [
                .init("feeling", .choice(["happy", "proud"])), .init("word", .choice(["tests", "yay"]), optional: true),
            ]),
            ToolDefinition(name: "face", description: "Face.", parameters: [.init("name", .choice(["happy", "sulky"]))]),
            ToolDefinition(name: "quiet", description: "Quiet.", parameters: [.init("minutes", .number([15, 30]))]),
            ToolDefinition(name: "note", description: "Note.", parameters: [.init("text", .text(maxLength: 10))]),
        ].map { d in Harness.Tool(definition: d, handle: { [unowned self] call in handled.append(call); return .done("ok") }) }
        harness = Harness(brain: brain, tools: tools, memory: { _ in memory }, home: home, debugLog: debugLog,
                          log: { [unowned self] in logs.append($0) })
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

    func testOnlyTheTriggersToolsAreOffered() async {
        // `quiet` isn't offered on a tap, so the whole answer is dropped.
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"face","name":"happy"},{"tool":"quiet","minutes":30}]}"# })
        rig.submit(trigger(.tap, "tapped · 09:30 Tuesday"))
        await rig.settle()
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [])
        XCTAssertEqual(records.first?.tools, ["say", "face"])
        XCTAssertEqual(records.first?.dropped, "shape: quiet isn't offered")
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
        let (answer, _) = await h.ask(Prompt(system: "", user: ""), [], deadline: 50)
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
            let tools = actions.filter { t.kind.tools.contains($0.name) }.map(\.definition)
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

    func ask(_ brain: any Brain, _ t: Trigger, tools: [String]? = nil) async throws -> String {
        let prompt = Prompt(trigger: t, memory: .init(steering: try steering(), longTerm: "", shortTerm: ""))
        let memory = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        let defs = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
            .filter { (tools ?? t.kind.tools).contains($0.name) }.map(\.definition)
        return try await brain.complete(system: prompt.system, user: prompt.user, tools: defs, deadline: .seconds(1))
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
        // Calls to tools that aren't offered are left out.
        let answer = try await ask(b, trigger(.talk, "talk · 13:10 Tuesday", words: "quiet"), tools: ["face"])
        XCTAssertEqual(answer, #"{"calls":[{"tool":"face","name":"sulky"}]}"#)
    }

    func testTheCloudBrainIsDisabled() async {
        do {
            _ = try await CloudBrain(model: "any").complete(system: "", user: "", tools: [], deadline: .seconds(1))
            XCTFail("the cloud brain answered")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("the cloud brain isn't available yet"))
        }
        XCTAssertEqual(Brains.make("rules").id, "rules@1")
        XCTAssertEqual(Brains.make("cloud:some-model").id, "cloud:some-model")
    }

    #if canImport(FoundationModels)
    /// The runtime schema builds for every trigger's tools, including
    /// `forget` with nothing to forget. Doesn't call the model.
    func testTheAppleSchemaBuildsForEveryTrigger() throws {
        let memory = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store)
        for kind in [Trigger.Kind.event, .tap, .talk, .reflect] {
            _ = try (AppleBrain.schema(actions.filter { kind.tools.contains($0.name) }.map(\.definition)))
        }
        XCTAssertEqual(AppleBrain.fromList(#"{"react":"stay quiet","calls":[{"tool":"face","name":"happy"}]}"#), #"{"calls":[]}"#)
        XCTAssertEqual(AppleBrain.fromList(#"{"react":"react","calls":[{"tool":"face","name":"happy"}]}"#),
                       #"{"calls":[{"name":"happy","tool":"face"}]}"#)
    }
    #endif
}
