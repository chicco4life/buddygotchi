import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The eval runner (plan/EVALS.md), with a scripted brain: the scenarios
/// read, each step reaches the core, and each pass is checked. The evals
/// themselves ask Jev (`boopdev eval`).
final class EvalTests: XCTestCase {
    static let scenarios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Evals/scenarios")

    func testEveryScenarioReads() throws {
        let all = try Scenario.load(directory: Self.scenarios)
        XCTAssertGreaterThanOrEqual(all.count, 7)
        XCTAssertTrue(all.allSatisfy { !$0.story.isEmpty }, "every scenario says its case in plain words")
        XCTAssertTrue(all.contains { $0.always }, "some scenarios are Boop's character")
        XCTAssertTrue(all.contains { $0.steps.contains { $0.session == "s2" } }, "a step can be another session's")
        XCTAssertEqual(Scenario.range("1-3"), 1...3)
        XCTAssertEqual(Scenario.range("2-"), 2...Int.max)
        XCTAssertEqual(Scenario.range("-4"), 0...4)
        XCTAssertEqual(Scenario.range("3"), 3...3)
        XCTAssertNil(Scenario.range("3-1"))
        XCTAssertNil(Scenario.range("-"))
        XCTAssertEqual(Scenario.ms("2m30s"), 150_000)
        XCTAssertEqual(Scenario.ms("1h5m"), 3_900_000)
        XCTAssertNil(Scenario.ms("5x"))
    }

