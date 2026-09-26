import Foundation
import XCTest
@testable import BoopKit

func definitions() throws -> [ToolDefinition] {
    let memory = try MemoryRig()
    let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
    return Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store).map(\.definition)
}

func context(_ i: Input, window: [Transcript.Entry]? = nil,
             memory: Prompt.Memory = Prompt.Memory(steering: "<!-- note -->\n# Boop\nBe nice.\n",
                                                   longTerm: "## About you\n- Ships on Fridays.\n", shortTerm: "## Today\n")) -> Context {
    Context(input: i, memory: memory, window: window ?? [.input(i)])
}

// MARK: - The if-else classifier

final class RulesClassifierTests: XCTestCase {
    func decide(_ i: Input, memory: Prompt.Memory? = nil) async throws -> [ToolCall] {
        let menu = Menu(i.kind.menu, definitions: try definitions())
        let c = memory.map { context(i, memory: $0) } ?? context(i)
        let answer = try await RulesClassifier().classify(c, menu, deadline: .seconds(1)).calls
        XCTAssertNil(menu.check(answer), "every answer fits the menu")
        return answer
    }

    /// HARNESS.md §6: each row of the table in RulesClassifier's comment.
    func testEachRow() async throws {
        let quiet = { (m: Int) in ToolCall("quiet", ["minutes": .number(m)]) }
        let cases: [(Input, [ToolCall])] = [
            (input(.agentStarted), []),
            (input(.agentFinished, tookMs: 1_080_000), [react("proud")]),
            (input(.agentFinished, tookMs: 300_000), [react("proud")]),
            (input(.agentFinished, tookMs: 240_000), []),
            (input(.agentFinished, outcome: .failed), [react("annoyed")]),
            (input(.poked), [react("annoyed")]),
            // BEHAVIORS.md §3.3: only "quiet" quiets; yelled at or told off, sad.
            (input(.said, words: "be quiet for an hour"), [quiet(60)]),
            (input(.said, words: "give me some quiet for a couple of hours"), [quiet(120)]),
            (input(.said, words: "quiet for fifteen minutes please"), [quiet(15)]),
            (input(.said, words: "BE QUIET", yelled: true), [quiet(30), react("sad", "silent")]),
            (input(.said, words: "be quiet, you idiot"), [quiet(30), react("sad", "silent")]),
            (input(.said, words: "Shut up for an hour"), [react("sad")]),
            (input(.said, words: "can you keep it down for fifteen minutes"), [react("sad")]),
            (input(.said, words: "hush"), [react("sad")]),
            (input(.said, words: "go away"), [react("sad")]),
            (input(.said, words: "I hate you"), [react("sad")]),
            (input(.said, words: "you're so annoying"), [react("sad")]),
            (input(.said, words: "you are useless"), [react("sad")]),
            (input(.said, words: "what are you doing", yelled: true), [react("sad")]),
            (input(.said, words: "", yelled: true), [react("sad")]),
            (input(.said, words: "this build is annoying"), [react("curious")]),
            (input(.said, words: "remember I ship on Fridays"), [react("happy"), remember("today")]),
            (input(.said, words: "note that landing launches Monday"), [react("happy"), remember("today")]),
            (input(.said, words: "Hello, Boop!"), [react("happy")]),
            (input(.said, words: "good job today"), [react("proud")]),
            (input(.said, words: "you're the best"), [react("proud")]),
            (input(.said, words: "this is a thing"), [react("curious")]),
            (input(.newDay), []),
        ]
        for (i, expected) in cases {
            let calls = try await decide(i)
            XCTAssertEqual(calls, expected, i.line + " " + (i.words ?? ""))
        }
        // Whole words only: "hi" isn't in "this", "quiet" isn't in "quietly".
        XCTAssertEqual(Input.plain("Hi, THIS is quiet-ish!"), " hi this is quiet ish ")
        XCTAssertFalse(input(.said, words: "speak quietly").asksForQuiet)
        XCTAssertTrue(input(.said, words: "Quiet!").asksForQuiet)
        let notes = Prompt.Memory(steering: "", longTerm: "",
                                  shortTerm: ShortTerm(date: "2026-10-14", firstSeen: "09:00", mood: "content",
                                                       notes: ["demo on Thursday"]).markdown)
        let newDay = try await decide(input(.newDay), memory: notes)
        XCTAssertEqual(newDay, [], "long-term memory needs a model to decide")
    }

