import Foundation
import XCTest
@testable import BoopKit

/// BEHAVIORS.md §3.3: you yelled if the mic heard you at −18 dBFS or louder
/// for 300 ms or more in all.
final class YellMeterTests: XCTestCase {
    func level(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer(YellMeter.dbfs)
    }

    /// A sine wave's RMS is its peak ÷ √2: a full-scale one is about −3 dBFS.
    func testLevelIsRMSAgainstFullScale() {
        let sine = (0..<480).map { Float(sin(Double($0) * 2 * .pi / 48)) }
        XCTAssertEqual(Double(level(sine)), -3.01, accuracy: 0.05)
        XCTAssertEqual(Double(level(sine.map { $0 * 0.1 })), -23.01, accuracy: 0.05)
        XCTAssertEqual(level([Float](repeating: 0, count: 480)), -.infinity)
        XCTAssertEqual(level([]), -.infinity)
    }

    func testThreeHundredLoudMillisecondsInAllIsAYell() {
        var meter = YellMeter()
        for _ in 0..<14 { meter.add(dbfs: -12, ms: 21.3) }  // 298 ms
        XCTAssertFalse(meter.yelled)
        meter.add(dbfs: -40, ms: 500)  // quiet stretches don't count, or undo it
        XCTAssertFalse(meter.yelled)
        meter.add(dbfs: -18, ms: 2)  // exactly −18 counts
        XCTAssertTrue(meter.yelled)
    }

    func testTalkingNormallyIsntAYell() {
        var meter = YellMeter()
        for _ in 0..<1000 { meter.add(dbfs: -18.5, ms: 21.3) }  // 21 s just under
        XCTAssertFalse(meter.yelled)
        XCTAssertEqual(meter.loudMs, 0)
    }
}
