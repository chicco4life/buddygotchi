import Foundation
import XCTest
@testable import BoopKit

/// The harness eval suite (plan/EVALS.md) passes with the rules classifier
/// and no writer, and the runner checks each step's whole window of passes.
final class EvalTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..")
        .standardizedFileURL
    static let scenarios = root.appendingPathComponent("app/Evals/scenarios")

    func runner() throws -> Eval {
        let steering = try String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        return Eval(steering: steering, memory: EvalTests.root.appendingPathComponent("app/Tests/Fixtures/memory"))
    }

    func testEveryScenarioPasses() async throws {
        let scenarios = try Scenario.load(directory: EvalTests.scenarios)
        XCTAssertFalse(scenarios.isEmpty)
        let eval = try runner()
        for scenario in scenarios {
            let result = try await eval.run(scenario)
            XCTAssertTrue(result.passed, "\(scenario.file)\n" + Eval.diff(result))
        }
    }

    func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    func run(_ json: String) async throws -> Eval.Result {
        let url = try write(json)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await runner().run(Scenario(file: url))
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
                       [["agent started → nothing"], ["agent finished → react(feeling: proud, voice: mumble)"]])
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
