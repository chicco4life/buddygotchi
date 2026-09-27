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
            if now.contains("3 in a row") {
                return ["mood": a("grumpy"), "react": a("grumpy"), "word.feeling": a("again"), "word.about": a("tests")]
            }
            if now.contains("passed") {
                return ["mood": a("proud"), "react": a("proud"), "word.feeling": a("finally"), "word.about": a("tests")]
            }
            return ["mood": a(state.contains("MOOD\nGrumpy") ? "grumpy" : "happy"), "react": a("none"),
                    "word.feeling": a("none"), "word.about": a("none")]
        }
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("04-tests-fight-back.json"))
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertEqual(result.checks.count, 4)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(result.checks[2].word, "again")
        XCTAssertEqual(result.checks[2].mood, "grumpy")
        XCTAssertEqual(result.checks[3].mood, "proud", "2 minutes after turning grumpy: no rule holds a mood")
        let last = try XCTUnwrap(states.all.last)
        XCTAssertTrue(last.contains("\n  Boop made a grumpy face, held once, and mumbled \"…again!\"\n"), last)
    }

    /// EVALS.md §3: a step's `reaction` says how the reactions its passes
    /// start end, so HISTORY can show one still in progress or one that
    /// didn't happen; any other value doesn't load.
    func testAStepSaysHowItsReactionEnds() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let proud = Answer(choice: "proud", probabilities: ["proud": 1])
            return ["react": proud, "mood": proud]
        }
        let eval = Eval(brain: brain, steering: RuntimeTests.steering)
        for (file, marker) in [("11-comeback-still-showing.json", " (in progress)\n"),
                               ("12-comeback-that-didnt-happen.json", " (didn't happen: waited too long)\n")] {
            _ = try await eval.run(try Scenario(file: Self.scenarios.appendingPathComponent(file)))
            let finish = try XCTUnwrap(states.all.last)
            XCTAssertTrue(finish.contains("\n  Boop made a proud face, held once, and mumbled." + marker), finish)
        }
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-reaction-\(UUID().uuidString).json")
        try Data(#"{"name":"n","why":"w","steps":[{"event":"pokes","at":"0s","reaction":"maybe","expect":{"react":"none"}}]}"#.utf8)
            .write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        do {
            _ = try Scenario(file: bad)
            XCTFail("a reaction of \"maybe\" loaded")
        } catch {
            XCTAssertTrue("\(error)".contains("step 1: reaction is"), "\(error)")
        }
    }

    /// A brain that stays quiet fails what should mumble, and the report
    /// says what was wanted and what came.
    func testAQuietBrainFailsAndTheReportSaysWhy() async throws {
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("05-poke-streak.json"))
        let result = try await Eval(brain: ScriptedBrain(always: [:]), steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let report = Eval.report([result])
        XCTAssertEqual(report.first, "FAIL  05-poke-streak.json  Poked again and again, Boop is grumpy")
        XCTAssertTrue(report[1].contains("wanted react grumpy, word none|nope|ugh, loops once, mood happy; got react none, word none, loops none, mood happy"), report[1])
        XCTAssertEqual(Eval.summary([[result]]), "0/1 passed")
    }
}