    /// It says which row matched, for the transcript.
    func testItSaysWhichRowMatched() async throws {
        let i = input(.agentFinished, outcome: .failed)
        let c = try await RulesClassifier().classify(context(i), Menu(i.kind.menu, definitions: try definitions()), deadline: .seconds(1))
        XCTAssertEqual(c.evidence, "failed")
    }
}

// MARK: - Jev

/// Answers Jev's requests from a script and keeps what was sent. Never
/// reaches the network.
final class FakeJev: @unchecked Sendable {
    let lock = NSLock()
    var requests: [[String: Any]] = []
    var status = 200
    /// Choice question → its choice; one left out gets its first option.
    var choices: [String: String] = [:]
    /// Yes/no question → its answer, 0 to 1; one left out is 0.
    var nouls: [String: Double] = [:]

    var send: @Sendable (URLRequest) async throws -> (Data, Int) {
        { [self] request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            let (choices, nouls, status): ([String: String], [String: Double], Int) = lock.withLock {
                requests.append(body)
                return (self.choices, self.nouls, self.status)
            }
            var answers: [String: Any] = [:]
            for (id, q) in body["questions"] as! [String: [String: Any]] {
                if q["type"] as? String == "noul" {
                    answers[id] = ["type": "noul", "noul": nouls[id] ?? 0]
                    continue
                }
                let options = (q["criteria"] as! [String: String]).keys.sorted()
                let choice = choices[id] ?? options[0]
                answers[id] = ["type": "choice", "choice": choice, "confidence": 0.9,
                               "probabilities": Dictionary(uniqueKeysWithValues: options.map { ($0, $0 == choice ? 0.9 : 0.0) })]
            }
            return (try JSONSerialization.data(withJSONObject: ["model": "jev-1.13.0", "answers": answers]), status)
        }
    }

    var last: [String: Any] { lock.withLock { requests.last ?? [:] } }
    var questions: [String: [String: Any]] { last["questions"] as? [String: [String: Any]] ?? [:] }
    var state: [String: Any] { last["state"] as? [String: Any] ?? [:] }
}

final class JevClassifierTests: XCTestCase {
    func classify(_ jev: FakeJev, _ i: Input, window: [Transcript.Entry]? = nil) async throws -> Classification {
        try await JevClassifier(key: "test-key", send: jev.send)
            .classify(context(i, window: window), Menu(i.kind.menu, definitions: try definitions()), deadline: .seconds(1))
    }

    /// HARNESS.md §6: the menu becomes questions built from the definitions.
    func testTheMenuBecomesQuestions() async throws {
        let jev = FakeJev()
        let c = try await classify(jev, input(.said, words: "hello boop"))
        XCTAssertEqual(c.calls, [])
        XCTAssertEqual(jev.last["model"] as? String, "jev-latest")
        let q = jev.questions
        XCTAssertEqual(Set(q.keys), ["quiet", "quiet.minutes", "react", "react.feeling", "react.voice", "remember"])
        XCTAssertEqual(q["react"]?["type"] as? String, "noul")
        XCTAssertEqual(q["react.feeling"]?["type"] as? String, "choice")
        XCTAssertEqual((q["react.feeling"]?["criteria"] as? [String: String])?["proud"], "Proud: something long or hard just finished.")
        XCTAssertEqual(Set((q["quiet.minutes"]?["criteria"] as! [String: String]).keys), ["15", "30", "60", "120"])
        XCTAssertNil(q["react.word"], "the writer's")
        XCTAssertNil(q["remember.where"], "one choice needs no question")
    }

