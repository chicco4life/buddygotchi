import Foundation
import XCTest
@testable import BoopKit

/// Answers Jev's requests from a script and keeps what was sent. Never
/// reaches the network.
final class FakeJev: @unchecked Sendable {
    let lock = NSLock()
    var requests: [[String: Any]] = []
    var status = 200
    /// Question → choice; a question left out is answered with its first option.
    var choices: [String: String] = [:]
    /// Yes/no question → its answer, 0 to 1; left out is 0.
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
            let data = try JSONSerialization.data(withJSONObject: ["model": "jev-1.13.0", "answers": answers])
            return (data, status)
        }
    }

    var last: [String: Any] { lock.withLock { requests.last ?? [:] } }
    var questions: [String: [String: Any]] { last["questions"] as? [String: [String: Any]] ?? [:] }
}

/// A writer that always answers the same, and counts what it was asked.
final class FakeWriter: TextBrain, Writer, @unchecked Sendable {
    let id = "writer@1"
    let answer: String
    let lock = NSLock()
    var calls = 0
    var wrote: [String] = []
    init(_ answer: String) { self.answer = answer }
    func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                  deadline: Duration) async throws -> String {
        lock.withLock { calls += 1 }
        return answer
    }
    func write(_ tool: ToolDefinition, _ situation: Situation, deadline: Duration) async throws -> ToolCall? {
        lock.withLock { wrote.append(tool.name) }
        return ToolCall(tool.name, ["text": .string("demo on Thursday")])
    }
}

final class JevBrainTests: XCTestCase {
    let memory = Prompt.Memory(steering: "<!-- note -->\n# Boop\nBe nice.\n", longTerm: "## About you\n- Ships on Fridays.\n",
                               shortTerm: "## Today\n")

