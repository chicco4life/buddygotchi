import Foundation
import XCTest
@testable import BoopKit

/// EVALS.md §2: every pass of an eval run goes to its own file, under a
/// header line for each scenario's run, which `boopdev watch` prints.
final class EvalLogTests: XCTestCase {
    func testEachRunStartsWithAHeader() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("eval-log-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: log) }
        let steering = try String(contentsOf: EvalTests.root.appendingPathComponent("plan/steering.md"), encoding: .utf8)
        var eval = Eval(steering: steering, memory: EvalTests.root.appendingPathComponent("app/Tests/Fixtures/memory"))
        eval.debugLog = log
        let scenario = try Scenario(file: EvalTests.root.appendingPathComponent("app/Evals/scenarios/03-turn-failed.json"))
        _ = try await eval.run(scenario, mode: .calm, run: 2)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, #"{"eval":"calm  03-turn-failed.json  run 2"}"#)
        XCTAssertEqual(lines.first.flatMap(Eval.header), "calm  03-turn-failed.json  run 2")
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertNil(Eval.header(lines[1]), "a pass isn't a header")
        XCTAssertNil(Eval.header(#"{"aside":"tapped"}"#))
        // As boopdev watch prints it: the header, then the run's first pass
        // afresh, with the memory in full.
        let printer = DebugLog.Printer()
        XCTAssertEqual(printer.readable(lines[0]), "=== calm  03-turn-failed.json  run 2")
        let first = printer.readable(lines[1])
        _ = printer.readable(lines[0])
        XCTAssertEqual(printer.readable(lines[1]), first)
    }
}