    func testYesesBecomeCallsWithTheirChoices() async throws {
        let jev = FakeJev()
        jev.nouls = ["quiet": 0.9, "react": 0.8, "remember": 0.3]
        jev.choices = ["quiet.minutes": "60", "react.feeling": "sulky", "react.voice": "silent"]
        let c = try await classify(jev, input(.said, words: "shut up for an hour"))
        XCTAssertEqual(c.calls, [ToolCall("quiet", ["minutes": .number(60)]), react("sulky", "silent")])
        XCTAssertTrue(c.evidence?.contains("quiet 0.90") ?? false, c.evidence ?? "")
        XCTAssertTrue(c.evidence?.contains("react.feeling sulky 0.90") ?? false, c.evidence ?? "")

        jev.nouls = ["react": 0.7, "remember": 0.93]
        jev.choices = ["react.feeling": "happy", "react.voice": "mumble"]
        let noted = try await classify(jev, input(.said, words: "remember the demo is on Thursday"))
        XCTAssertEqual(noted.calls, [react("happy"), remember("today")])
    }

    /// A new day asks one yes/no per section, and may keep several.
    func testANewDayAsksPerSection() async throws {
        let jev = FakeJev()
        jev.nouls = ["remember.about_you": 0.8, "remember.moment": 0.6, "remember.temperament": 0.4]
        let c = try await classify(jev, input(.newDay))
        XCTAssertEqual(Set(jev.questions.keys),
                       ["remember.about_you", "remember.preference", "remember.temperament", "remember.moment"])
        XCTAssertEqual(c.calls, [remember("about_you"), remember("moment")])
        XCTAssertNotNil((jev.state["memory"] as? [String: String])?["short_term_yesterday"])
    }

    /// The state is the pass as JSON: who Boop is, memory, what happened
    /// lately (with what Boop did), and now. Never the key.
    func testTheStateCarriesTheWindow() async throws {
        let earlier = input(.agentFinished, tookMs: 600_000, rules: "cheer size 2", at: 0)
        let now = input(.said, words: "hi", at: 4)
        let window: [Transcript.Entry] = [
            .input(earlier), .rules("cheer size 2"), .decided(by: "x", [react("proud")], evidence: nil),
            .ran(react("proud", word: "finally"), .done("ok")),
            .aside("tapped · 14:07 Tuesday: Boop wiggled", ts: 120_000),
            .input(now),
        ]
        let jev = FakeJev()
        _ = try await classify(jev, now, window: window)
        let state = jev.state
        XCTAssertEqual(state["boop"] as? String, "# Boop\nBe nice.")
        XCTAssertEqual((state["memory"] as? [String: String])?["long_term"], "## About you\n- Ships on Fridays.\n")
        XCTAssertEqual(state["now"] as? [String: String], ["happened": "you said · 14:05 Tuesday", "they_said": "hi"])
        let recent = state["recent"] as! [[String: Any]]
        XCTAssertEqual(recent.map { $0["minutes_ago"] as? Int }, [4, 2])
        XCTAssertEqual(recent[0]["boop_did"] as? [String], ["react(feeling: proud, voice: mumble, word: finally)"])
        XCTAssertEqual(recent[0]["rules"] as? String, "cheer size 2")
        XCTAssertNil(recent[1]["boop_did"], "an aside")
        let request = String(decoding: try JSONSerialization.data(withJSONObject: jev.last), as: UTF8.self)
        XCTAssertFalse(request.contains("test-key"))
    }

    func testAnErrorStatusFailsWithoutItsBody() async throws {
        let jev = FakeJev()
        jev.status = 429
        do {
            _ = try await classify(jev, input(.agentStarted))
            XCTFail("a 429 answered")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("jev: HTTP 429"))
        }
    }
}

// MARK: - Writers and settings