    /// A brain that answers the way the scenario wants passes it, which
    /// checks that every expected step wakes the brain and that the mood and
    /// word are read as the actions leave them. A reaction's moment goes
    /// nowhere and counts as played at once, so HISTORY shows it plainly
    /// (EVALS.md §1).
    func testTheTestsFightBackWithAnAgreeableBrain() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let now = state.components(separatedBy: "\nNOW (").last ?? ""
            func a(_ c: String) -> Answer { Answer(choice: c, probabilities: [c: 0.9]) }
            if now.contains("passed") {
                return ["mood": a("proud"), "react.mood": a("proud"), "word.feeling": a("finally"), "word.about": a("tests")]
            }
            if now.contains("failed") {
                return ["mood": a("determined"), "react.mood": a("determined"), "word.feeling": a("oops"), "word.about": a("none")]
            }
            return ["mood": a(state.contains("MOOD\nDetermined") ? "determined" : "happy"), "react.mood": a("none"),
                    "word.feeling": a("none"), "word.about": a("none")]
        }
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("04-tests-fight-back.json"))
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertEqual(result.checks.count, 4)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(result.checks[2].word, "oops")
        XCTAssertEqual(result.checks[2].mood, "determined")
        XCTAssertEqual(result.checks[3].mood, "proud", "2 minutes after the last failure: no rule holds a mood")
        let last = try XCTUnwrap(states.all.last)
        XCTAssertTrue(last.contains("\n  Boop made a determined face, held once, and mumbled \"…oops!\"\n"), last)
    }

    /// EVALS.md §3: a step's `reaction` says how the reactions its passes
    /// start end, so HISTORY can show one still in progress, or leave out
    /// one that didn't happen; any other value doesn't load.
    func testAStepSaysHowItsReactionEnds() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let proud = Answer(choice: "proud", probabilities: ["proud": 1])
            return ["react.mood": proud, "mood": proud]
        }
        let eval = Eval(brain: brain, steering: RuntimeTests.steering)
        for (file, shown) in [("11-comeback-still-showing.json", true), ("12-comeback-that-didnt-happen.json", false)] {
            _ = try await eval.run(try Scenario(file: Self.scenarios.appendingPathComponent(file)))
            let finish = try XCTUnwrap(states.all.last)
            XCTAssertEqual(finish.contains("\n  Boop made a proud face, held once, and mumbled. (in progress)\n"), shown, finish)
            XCTAssertEqual(finish.contains("after failing.\n  Boop made"), shown, "one that didn't happen isn't shown: \(finish)")
        }
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-reaction-\(UUID().uuidString).json")
        try Data(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","reaction":"maybe","expect":{"react":"none"}}]}"#.utf8)
            .write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        do {
            _ = try Scenario(file: bad)
            XCTFail("a reaction of \"maybe\" loaded")
        } catch {
            XCTAssertTrue("\(error)".contains("step 1: reaction is"), "\(error)")
        }
    }

    /// EVALS.md §3: a turn start's `prompt` and a finish's `message` reach
    /// Jev as NOW's notes (`27-agent-gives-up`); on any other step they
    /// don't load.
    func testAStepCarriesThePromptAndLastMessage() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            return [:]
        }
        _ = try await Eval(brain: brain, steering: RuntimeTests.steering)
            .run(try Scenario(file: Self.scenarios.appendingPathComponent("27-agent-gives-up.json")))
        XCTAssertTrue(states.all.first?.contains("\n  You asked: \"fix the login redirect\"") == true, states.all.first ?? "no pass")
        XCTAssertTrue(states.all.last?.contains("\n  Its last message: \"I couldn't get the login working.") == true, states.all.last ?? "no pass")
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","prompt":"hi","expect":{"react":"none"}}]}"#, "step 1: prompt is only"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn failed","at":"0s","message":"hi","expect":{"react":"none"}}]}"#, "step 1: message is only")] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bad-note-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                _ = try Scenario(file: file)
                XCTFail("loaded: \(json)")
            } catch {
                XCTAssertTrue("\(error)".contains(why), "\(error)")
            }
        }
    }

    /// A brain that stays quiet fails what should mumble, and the report
    /// says what was wanted and what came.
    func testAQuietBrainFailsAndTheReportSaysWhy() async throws {
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("05-pokes-in-a-row.json"))
        let result = try await Eval(brain: ScriptedBrain(always: [:]), steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let report = Eval.report([result])
        XCTAssertEqual(report.first, "FAIL  05-pokes-in-a-row.json  Four pokes in a row make Boop grumpy, briefly")
        XCTAssertTrue(report[1].contains("wanted react grumpy, word none|nope|ugh, loops once, mood grumpy; got react none, animation none, word none, loops none, mood happy"), report[1])
        XCTAssertEqual(Eval.summary([[result]]), "0/1 passed")
    }

    /// EVALS.md §3: a scenario without a case doesn't load, nor one with a
    /// check it doesn't know.
    func testAScenarioNeedsItsCaseAndKnownChecks() throws {
        for (json, why) in [(#"{"name":"n","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "needs name, case"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"max_fun":2},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks has only"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"reactions":"lots"},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks.reactions")] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                _ = try Scenario(file: file)
                XCTFail("loaded: \(json)")
            } catch {
                XCTAssertTrue("\(error)".contains(why), "\(error)")
            }
        }
    }

    /// EVALS.md §3's whole-run checks, against a brain that makes the same
    /// excited "tests" face at every pass and never changes the mood, over
    /// five quick wins: it's the same reaction ten times running (starts
    /// and finishes), of one kind, and the mood never moves.
    func testWholeRunChecksCatchTheSameReactionAgainAndAgain() async throws {
        let brain = ScriptedBrain(always: ["react.mood": Answer(choice: "excited", probabilities: ["excited": 0.9]),
                                           "word.about": Answer(choice: "tests", probabilities: ["tests": 0.9])])
        let steps = (0..<5).map { i in
            #"{"event":"turn started","at":"\#(i)m"},{"event":"command","at":"\#(i)m20s","topic":"tests","failed":false},"#
                + #"{"event":"turn finished","at":"\#(i)m30s"}"#
        }.joined(separator: ",")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("19-same-win-again.json")
        try Data(#"{"name":"n","case":"c","why":"w","checks":{"max_same_in_a_row":2,"min_variety":2,"reactions":"2-","mood_changes":"-2"},"steps":[\#(steps)]}"#.utf8)
            .write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let scenario = try Scenario(file: file)
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let failed = Dictionary(uniqueKeysWithValues: result.runChecks.map { ($0.name, $0) })
        XCTAssertEqual(failed["max_same_in_a_row 2"]?.passed, false)
        XCTAssertTrue(failed["max_same_in_a_row 2"]?.detail.hasSuffix("in a row (excited \"tests\")") ?? false,
                      failed["max_same_in_a_row 2"]?.detail ?? "")
        XCTAssertEqual(failed["min_variety 2"]?.passed, false)
        XCTAssertEqual(failed["reactions 2 or more"]?.passed, true)
        XCTAssertEqual(failed["mood_changes 0-2"]?.passed, true)
        let report = Eval.report([result], story: scenario.story)
        XCTAssertEqual(report[1], "  case: " + scenario.story)
        let asGap = Eval.report([result], story: scenario.story, gap: "why")
        XCTAssertTrue(asGap[0].hasPrefix("GAP   19-same-win-again.json"), asGap[0])
        XCTAssertEqual(asGap[1], "  gap: why")
        XCTAssertEqual(Eval.summary([[result]], gaps: 1), "0/1 passed (1 known gaps failed)")
        XCTAssertTrue(report.contains { $0.hasPrefix("  whole run: max_same_in_a_row 2: ") }, report.joined(separator: "\n"))
        XCTAssertTrue(Eval.timeline(result).contains { $0.contains("→ excited \"tests\", once  [happy]") },
                      Eval.timeline(result).joined(separator: "\n"))
    }

    /// The quiet and mood checks, on a made-up run: a turn from 0 to 20
    /// minutes with reactions at 1 and 9 minutes is quiet for 11 minutes
    /// at the end; happy → determined → happy inside 40 s is a bounce.
    func testQuietAndBounceChecks() {
        func pass(_ s: Int64, _ face: String?, _ mood: String) -> Eval.Pass {
            Eval.Pass(atMs: s * 1000, line: "l", reaction: face.map { Eval.Reaction(face: $0, animation: "none", word: "none") },
                      loops: face == nil ? nil : "once", mood: mood, dropped: nil)
        }
        var checks = Scenario.Checks()
        checks.quietWorkingMs = 360_000
        checks.bounceMs = 60_000
        checks.moodChanges = 1...3
        let out = Eval.judge(checks, timeline: [pass(60, "happy", "happy"), pass(540, "determined", "determined"),
                                                pass(580, nil, "happy")], working: [(0, 1_200_000)])
        XCTAssertEqual(out.map(\.passed), [false, true, false])
        XCTAssertEqual(out[0].detail, "the longest quiet stretch of work was 11m00s, from 9m00s")
        XCTAssertEqual(out[1].detail, "2: happy → determined → happy")
        XCTAssertEqual(out[2].detail, "happy → determined at 9m00s, back at 9m40s")
    }
}
