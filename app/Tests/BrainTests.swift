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

// MARK: - The if-else classifiers

func decide(_ classifier: any Classifier, _ i: Input) async throws -> [ToolCall] {
    let menu = Menu(i.menu, definitions: try definitions())
    let answer = try await classifier.classify(context(i), menu, deadline: .seconds(1)).calls
    XCTAssertNil(menu.check(answer), "every answer fits the menu")
    return answer
}

final class ChattyRulesTests: XCTestCase {
    /// HARNESS.md §6: each row of the table in ChattyRules' comment. Every
    /// agent input gets a mumble.
    func testEachRow() async throws {
        let cases: [(Input, [ToolCall])] = [
            (input(.agentStarted), [react("curious")]),
            (input(.agentFinished, tookMs: 1_080_000), [react("excited")]),
            (input(.agentFinished, tookMs: 61_000), [react("excited")]),
            (input(.agentFinished, tookMs: 60_000), [react("proud")]),
            (input(.agentFinished, tookMs: 15_000), [react("proud")]),
            (input(.agentFinished, tookMs: 14_000), [react("happy")]),
            (input(.agentFinished, tookMs: 8_000), [react("happy")]),
            (input(.agentFinished, outcome: .failed), [react("annoyed")]),
            (input(.poked), [react("annoyed")]),
            (input(.said, words: "shut up"), [react("sad")]),
            (input(.said, words: "hello boop"), [react("happy")]),
        ]
        for (i, expected) in cases {
            let calls = try await decide(ChattyRules(), i)
            XCTAssertEqual(calls, expected, i.line + " " + (i.words ?? ""))
        }
    }

    /// It says which row matched, for the transcript.
    func testItSaysWhichRowMatched() async throws {
        let i = input(.agentFinished, outcome: .failed)
        let c = try await ChattyRules().classify(context(i), Menu(i.menu, definitions: try definitions()), deadline: .seconds(1))
        XCTAssertEqual(c.evidence, "failed")
        XCTAssertEqual(ChattyRules().id, "chatty@1")
    }
}

final class NormalRulesTests: XCTestCase {
    /// HARNESS.md §6 and BEHAVIORS.md §6's normal column: each row of the
    /// table in NormalRules' comment. A start and a short turn (under 15 s)
    /// are the rules' alone; 15 s or more is proud.
    func testEachRow() async throws {
        let cases: [(Input, [ToolCall])] = [
            (input(.agentStarted), []),
            (input(.agentFinished, tookMs: 8_000), []),
            (input(.agentFinished, tookMs: 14_999), []),
            (input(.agentFinished, tookMs: 15_000), [react("proud")]),
            (input(.agentFinished, tookMs: 60_000), [react("proud")]),
            (input(.agentFinished, tookMs: 1_080_000), [react("proud")]),
            (input(.agentFinished, outcome: .failed), [react("annoyed")]),
            (input(.poked), [react("annoyed")]),
            (input(.said, words: "shut up"), [react("sad")]),
            (input(.said, words: "hello boop"), [react("happy")]),
            (input(.said, words: "remember the demo is on Thursday"), [react("happy"), remember("today")]),
        ]
        for (i, expected) in cases {
            let calls = try await decide(NormalRules(), i)
            XCTAssertEqual(calls, expected, i.line + " " + (i.words ?? ""))
        }
        XCTAssertEqual(NormalRules().id, "normal@1")
    }
}

