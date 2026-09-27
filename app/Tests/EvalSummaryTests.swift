import Foundation
import XCTest
@testable import BoopKit

/// VERIFICATION.md L5: what `boopdev eval --real` sums up over the real
/// brains' passes, and when they hold.
final class EvalSummaryTests: XCTestCase {
    /// A step that scripts a stage (a crash, a refusal, words) tests the
    /// harness, not the brains, so its passes stay out of the summary.
    func testScriptedStepsAreLeftOut() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).json")
        try Data("""
            {"name": "x", "steps": [
              {"input": {"at": "0m", "event": "turn started"}, "expect": []},
              {"input": {"at": "1m", "event": "turn finished"}, "classifier": {"error": "model crashed"}, "expect": []},
              {"input": {"at": "2m", "event": "turn started"}, "classifier": "refused", "expect": []},
              {"input": {"at": "3m", "event": "talk", "words": "hi"}, "writer": {"error": "boom"}, "expect": []},
              {"input": {"at": "4m", "event": "talk", "words": "hello"}, "expect": []}]}
            """.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let steering = try String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        let eval = Eval(steering: steering, memory: EvalTests.root.appendingPathComponent("app/Tests/Fixtures/memory"))
        let result = try await eval.run(Scenario(file: url), mode: .chatty)
        XCTAssertEqual(result.brainPasses.map(\.input.kind), [.agentStarted, .said])
        let summary = Eval.Summary(result.brainPasses)
        XCTAssertTrue(summary.holds, summary.lines.joined(separator: "\n"))
        XCTAssertEqual(summary.lines.first, "--- the real brains, over 2 passes")
    }

    /// L5's pass: Stage 1 answered every pass it didn't refuse, actions
    /// dropped under 5% of the calls handed to them, and every kind's p95
    /// is under its deadline. Refusals are reported, not failed.
    func testWhenTheRealBrainsHold() {
        func pass(latency: Int = 100, dropped: String? = nil, ran: [(ToolCall, ActionOutcome)] = []) -> Harness.Record {
            var r = Harness.Record(input: input(.said, words: "hi"), classifier: "c", writer: "w", window: 1)
            r.latencyMs = latency
            r.dropped = dropped
            r.ran = ran.map { (call: $0.0, outcome: $0.1) }
            return r
        }
        let done = pass(ran: [(react("happy"), .done(""))])
        XCTAssertTrue(Eval.Summary([done, pass(dropped: "refused: guardrail")]).holds, "a refusal is reported, not failed")
        XCTAssertFalse(Eval.Summary([done, pass(dropped: "off the menu: hug")]).holds)
        XCTAssertFalse(Eval.Summary([done, pass(dropped: "model crashed")]).holds)
        XCTAssertEqual(Eval.Summary.maxDropped, 0.05)
        let actionDropped = pass(ran: [(react("happy"), .dropped("muted"))])
        XCTAssertFalse(Eval.Summary(Array(repeating: done, count: 19) + [actionDropped]).holds, "1 in 20 is 5%")
        XCTAssertTrue(Eval.Summary(Array(repeating: done, count: 20) + [actionDropped]).holds, "1 in 21 is under")
        XCTAssertTrue(Eval.Summary([pass(ran: [(remember("today"), .dropped("nothing was written"))])]).holds,
                      "a call nothing was written for isn't the action's drop")
        XCTAssertEqual(Input.Kind.said.deadlineMs, 4000)
        XCTAssertTrue(Eval.Summary([pass(latency: 3999)]).holds)
        XCTAssertFalse(Eval.Summary([pass(latency: 4000)]).holds, "p95 must be under the deadline")
    }
}
