import Foundation
import XCTest
@testable import BoopKit

/// The harness eval suite (plan/EVALS.md) passes in every mode, with its
/// if-else table and no writer, and the runner checks each step's whole
/// window of passes.
final class EvalTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..")
        .standardizedFileURL
    static let scenarios = root.appendingPathComponent("app/Evals/scenarios")

    func runner() throws -> Eval {
        let steering = try String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        return Eval(steering: steering, memory: EvalTests.root.appendingPathComponent("app/Tests/Fixtures/memory"))
    }

    /// Every scenario in every mode it runs in.
    func results() async throws -> [Eval.Result] {
        let scenarios = try Scenario.load(directory: EvalTests.scenarios)
        XCTAssertFalse(scenarios.isEmpty)
        let eval = try runner()
        var results: [Eval.Result] = []
        for scenario in scenarios {
            for mode in Eval.deterministic where scenario.modes.contains(mode) {
                results.append(try await eval.run(scenario, mode: mode))
            }
        }
        return results
    }

    func testEveryScenarioPasses() async throws {
        let results = try await results()
        XCTAssertEqual(Set(results.map(\.mode)), Set(Mode.allCases))
        for result in results {
            XCTAssertTrue(result.passed, "\(result.scenario.file) in \(result.mode.rawValue)\n" + Eval.diff(result))
        }
    }

    /// BEHAVIORS.md §6, across every scenario: in chatty, every agent input
    /// and poke streak the brain decides on gets a mumble; in normal, a
    /// start never does; in calm, the brain mumbles only at a failed turn or
    /// when you talk to it, and the rules never chatter.
    func testEachModeKeepsItsCharacter() async throws {
        for result in try await results() {
            var mode = result.mode
            for (step, scenarioStep) in zip(result.steps, result.scenario.steps) {
                // A step's window is in the mode it switched to, if it did.
                mode = scenarioStep.event.mode ?? mode
                guard scenarioStep.classifier == nil else { continue }
                for line in step.actual {
                    let mumble = line.contains("voice: mumble")
                    switch mode {
                    case .chatty:
                        if line.hasPrefix("agent ") || line.hasPrefix("poked ") {
                            XCTAssertTrue(mumble, "\(result.scenario.file): \(line)")
                        }
                    case .calm:
                        let allowed = line.hasPrefix("you said ") || line.hasPrefix("agent finished → react(feeling: annoyed")
                        XCTAssertTrue(!mumble || allowed, "\(result.scenario.file): \(line)")
                        XCTAssertFalse(line.hasPrefix("rules → mumble"), "\(result.scenario.file): \(line)")
                    case .normal:
                        if line.hasPrefix("agent started") {
                            XCTAssertFalse(mumble, "\(result.scenario.file): \(line)")
                        }
                    }
                }
            }
        }
    }

    func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    func run(_ json: String, mode: Mode = .chatty) async throws -> Eval.Result {
        let url = try write(json)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await runner().run(Scenario(file: url), mode: mode)
    }

    /// An expectation that leaves out a pass fails: a step's window is
    /// checked whole, and an empty list means no input at all.
    func testAnUnexpectedPassFails() async throws {
        let result = try await run("""
            {"name": "x", "steps": [
              {"input": {"at": "0m", "event": "turn started"}, "expect": []},
              {"input": {"at": "12m", "event": "turn finished"}, "expect": []}]}
            """)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.steps.map(\.actual),
                       [["agent started → react(feeling: curious, voice: mumble)"],
                        ["agent finished → react(feeling: excited, voice: mumble)"]])
    }

    /// Scripted stages replace the brains for that step only. A tap never
    /// reaches the brain (HARNESS.md §2), and a memory line nobody wrote
    /// drops its call.
    func testScriptedStagesAndDrops() async throws {
        let result = try await run("""
            {"name": "x", "steps": [
              {"input": {"at": "0m", "event": "turn started"}, "classifier": "refused",
               "expect": ["agent started → dropped (refused)"]},
              {"input": {"at": "1m", "event": "tap"}, "expect": []},
              {"input": {"at": "2m", "event": "talk", "words": "remember the demo is at noon"},
               "expect": ["you said → react(feeling: happy, voice: mumble), remember(where: today) dropped (unwritten)"]},
              {"input": {"at": "3m", "event": "talk", "words": "remember the demo is at noon"},
               "writer": {"remember.text": "demo at noon"},
               "expect": ["you said → react(feeling: happy, voice: mumble), remember(text: \\"demo at noon\\", where: today)"]},
              {"input": {"at": "4m", "event": "turn finished"}, "classifier": "late",
               "expect": ["agent finished → dropped (late)"]},
              {"input": {"at": "5m", "event": "talk", "words": "hi"}, "writer": {"error": "boom"},
               "expect": ["you said → react(feeling: happy, voice: mumble) · writer failed (error)"]}]}
            """)
        XCTAssertTrue(result.passed, Eval.diff(result))
    }

    /// EVALS.md §3: expectations for each mode, a switch mid-scenario, and
    /// the rules' own reactions when a scenario asks for them.
    func testModesAndRuleReactions() async throws {
        let json = """
            {"name": "x", "modes": ["chatty", "calm"], "rules": true, "steps": [
              {"input": {"at": "0s", "event": "turn started"},
               "expect": {"chatty": ["agent started → react(feeling: curious, voice: mumble)"],
                          "calm": ["agent started → nothing"]}},
              {"input": {"at": "8s", "event": "turn finished"},
               "expect": {"chatty": ["rules → cheer", "agent finished → react(feeling: happy, voice: mumble)"],
                          "calm": ["agent finished → nothing"]}},
              {"input": {"at": "10s", "event": "mode", "mode": "chatty"}, "expect": []},
              {"input": {"at": "20s", "event": "turn started"},
               "expect": ["agent started → react(feeling: curious, voice: mumble)"]},
              {"input": {"at": "30s", "event": "turn finished"},
               "expect": ["rules → cheer", "agent finished → react(feeling: happy, voice: mumble)"]}]}
            """
        let url = try write(json)
        defer { try? FileManager.default.removeItem(at: url) }
        let scenario = try Scenario(file: url)
        XCTAssertEqual(scenario.modes, [.chatty, .calm])
        XCTAssertEqual(scenario.steps[2].event.mode, .chatty)
        for mode in scenario.modes {
            let result = try await runner().run(scenario, mode: mode)
            XCTAssertTrue(result.passed, mode.rawValue + "\n" + Eval.diff(result))
            XCTAssertEqual(result.classifier, mode == .calm ? "calm@1" : "chatty@1")
        }
        let partial = try write(#"{"name": "x", "modes": ["calm"], "steps": [{"input": {"at": "0m", "event": "tap"}, "expect": {"chatty": []}}]}"#)
        defer { try? FileManager.default.removeItem(at: partial) }
        try XCTAssertThrowsError(try Scenario(file: partial)) { XCTAssertTrue("\($0)".contains("expect needs a list for each of calm")) }
        let noMode = try write(#"{"name": "x", "steps": [{"input": {"at": "0m", "event": "mode"}, "expect": []}]}"#)
        defer { try? FileManager.default.removeItem(at: noMode) }
        try XCTAssertThrowsError(try Scenario(file: noMode))
    }

    /// EVALS.md §3: a command's topic and result, a yell, and times in ms.
    func testCommandsYellsAndMilliseconds() throws {
        XCTAssertEqual(Scenario.ms("500ms"), 500)
        XCTAssertEqual(Scenario.ms("90s"), 90_000)
        let url = try write("""
            {"name": "x", "steps": [
              {"input": {"at": "0m", "event": "command", "topic": "tests", "failed": true}, "expect": []},
              {"input": {"at": "1500ms", "event": "talk", "words": "", "yelled": true}, "expect": []}]}
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        let scenario = try Scenario(file: url)
        XCTAssertEqual(scenario.steps[0].event.topic, "tests")
        XCTAssertTrue(scenario.steps[0].event.failed)
        XCTAssertEqual(scenario.steps[1].event.atMs, 1500)
        XCTAssertTrue(scenario.steps[1].event.yelled)
        let noTopic = try write(#"{"name": "x", "steps": [{"input": {"at": "0m", "event": "command"}, "expect": []}]}"#)
        defer { try? FileManager.default.removeItem(at: noTopic) }
        try XCTAssertThrowsError(try Scenario(file: noTopic))
    }

    /// EVALS.md §3: a value lists what fits; `none` lets it be left out; `*`
    /// is any run of characters. The writer's arguments aren't checked when
    /// nothing writes, and a call that needs one is then expected dropped.
    func testExpectationsListWhatFits() throws {
        let defs = try definitions()
        func record(_ ran: [(ToolCall, ActionOutcome)], writeFailed: String? = nil) -> Harness.Record {
            var r = Harness.Record(input: input(.said, words: "remember the demo"), classifier: "c", writer: "w", window: 1)
            r.ran = ran
            r.writeFailed = writeFailed
            return r
        }
        let word = try Expectation("you said → react(feeling: happy|proud, voice: mumble, word: okay|yes)")
        XCTAssertTrue(word.matches(record([(react("proud", word: "yes"), .done(""))]), writing: true, definitions: defs))
        XCTAssertFalse(word.matches(record([(react("proud", word: "yay"), .done(""))]), writing: true, definitions: defs))
        XCTAssertFalse(word.matches(record([(react("sad", word: "yes"), .done(""))]), writing: true, definitions: defs))
        XCTAssertFalse(word.matches(record([(react("proud"), .done(""))]), writing: true, definitions: defs),
                       "a word left out fits only with none")
        XCTAssertTrue(word.matches(record([(react("proud"), .done(""))]), writing: false, definitions: defs),
                      "with no writer, words aren't checked")
        try XCTAssertTrue(try Expectation("you said → react(feeling: happy, voice: mumble, word: okay|none)")
            .matches(record([(react("happy"), .done(""))]), writing: true, definitions: defs))
        try XCTAssertFalse(try Expectation("you said → react(feeling: happy, voice: mumble)")
            .matches(record([(react("happy", word: "hi"), .done(""))]), writing: true, definitions: defs),
                       "a word nobody expected fails")

        let note = try Expectation(#"you said → remember(text: "*Thursday*|*thu*", where: today)"#)
        XCTAssertTrue(note.matches(record([(remember("today", "demo on thursday"), .done(""))]), writing: true, definitions: defs))
        XCTAssertFalse(note.matches(record([(remember("today", "demo friday"), .done(""))]), writing: true, definitions: defs))
        XCTAssertTrue(note.matches(record([(remember("today"), .dropped("nothing was written"))]), writing: false, definitions: defs),
                      "with no writer, the note is expected dropped (unwritten)")
        XCTAssertFalse(note.matches(record([(remember("today"), .dropped("nothing was written"))]), writing: true, definitions: defs))

        let failed = try Expectation("you said → react(feeling: happy, voice: mumble) · writer failed (error)")
        XCTAssertTrue(failed.matches(record([(react("happy"), .done(""))], writeFailed: "apple: boom"), writing: true, definitions: defs))
        try XCTAssertEqual(try Expectation("you said → dropped (off menu)").answer, .dropped("off menu"))
        try XCTAssertThrowsError(try Expectation("you said: react(feeling: happy)"))
        try XCTAssertThrowsError(try Expectation("you yelled → nothing"))
    }

    func testABadScenarioNamesTheStep() throws {
        let url = try write("""
            {"name": "x", "steps": [{"input": {"at": "0m", "event": "turn started"}, "expect": []},
                                    {"input": {"at": "0m", "event": "tap"}, "expect": []}]}
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try Scenario(file: url)
            XCTFail("a step at the same time as the one before should be refused")
        } catch {
            XCTAssertTrue("\(error)".contains("step 2: at must be later"), "\(error)")
        }
    }
}