final class CalmRulesTests: XCTestCase {
    /// HARNESS.md §6: each row of the table in CalmRules' comment. Only a
    /// failure and what you say get anything.
    func testEachRow() async throws {
        let cases: [(Input, [ToolCall])] = [
            (input(.agentStarted), []),
            (input(.agentFinished, tookMs: 1_080_000), []),
            (input(.agentFinished, tookMs: 8_000), []),
            (input(.agentFinished, outcome: .failed), [react("annoyed")]),
            (input(.poked), []),
            // Hurt keeps to itself; the rest of what you say gets its mumble.
            (input(.said, words: "shut up"), []),
            (input(.said, words: "what are you doing", yelled: true), []),
            (input(.said, words: "be quiet for an hour"), [ToolCall("quiet", ["minutes": .number(60)])]),
            (input(.said, words: "hello boop"), [react("happy")]),
            (input(.said, words: "remember the demo is on Thursday"), [react("happy"), remember("today")]),
            (input(.said, words: "remember I ship on Fridays"), [react("happy"), remember("about_you")]),
        ]
        for (i, expected) in cases {
            let calls = try await decide(CalmRules(), i)
            XCTAssertEqual(calls, expected, i.line + " " + (i.words ?? ""))
        }
        XCTAssertEqual(CalmRules().id, "calm@1")
    }
}

final class PhrasesTests: XCTestCase {
    /// HARNESS.md §6: each row of the table in Phrases' comment, which both
    /// if-else classifiers use for what you said.
    func testEachRow() {
        let quiet = { (m: Int) in ToolCall("quiet", ["minutes": .number(m)]) }
        let cases: [(Input, [ToolCall])] = [
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
            // ARCHITECTURE.md §4: how you like things is a preference; a
            // lasting fact about you is about_you; the rest is today's.
            (input(.said, words: "remember I ship on Fridays"), [react("happy"), remember("about_you")]),
            (input(.said, words: "remember that I always review PRs before lunch"), [react("happy"), remember("about_you")]),
            (input(.said, words: "remember my name is on the release notes every week"), [react("happy"), remember("about_you")]),
            (input(.said, words: "remember I like it quiet before 10am"), [react("happy"), remember("preference")]),
            (input(.said, words: "remember to be quiet", yelled: true), [quiet(30), react("sad", "silent")]),
            (input(.said, words: "note that I'd rather have tests first"), [react("happy"), remember("preference")]),
            (input(.said, words: "note that landing launches Monday"), [react("happy"), remember("today")]),
            (input(.said, words: "remember the demo is on Thursday"), [react("happy"), remember("today")]),
            (input(.said, words: "remember I have a dentist appointment at 3"), [react("happy"), remember("today")]),
            (input(.said, words: "Hello, Boop!"), [react("happy")]),
            (input(.said, words: "see you tomorrow"), [react("happy")]),
            (input(.said, words: "time for lunch"), [react("hopeful")]),
            (input(.said, words: "good job today"), [react("proud")]),
            (input(.said, words: "you're the best"), [react("proud")]),
            (input(.said, words: "this is a thing"), [react("curious")]),
        ]
        for (i, expected) in cases {
            XCTAssertEqual(Phrases.reply(to: i, hurtMumbles: true).0, expected, i.words ?? "")
        }
        // Whole words only: "hi" isn't in "this", "quiet" isn't in "quietly".
        XCTAssertEqual(Input.plain("Hi, THIS is quiet-ish!"), " hi this is quiet ish ")
        XCTAssertFalse(input(.said, words: "speak quietly").asksForQuiet)
        XCTAssertTrue(input(.said, words: "Quiet!").asksForQuiet)
        // Calm keeps hurt to itself: a silent react is only on the menu
        // as quiet starts.
        XCTAssertEqual(Phrases.reply(to: input(.said, words: "shut up"), hurtMumbles: false).0, [])
    }
}

/// HARNESS.md §2: what reaches a brain, and what it may do about it.
final class InputMenuTests: XCTestCase {
    /// A turn's length arrives named, so no brain compares numbers: short
    /// under 15 s, long up to a minute, very long past it.
    func testATurnsLengthIsNamed() {
        XCTAssertEqual([8_000, 14_999, 15_000, 60_000, 60_001, 1_080_000].map { Input.Length(ms: $0) },
                       [.short, .short, .long, .long, .veryLong, .veryLong])
        XCTAssertEqual(input(.agentFinished, tookMs: 20_000).line,
                       "agent finished · done · claude · jetpack · a long turn (20 s) · 14:05 Tuesday")
        XCTAssertEqual(input(.agentFinished, tookMs: 240_000).line,
                       "agent finished · done · claude · jetpack · a very long turn (4 min) · 14:05 Tuesday")
    }

