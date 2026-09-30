import Beacon
import Foundation
import XCTest
@testable import BrainKit

/// Beacon, the brain kit's second example (plan/kit/BRAIN-KIT.md §11): the
/// worked example's run, pinned, so the spec quotes what it does. A port
/// of the kit runs the same timeline and must write the same log and
/// prompts (§12).
final class BeaconTests: XCTestCase {
    static let steering = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../examples/Beacon/steering")

    /// The prompt from HISTORY on.
    func tail(_ prompt: String) -> String {
        String(prompt[prompt.range(of: "HISTORY (")!.lowerBound...])
    }

    func testTheWorkedExample() async throws {
        let run = try await Beacon.demo(steering: Self.steering)
        XCTAssertEqual(run.prompts.count, 6, "two failures, a press, the third, a press, the pass")
        XCTAssertEqual(run.log[8...12].joined(separator: "\n"), #"""
            {"seq":9,"at":1791986940000,"source":"ci","kind":"build_failed","data":{"branch":"main","run":814}}
            {"seq":10,"at":1791986940000,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":9,"message":"Beacon flashed red on its own.","ok":true}}
            {"seq":11,"at":1791986940000,"source":"self","kind":"pass","data":{"answers":{"play":{"choice":"wobble","p":{"wobble":1}},"tone":{"choice":"worried","p":{"worried":1}}},"brain":"scripted","dropped":null,"for":9,"ms":0}}
            {"seq":12,"at":1791986940000,"source":"self","kind":"did","data":{"action":"tone","by":"brain","for":9,"from":"calm","latency_ms":0,"message":"Beacon went from calm to worried.","ok":true,"to":"worried"}}
            {"seq":13,"at":1791986940000,"source":"self","kind":"did","data":{"action":"play","by":"brain","for":9,"latency_ms":0,"message":"Beacon wobbled.","ok":true,"open":true}}
            """#)
        XCTAssertEqual(run.log[15], #"{"seq":16,"at":1791986948000,"source":"self","kind":"ended","data":{"action":"play","by":"brain","for":13,"outcome":"done"}}"#)

        XCTAssertEqual(tail(run.prompts[3].prompt), """
            HISTORY (oldest first; indented lines add to the line above)
            8 min ago: The build on main failed.
              Beacon flashed red on its own.
            4 min ago: The build on main failed again, 2 in a row.
              Beacon flashed red on its own.
            3 min ago: You pressed the button.

            NOW (14:09, Wednesday)
            The build on main failed again, 3 in a row.
            Beacon flashed red on its own.
            """)
        XCTAssertTrue(run.prompts[3].prompt.contains("TONE\nCalm."))
        XCTAssertEqual(tail(run.prompts[4].prompt), """
            HISTORY (oldest first; indented lines add to the line above)
            8 min ago: The build on main failed.
              Beacon flashed red on its own.
            4 min ago: The build on main failed again, 2 in a row.
              Beacon flashed red on its own.
            3 min ago: You pressed the button.
            just now: The build on main failed again, 3 in a row.
              Beacon flashed red on its own.
              Beacon went from calm to worried.
              Beacon wobbled. (in progress)
            Beacon has been worried for under a minute.

            NOW (14:09, Wednesday)
            You pressed the button.
            Beacon did nothing on its own.
            """, "the wobble in progress, so the brain plays nothing")
        XCTAssertTrue(run.prompts[4].prompt.contains("TONE\nWorried."), "the tone's section follows its value")
        XCTAssertEqual(tail(run.prompts[5].prompt), """
            HISTORY (oldest first; indented lines add to the line above)
            19 min ago: The build on main failed.
              Beacon flashed red on its own.
            15 min ago: The build on main failed again, 2 in a row.
              Beacon flashed red on its own.
            14 min ago: You pressed the button.
            11 min ago: The build on main failed again, 3 in a row.
              Beacon flashed red on its own.
              Beacon went from calm to worried.
              Beacon wobbled.
            10 min ago: You pressed the button.
            Beacon has been worried for 11 min.

            NOW (14:20, Wednesday)
            The build on main passed after 3 failures.
            Beacon flashed green on its own.
            """, "reaching back to the red streak's start")
        XCTAssertTrue(run.log.last!.contains(#""kind":"ended""#) && run.log[20].contains(#""message":"Beacon cheered.""#))
        XCTAssertTrue(run.log[19].contains(#""to":"calm""#), "back to calm")
    }

    /// §3.2, §10: Beacon's file registers a template, and an hour of red
    /// is news of its own, once.
    func testDeploysAndAnHourOfRed() throws {
        final class Clock: @unchecked Sendable { var now = Beacon.start }
        let clock = Clock()
        let queue = DispatchQueue(label: "beacon.test")
        let beacon = try Beacon(brain: nil, log: Log(), steering: Self.steering, clock: .init(now: { clock.now }), queue: queue,
                                timeZone: TimeZone(identifier: "UTC")!)
        let h = beacon.harness
        let deploy = queue.sync { h.emit(source: "ci", kind: "deploy", data: ["who": "Ana", "service": "api"]) }
        XCTAssertEqual(queue.sync { h.line(deploy.seq)?.text }, "Ana deployed api.")
        queue.sync { _ = h.emit(source: "ci", kind: "build_failed", data: ["branch": "main"]) }
        XCTAssertEqual(beacon.light.played.map(\.name), ["flash"], "the rule flashed, at once")
        clock.now += 3_600_000
        queue.sync { h.tick(); h.tick() }
        let red = queue.sync { h.log.events.filter { $0.kind == "still_red" } }
        XCTAssertEqual(red.count, 1)
        XCTAssertEqual(queue.sync { h.line(red[0].seq)?.text }, "The build has been red for an hour.")
    }
}