    func tools(_ kind: Trigger.Kind) throws -> [ToolDefinition] {
        let rig = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        return Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: rig.store)
            .filter { kind.offered.contains($0.name) }.map(\.definition)
    }

    func decide(_ jev: FakeJev, writer: any Brain = RulesBrain(), _ t: Trigger, recent: [Turn] = [],
                limits: [String] = []) async throws -> Decision {
        let brain = JevBrain(key: "test-key", writer: writer, send: jev.send)
        return try await brain.decide(Situation(trigger: t, memory: memory, recent: recent),
                                      Menu(tools: try tools(t.kind), limits: limits), deadline: .seconds(1))
    }

    /// HARNESS.md §7: the menu becomes one `act` question, one per argument
    /// of each tool Jev can fill, and a yes/no for `note`, which needs words.
    func testTheMenuBecomesChoiceQuestions() async throws {
        let jev = FakeJev()
        jev.choices = ["act": "stay_quiet"]
        let d = try await decide(jev, trigger(.talk, "talk · 09:14 Tuesday", words: "hello boop"))
        XCTAssertEqual(d.calls, [])
        XCTAssertEqual(jev.last["model"] as? String, "jev-latest")
        let q = jev.questions
        XCTAssertEqual(Set(q.keys), ["act", "say.feeling", "say.word", "face.name", "quiet.minutes", "note"])
        XCTAssertEqual(Set((q["act"]?["criteria"] as! [String: String]).keys), ["stay_quiet", "say", "face", "quiet"])
        XCTAssertEqual(q["note"]?["type"] as? String, "noul")
        let words = q["say.word"]?["criteria"] as! [String: String]
        XCTAssertNotNil(words["none"], "an optional argument can be left out")
        XCTAssertEqual(Set((q["quiet.minutes"]?["criteria"] as! [String: String]).keys), ["15", "30", "60", "120"])
    }

    func testTheChosenToolGetsItsOwnAnswers() async throws {
        let jev = FakeJev()
        jev.choices = ["act": "quiet", "quiet.minutes": "60", "say.feeling": "proud"]
        var d = try await decide(jev, trigger(.talk, "talk · 09:14 Tuesday", words: "shut up for an hour"))
        XCTAssertEqual(d.calls, [ToolCall("quiet", ["minutes": .number(60)])])
        XCTAssertTrue(d.raw?.contains("jev-1.13.0") ?? false, "the answers are kept for the debug log")

        jev.choices = ["act": "say", "say.feeling": "proud", "say.word": "none"]
        d = try await decide(jev, trigger(.event, "turn finished · claude · a · took 18 min · 14:05 Tuesday"))
        XCTAssertEqual(d.calls, [ToolCall("say", ["feeling": .string("proud")])])
        jev.choices["say.word"] = "finally"
        d = try await decide(jev, trigger(.event, "turn finished · claude · a · took 18 min · 14:05 Tuesday"))
        XCTAssertEqual(d.calls, [ToolCall("say", ["feeling": .string("proud"), "word": .string("finally")])])
    }

    /// HARNESS.md §5: a tool past its limit isn't an option at all.
    func testALimitedToolIsLeftOut() async throws {
        let jev = FakeJev()
        _ = try await decide(jev, trigger(.tap, "tapped · 09:30 Tuesday"),
                             limits: ["say limit: once every 5 min on tap, next in 3 min", "quiet limit: only on talk",
                                      "note limit: only on talk"])
        XCTAssertEqual(Set((jev.questions["act"]?["criteria"] as! [String: String]).keys), ["stay_quiet", "face"])
        XCTAssertNil(jev.questions["say.feeling"])
    }

    /// The state is the situation as JSON: who Boop is, memory, what it did
    /// lately and what just happened. Never the key.
    func testTheStateCarriesTheSituation() async throws {
        let jev = FakeJev()
        let earlier = Turn(trigger: Trigger(kind: .tap, line: "tapped · 09:10 Tuesday", ts: 0),
                           did: [ToolCall("face", ["name": .string("smug")])])
        let quiet = Turn(trigger: Trigger(kind: .event, line: "turn started · claude · a · 09:12 Tuesday", ts: 120_000))
        _ = try await decide(jev, Trigger(kind: .talk, line: "talk · 09:14 Tuesday", words: "hi", ts: 240_000),
                             recent: [earlier, quiet])
        let state = jev.last["state"] as! [String: Any]
        XCTAssertEqual(state["boop"] as? String, "# Boop\nBe nice.")
        XCTAssertEqual((state["memory"] as? [String: String])?["long_term"], memory.longTerm)
        XCTAssertEqual(state["now"] as? [String: String], ["happened": "talk · 09:14 Tuesday", "they_said": "hi"])
        let recent = state["recent"] as! [[String: Any]]
        XCTAssertEqual(recent.map { $0["minutes_ago"] as? Int }, [4, 2])
        XCTAssertEqual(recent.map { $0["boop_did"] as? [String] }, [["face(name: \"smug\")"], ["stayed quiet"]])
        let request = String(decoding: try JSONSerialization.data(withJSONObject: jev.last), as: UTF8.self)
        XCTAssertFalse(request.contains("test-key"))
    }

    /// Jev can't write: a yes to `note` has the writer write that one call,
    /// after Jev's own reaction. A no never asks it, and the rules can't write.
    func testWritingGoesToTheWriter() async throws {
        let jev = FakeJev()
        jev.choices = ["act": "say", "say.feeling": "happy", "say.word": "none"]
        jev.nouls = ["note": 0.8]
        let writer = FakeWriter(#"{"calls":[]}"#)
        let said = trigger(.talk, "talk · 10:00 Friday", words: "remember the demo is on Thursday")
        var d = try await decide(jev, writer: writer, said)
        XCTAssertEqual(d.calls, [ToolCall("say", ["feeling": .string("happy")]), ToolCall("note", ["text": .string("demo on Thursday")])])
        XCTAssertTrue(d.raw?.contains("writer: ") ?? false)
        XCTAssertEqual(writer.wrote, ["note"])
        XCTAssertEqual(writer.calls, 0, "the writer only writes; it doesn't decide")

        jev.nouls = ["note": 0.4]
        d = try await decide(jev, writer: writer, said)
        XCTAssertEqual(d.calls.map(\.name), ["say"])
        XCTAssertEqual(writer.wrote, ["note"])

        jev.nouls = ["note": 0.8]
        d = try await decide(jev, said)
        XCTAssertEqual(d.calls.map(\.name), ["say"], "the rules can't write")
    }

    /// Reflection offers only tools that need words: the writer decides it
    /// all, and Jev isn't asked.
    func testReflectionIsTheWritersAlone() async throws {
        let jev = FakeJev()
        let writer = FakeWriter(#"{"calls":[{"tool":"remember","kind":"about_you","text":"Ships on Fridays."}]}"#)
        let d = try await decide(jev, writer: writer, trigger(.reflect, "reflect · yesterday 2026-10-14"))
        XCTAssertEqual(d.calls.map(\.name), ["remember"])
        XCTAssertEqual(jev.requests.count, 0)
    }

    func testAnErrorStatusIsDroppedWithoutItsBody() async throws {
        let jev = FakeJev()
        jev.status = 429
        do {
            _ = try await decide(jev, trigger(.tap, "tapped · 09:30 Tuesday"))
            XCTFail("a 429 answered")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("jev: HTTP 429"))
        }
    }

    /// The setting: `jev` needs a key, and without one Boop keeps the brain
    /// `apple` would give. Asks for the key only when Jev is chosen.
    func testTheJevSettingNeedsAKey() {
        var asked = 0
        var logs: [String] = []
        let fallback = Brains.make("apple").id
        XCTAssertEqual(Brains.make("jev", key: { asked += 1; return nil }, log: { logs.append($0) }).id, fallback)
        XCTAssertTrue(logs.contains { $0.hasPrefix("brain: Jev needs an API key") }, "\(logs)")
        XCTAssertEqual(Brains.make("jev", key: { asked += 1; return "k" }).id, "jev:jev-latest")
        _ = Brains.make("rules", key: { asked += 1; return "k" })
        XCTAssertEqual(asked, 2)
    }

    /// End to end through the harness: Jev's calls are checked and run like
    /// any brain's, and the turn joins the conversation.
    func testTheHarnessRunsJevLikeAnyBrain() async throws {
        let jev = FakeJev()
        jev.choices = ["act": "face", "face.name": "sulky"]
        let rig = HarnessRig(brain: JevBrain(key: "k", writer: RulesBrain(), send: jev.send))
        rig.submit(trigger(.talk, "talk · 13:10 Tuesday", words: "go away"))
        await rig.settle()
        rig.submit(trigger(.tap, "tapped · 13:11 Tuesday"))
        await rig.settle()
        let (handled, records) = rig.snapshot
        XCTAssertEqual(handled, [ToolCall("face", ["name": .string("sulky")]), ToolCall("face", ["name": .string("sulky")])])
        XCTAssertTrue(records.allSatisfy(\.validShape))
        let recent = (jev.last["state"] as! [String: Any])["recent"] as! [[String: Any]]
        XCTAssertEqual(recent.first?["they_said"] as? String, "go away")
        XCTAssertEqual(records[1].prompt.history.count, 1, "the same turn, as a text brain would see it")
    }
}

