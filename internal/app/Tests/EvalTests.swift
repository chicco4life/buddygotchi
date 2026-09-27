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
    /// word are read as the actions leave them.
    func testTheTestsFightBackWithAnAgreeableBrain() async throws {
        let brain = ScriptedBrain { state, _ in
            let now = state.components(separatedBy: "\nNOW (").last ?? ""
            func a(_ c: String) -> Answer { Answer(choice: c, probabilities: [c: 0.9]) }
            if now.contains("3 in a row") {
                return ["mood": a("grumpy"), "react": a("annoyed"), "word.feeling": a("again"), "word.about": a("tests")]
            }
            if now.contains("passed") {
                return ["mood": a("cheerful"), "react": a("proud"), "word.feeling": a("finally"), "word.about": a("tests")]
            }
            return ["mood": a(state.contains("MOOD\nGrumpy") ? "grumpy" : "cheerful"), "react": a("none"),
                    "word.feeling": a("none"), "word.about": a("none")]
        }
        let steering = try Steering(directory: RuntimeTests.steeringDir)
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("04-tests-fight-back.json"))
        let result = try await Eval(brain: brain, steering: steering).run(scenario)
        XCTAssertEqual(result.checks.count, 4)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(result.checks[2].word, "again")
        XCTAssertEqual(result.checks[2].mood, "grumpy")
        XCTAssertEqual(result.checks[3].mood, "cheerful", "16 minutes on, past the 10-minute limit")
    }

    /// A brain that stays quiet fails what should mumble, and the report
    /// says what was wanted and what came.
    func testAQuietBrainFailsAndTheReportSaysWhy() async throws {
        let steering = try Steering(directory: RuntimeTests.steeringDir)
        let scenario = try Scenario(file: Self.scenarios.appendingPathComponent("05-poke-streak.json"))
        let result = try await Eval(brain: ScriptedBrain(always: [:]), steering: steering).run(scenario)
        XCTAssertFalse(result.passed)
        let report = Eval.report([[result]])
        XCTAssertEqual(report.first, "FAIL  05-poke-streak.json  Poked again and again, Boop is annoyed")
        XCTAssertTrue(report[1].contains("wanted react annoyed, word none|nope|ugh; got react none, word none, mood cheerful"), report[1])
        XCTAssertEqual(report.last, "0/1 passed")
    }
}