final class WriterTests: XCTestCase {
    func slots() throws -> (Context, [Slot]) {
        let i = input(.said, words: "remember the demo is on Thursday")
        let calls = [react("happy"), remember("today")]
        let menu = Menu(i.kind.menu, definitions: try definitions())
        let window: [Transcript.Entry] = [.input(i), .decided(by: "rules@2", calls, evidence: nil)]
        return (context(i, window: window), menu.slots(calls))
    }

    /// HARNESS.md §6: when Apple's model can't run, every write fails, and
    /// the model is never reached.
    func testAppleFailsWhenItsModelCantRun() async throws {
        let (c, s) = try slots()
        do {
            _ = try await AppleWriter(unavailable: { "the model is updating" }).write(c, s, deadline: .seconds(1))
            XCTFail("wrote")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("apple: the model is updating"))
        }
        XCTAssertTrue(AppleWriter(unavailable: { nil }).id.hasPrefix("apple:"))
    }

    /// The request ends with what Boop decided, then a line per slot.
    func testAppleSeesTheDecisionAndTheSlots() throws {
        let (c, s) = try slots()
        let request = AppleWriter.request(c, s)
        XCTAssertTrue(request.contains("  decided: react(feeling: happy, voice: mumble), remember(where: today)"), request)
        XCTAssertTrue(request.hasSuffix("""
            react.word: one word from its list that fits the mumble, or none.
            remember.text: at most 80 characters. A note for later today: something the person said or asked to note. \
            Plain words, no code; leave it empty if nothing is worth keeping.
            """), request)
        let instructions = AppleWriter.instructions(c.memory)
        XCTAssertTrue(instructions.hasPrefix(AppleWriter.preamble + "\n\n# Boop\nBe nice."), instructions)
        XCTAssertTrue(instructions.contains("Ships on Fridays."))
        XCTAssertEqual(AppleWriter.values(#"{"react_word":"none","remember_text":"demo on Thursday"}"#, s),
                       ["remember.text": "demo on Thursday"])
    }

    #if canImport(FoundationModels)
    /// The runtime schema builds for every kind of slot. Doesn't call the model.
    func testTheAppleSchemaBuilds() throws {
        let (_, s) = try slots()
        _ = try AppleWriter.schema(s)
        let menu = Menu(Input.Kind.newDay.menu, definitions: try definitions())
        _ = try AppleWriter.schema(menu.slots([remember("about_you"), remember("moment")]))
    }
    #endif

    func testNoWriterAndTheDeepSeekStub() async throws {
        let (c, s) = try slots()
        let none = try await NoWriter().write(c, s, deadline: .seconds(1))
        XCTAssertEqual(none.values, [:])
        do {
            _ = try await DeepSeekWriter().write(c, s, deadline: .seconds(1))
            XCTFail("the stub wrote")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("the DeepSeek writer isn't available yet"))
        }
        XCTAssertEqual(DeepSeekWriter().id, "deepseek:deepseek-flash")
    }

    /// The settings: Jev needs a key, asked for only when it's chosen.
    func testTheSettingsMakeTheBrains() {
        var asked = 0
        var logs: [String] = []
        XCTAssertEqual(Brains.classifier("rules", key: { asked += 1; return "k" }).id, "rules@2")
        XCTAssertEqual(Brains.classifier("jev", key: { asked += 1; return nil }, log: { logs.append($0) }).id, "rules@2")
        XCTAssertTrue(logs.contains { $0.hasPrefix("brain: Jev needs an API key") }, "\(logs)")
        XCTAssertEqual(Brains.classifier("jev", key: { asked += 1; return "k" }).id, "jev:jev-latest")
        XCTAssertEqual(asked, 2)
        XCTAssertEqual(Brains.writer("none").id, "none")
        XCTAssertEqual(Brains.writer("deepseek").id, "deepseek:deepseek-flash")
        XCTAssertEqual(Brains.writer("apple").id, AppleWriter.unavailableReason == nil ? AppleWriter().id : "none")
    }
}
