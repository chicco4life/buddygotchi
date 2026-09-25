import XCTest
@testable import BoopKit

final class BoopVersionTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(BoopVersion.current.isEmpty)
    }
}