/// HARNESS.md §4: the transcript is typed turns, and a text brain sees them
/// as the same exchanges it always did.
final class TurnTests: XCTestCase {
    func testTurnsRenderAsTheTextConversation() {
        let memory = Prompt.Memory(steering: "# Boop\n", longTerm: "## Boop\n", shortTerm: "## Today\n")
        let first = Turn(trigger: trigger(.tap, "tapped · 09:30 Tuesday"), did: [ToolCall("face", ["name": .string("happy")])])
        let second = Turn(trigger: trigger(.event, "turn finished · claude · a · took 12 s · 09:31 Tuesday"),
                          limits: ["quiet limit: only on talk"])
        let p = Prompt(Situation(trigger: trigger(.talk, "talk · 09:32 Tuesday", words: "hi"), memory: memory,
                                 recent: [first, second]), Menu(tools: []))
        XCTAssertEqual(p.history, [
            Exchange(user: "## Boop\n\n## Today\n\n--- now ---\ntapped · 09:30 Tuesday",
                     answer: #"{"calls":[{"tool":"face","name":"happy"}]}"#),
            Exchange(user: "--- now ---\nturn finished · claude · a · took 12 s · 09:31 Tuesday\nquiet limit: only on talk",
                     answer: #"{"calls":[]}"#),
        ])
        XCTAssertEqual(p.user, "--- now ---\ntalk · 09:32 Tuesday\nthey said: \"hi\"")
    }

    /// Every brain's calls are checked against the menu, not only a text
    /// brain's JSON.
    func testCallsFromAnyBrainAreChecked() {
        let tools = [ToolDefinition(name: "face", description: "", parameters: [.init("name", .choice(["happy"]))])]
        XCTAssertNil(Answer.check(calls: [ToolCall("face", ["name": .string("happy")])], tools: tools))
        XCTAssertEqual(Answer.check(calls: [ToolCall("face", ["name": .string("sad")])], tools: tools),
                       "face: name isn't one of its choices")
        XCTAssertEqual(Answer.check(calls: [ToolCall("say")], tools: tools), "say isn't offered")
    }
}