    /// `quiet` is on the menu only when the words ask for it.
    func testQuietIsOnTheMenuOnlyWhenAsked() {
        XCTAssertEqual(input(.said, words: "be quiet for an hour").menu.map(\.tool), ["quiet", "react", "remember"])
        XCTAssertEqual(input(.said, words: "shut up for an hour").menu.map(\.tool), ["react", "remember"])
        XCTAssertEqual(input(.agentFinished).menu.map(\.tool), ["react"])
        // A silent react shows nothing in v1, so it's offered only as quiet starts.
        XCTAssertEqual(input(.said, words: "be quiet").menu[1].only["voice"], nil)
        XCTAssertEqual(input(.said, words: "shut up").menu[0].only["voice"], ["mumble"])
        XCTAssertEqual(input(.agentStarted).menu[0].only["voice"], ["mumble"])
        XCTAssertEqual(input(.poked).menu[0].only["voice"], ["mumble"])
    }
}

// MARK: - Jev

/// Log lines, collected from any thread.
final class Lines: @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    var all: [String] { lock.withLock { lines } }
    func add(_ line: String) { lock.withLock { lines.append(line) } }
}

/// Answers Jev's requests from a script and keeps what was sent. Never
/// reaches the network.
final class FakeJev: @unchecked Sendable {
    let lock = NSLock()
    var requests: [[String: Any]] = []
    var status = 200
    /// Statuses for the next requests in turn, before `status`.
    var statuses: [Int] = []
    /// Choice question → its choice; one left out gets its first option.
    var choices: [String: String] = [:]
    /// Yes/no question → its answer, 0 to 1; one left out is 0.
    var nouls: [String: Double] = [:]

