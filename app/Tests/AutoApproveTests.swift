import XCTest
@testable import BoopCore

final class AutoApproveTests: XCTestCase {
    func testStableCwdHashDoesNotUseRandomizedStringHash() {
        XCTAssertEqual(stableHashCwd("/tmp/boop"), stableHashCwd("/tmp/boop"))
        XCTAssertEqual(stableHashCwd(nil), "unknown")
        XCTAssertEqual(stableHashCwd(""), "unknown")
        XCTAssertEqual(stableHashCwd("/tmp/boop").count, 8)
    }
}