    var send: @Sendable (URLRequest) async throws -> (Data, Int) {
        { [self] request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            let (choices, nouls, status): ([String: String], [String: Double], Int) = lock.withLock {
                requests.append(body)
                return (self.choices, self.nouls, self.statuses.isEmpty ? self.status : self.statuses.removeFirst())
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
            .classify(context(i, window: window), Menu(i.menu, definitions: try definitions()), deadline: .seconds(1))
    }

    /// HARNESS.md §6: the menu becomes questions built from the definitions.
    func testTheMenuBecomesQuestions() async throws {
        let jev = FakeJev()
        let c = try await classify(jev, input(.said, words: "hello boop"))
        XCTAssertEqual(c.calls, [])
        XCTAssertEqual(jev.last["model"] as? String, "jev-latest")
        let q = jev.questions
        XCTAssertEqual(Set(q.keys), ["react", "react.feeling", "remember", "remember.where"],
                       "quiet, and so a silent react, only when asked for quiet")
        XCTAssertEqual(q["react"]?["type"] as? String, "noul")
        // The definition's own question, about `now`, judged by `boop`
        // (TypeSafe's advice: name the part of the state, say what yes means).
        XCTAssertEqual(q["react"]?["instructions"] as? [String: String],
                       ["question": "Does what just happened call for Boop to react?", "about": "`now`",
                        "judge_by": "`boop`, its Examples first"])
        XCTAssertEqual((q["react"]?["criteria"] as? [String: String])?["true"],
                       "Yes: `boop` says to do this for something like `now`.")
        XCTAssertEqual(q["react.feeling"]?["type"] as? String, "choice")
        XCTAssertEqual((q["react.feeling"]?["instructions"] as? [String: String])?["question"],
                       "Which feeling does Boop have about what just happened?")
        XCTAssertEqual((q["react.feeling"]?["criteria"] as? [String: String])?["proud"], "Proud: something long or hard just finished, whatever it was about.")
        XCTAssertNil(q["react.word"], "the writer's")
        XCTAssertNil(q["remember.text"], "the writer's")
        // Where to remember is asked with each place's meaning spelled out.
        let places = q["remember.where"]?["criteria"] as? [String: String]
        XCTAssertEqual(places.map { Set($0.keys) }, ["today", "about_you", "preference"])
        XCTAssertTrue(places?["about_you"]?.contains("durable fact") ?? false)

        _ = try await classify(jev, input(.said, words: "be quiet please"))
        XCTAssertEqual(Set(jev.questions.keys), ["quiet", "quiet.minutes", "react", "react.feeling", "react.voice", "remember",
                                                 "remember.where"])
        let minutes = jev.questions["quiet.minutes"]?["criteria"] as? [String: String]
        XCTAssertEqual(Set(minutes?.keys ?? [:].keys), ["15", "30", "60", "120"])
        XCTAssertEqual(minutes?["30"], "Half an hour, or when they don't say how long.")
    }

    func testYesesBecomeCallsWithTheirChoices() async throws {
        let jev = FakeJev()
        jev.nouls = ["quiet": 0.9, "react": 0.8, "remember": 0.3]
        jev.choices = ["quiet.minutes": "60", "react.feeling": "sulky", "react.voice": "silent"]
        let c = try await classify(jev, input(.said, words: "be quiet for an hour"))
        XCTAssertEqual(c.calls, [ToolCall("quiet", ["minutes": .number(60)]), react("sulky", "silent")])
        XCTAssertTrue(c.evidence?.contains("quiet 0.90") ?? false, c.evidence ?? "")
        XCTAssertTrue(c.evidence?.contains("react.feeling sulky 0.90") ?? false, c.evidence ?? "")

        jev.nouls = ["react": 0.7, "remember": 0.93]
        jev.choices = ["react.feeling": "happy", "react.voice": "mumble", "remember.where": "about_you"]
        let noted = try await classify(jev, input(.said, words: "remember I ship on Fridays"))
        XCTAssertEqual(noted.calls, [react("happy"), remember("about_you")])
    }

    /// The state is the pass as JSON: who Boop is, memory, what happened
    /// lately (with what Boop did), and now. Never the key.
    func testTheStateCarriesTheWindow() async throws {
        let earlier = input(.agentFinished, tookMs: 600_000, rules: "cheer", at: 0)
        let now = input(.said, words: "hi", at: 4)
        let window: [Transcript.Entry] = [
            .input(earlier), .rules("cheer"), .decided(by: "x", [react("proud")], evidence: nil),
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
        XCTAssertEqual(recent[0]["rules"] as? String, "cheer")
        XCTAssertNil(recent[1]["boop_did"], "an aside")
        let request = String(decoding: try JSONSerialization.data(withJSONObject: jev.last), as: UTF8.self)
        XCTAssertFalse(request.contains("test-key"))
    }

    /// Jev never writes, so it doesn't get steering.md's Writing section.
    func testJevDoesntReadTheWritersSection() {
        XCTAssertEqual(JevClassifier.boop("<!-- note -->\n# Boop\n\n## Examples\nx\n\n## Writing\nw\n\n## Never\nn\n"),
                       "# Boop\n\n## Examples\nx\n\n## Never\nn")
        XCTAssertEqual(JevClassifier.boop("# Boop\n\n## Writing\nw\n"), "# Boop")
        let steering = try? String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        let boop = JevClassifier.boop(steering ?? "")
        XCTAssertTrue(boop.contains("## Examples") && boop.contains("## Never"), boop)
        XCTAssertFalse(boop.contains("## Writing"))
    }

    /// steering.md's Writing names `react`'s word sources as the definition
    /// does, in the same order, so the writer can tie each to its words.
    func testWritingNamesTheWordSources() throws {
        let steering = try String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        let writing = try XCTUnwrap(steering.components(separatedBy: "## Writing").last?.lowercased())
        let at = ReactAction.wordSources.map { writing.range(of: $0 + ":")?.lowerBound }
        XCTAssertFalse(at.contains(nil), "every source in Writing: \(ReactAction.wordSources)")
        XCTAssertEqual(at.compactMap { $0 }, at.compactMap { $0 }.sorted(), "in the same order")
    }

    /// HARNESS.md §6: a 429, 529 or other 5xx is tried once more, 0.3 s
    /// later, as TypeSafe advises; any other failure isn't.
    func testABusyServerIsTriedOnceMore() async throws {
        XCTAssertEqual(JevClassifier.retryAfterMs, 300)
        let jev = FakeJev()
        jev.statuses = [529]
        _ = try await classify(jev, input(.agentStarted))
        XCTAssertEqual(jev.lock.withLock { jev.requests.count }, 2)

        let busy = FakeJev()
        busy.statuses = [429, 429]
        do {
            _ = try await classify(busy, input(.agentStarted))
            XCTFail("answered")
        } catch {
            XCTAssertEqual(error as? BrainError, BrainError("jev: HTTP 429"))
        }
        XCTAssertEqual(busy.lock.withLock { busy.requests.count }, 2, "once more, not again and again")

        let refused = FakeJev()
        refused.statuses = [401]
        _ = try? await classify(refused, input(.agentStarted))
        XCTAssertEqual(refused.lock.withLock { refused.requests.count }, 1, "a bad key isn't retried")
    }

    /// HARNESS.md §6: in normal mode, Jev has half the input's deadline;
    /// an error, a refusal or no answer by then, and normal's table decides
    /// that pass instead, saying so in the evidence and the log.
    func testNormalsTableDecidesWhenJevCant() async throws {
        XCTAssertEqual(FallbackClassifier.modelMs(.seconds(5)), 2500)
        XCTAssertEqual(FallbackClassifier.modelMs(.seconds(4)), 2000)
        let failed = input(.agentFinished, outcome: .failed)
        let menu = Menu(failed.menu, definitions: try definitions())
        let logs = Lines()

        let badKey = FakeJev()
        badKey.statuses = [401]
        let normal = FallbackClassifier(JevClassifier(key: "k", send: badKey.send), else: NormalRules(), log: logs.add)
        let c = try await normal.classify(context(failed), menu, deadline: .seconds(5))
        XCTAssertEqual(c.calls, [react("annoyed")])
        XCTAssertEqual(c.evidence, "jev:jev-latest failed (jev: HTTP 401) · normal@1: failed")
        XCTAssertEqual(logs.all, ["brain: jev:jev-latest failed (jev: HTTP 401); normal@1 decided"])
        XCTAssertEqual(normal.id, "jev:jev-latest")

        // Slower than half the deadline: the table, in time for the writer.
        let slow = FallbackClassifier(FakeClassifier(delayMs: 400) { _ in [] }, else: NormalRules())
        let start = ContinuousClock.now
        let late = try await slow.classify(context(failed), menu, deadline: .milliseconds(400))
        XCTAssertEqual(late.calls, [react("annoyed")])
        XCTAssertTrue(late.evidence?.hasPrefix("fake-classifier@1 failed (late") ?? false, late.evidence ?? "")
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(390))

        // Jev's own answer when it has one, doing nothing included.
        let answered = FakeJev()
        let quiet = try await FallbackClassifier(JevClassifier(key: "k", send: answered.send), else: NormalRules())
            .classify(context(failed), menu, deadline: .seconds(5))
        XCTAssertEqual(quiet.calls, [])
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
        let menu = Menu(i.menu, definitions: try definitions())
        let window: [Transcript.Entry] = [.input(i), .decided(by: "chatty@1", calls, evidence: nil)]
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

    /// The request is what just happened and what Boop decided, then a line
    /// per slot; not the rest of the window, whose words the model copied
    /// (ARCHITECTURE.md §11).
    func testAppleSeesTheDecisionAndTheSlots() throws {
        var (c, s) = try slots()
        let earlier = input(.agentFinished, tookMs: 600_000, rules: "cheer", at: -3)
        c.window = [.input(earlier), .ran(react("proud", word: "finally"), .done("ok"))] + c.window
        let request = AppleWriter.request(c, s)
        XCTAssertEqual(request, """
            --- now ---
            you said · 14:05 Tuesday
            They just said: "remember the demo is on Thursday"
            Boop decided: react(feeling: happy, voice: mumble), remember(where: today)
            --- write ---
            react.word: the mumble's one real word, from its list, as Writing says; none only when nothing fits.
            remember.text: at most 80 characters. Short-term, for today: a fact about a project or this session, like what \
            something is, a date, or what they're doing now. Plain words, no code; leave it empty if nothing is worth keeping.
            """)
        XCTAssertEqual(s.first?.sources, ReactAction.wordSources, "the word names where it can come from")
        XCTAssertEqual(AppleWriter.values(#"{"react_word_from":"the feeling","react_word":"yay"}"#, s), ["react.word": "yay"])
        // Chatty mode's writer asks again for a word left empty, without `none`.
        XCTAssertTrue(AppleWriter.missesAWord(["remember.text": "demo"], s))
        XCTAssertFalse(AppleWriter.missesAWord(["react.word": "okay"], s))
        XCTAssertEqual(AppleWriter.wordChoices(["yay", "tests"], false), ["none", "yay", "tests"])
        XCTAssertEqual(AppleWriter.wordChoices(["yay", "tests"], true), ["yay", "tests"])
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
        _ = try AppleWriter.schema(s, wordRequired: true)
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

    /// HARNESS.md §6: each mode's brain. Jev needs a key, asked for only
    /// when it's chosen; without one, normal decides with its own table.
    func testEachModeHasItsBrain() {
        var asked = 0
        let logs = Lines()
        XCTAssertEqual(Brains.classifier(for: .chatty, key: { asked += 1; return "k" }).id, "chatty@1")
        XCTAssertEqual(Brains.classifier(for: .calm, key: { asked += 1; return "k" }).id, "calm@1")
        XCTAssertEqual(Brains.classifier(for: .normal, key: { asked += 1; return "k" }).id, "jev:jev-latest")
        XCTAssertEqual(Brains.classifier(for: .normal, key: { asked += 1; return nil }, log: logs.add).id, "normal@1")
        XCTAssertTrue(logs.all.contains { $0.hasPrefix("brain: Jev needs an API key") }, "\(logs.all)")
        // Normal's Jev has its table behind it; the override is Jev alone.
        XCTAssertTrue(Brains.classifier(for: .normal, key: { "k" }) is FallbackClassifier)
        XCTAssertTrue(Brains.classifier(for: .normal, override: "jev", key: { "k" }) is JevClassifier)
        XCTAssertEqual(asked, 2)
        // Overrides, for one run.
        XCTAssertEqual(Brains.classifier(for: .normal, override: "calm").id, "calm@1")
        XCTAssertEqual(Brains.classifier(for: .chatty, override: "normal").id, "normal@1")
        XCTAssertEqual(Brains.classifier(for: .calm, override: "jev", key: { "k" }).id, "jev:jev-latest")
        XCTAssertEqual(Brains.writer(for: .calm, override: "none").id, "none")
        XCTAssertEqual(Brains.writer(for: .calm, override: "deepseek").id, "deepseek:deepseek-flash")
        // Apple's model writes in every mode, and must find a word in chatty.
        for mode in Mode.allCases {
            let writer = Brains.writer(for: mode)
            if AppleWriter.unavailableReason == nil {
                XCTAssertEqual((writer as? AppleWriter)?.wordRequired, mode == .chatty, mode.rawValue)
            } else {
                XCTAssertEqual(writer.id, "none")
            }
        }
    }
}
