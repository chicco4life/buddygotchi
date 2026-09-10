import Foundation
import XCTest
@testable import BoopCore

final class VoiceFilterTests: XCTestCase {
    func testGuideOwnsStyleAndDisplayOwnsControls() {
        XCTAssertEqual(VoiceFilter.check("Hello again!", language: "en", byteCap: 63), "Hello again!")
        XCTAssertEqual(VoiceFilter.check("One thought. Another.", language: "en", byteCap: 63), "One thought. Another.")
        for line in ["hello\nthere", "hello\u{0}there", "hello\u{1b}there", "hello\u{200B}there"] {
            XCTAssertNil(VoiceFilter.check(line, language: "en", byteCap: 63))
        }
        XCTAssertNil(VoiceFilter.check("hello", language: "unknown", byteCap: 63))
    }
    func testEveryByteBoundaryPreservesCharacters() {
        for text in ["조용히 곁에 있어요", "Café again", "e\u{301}chos", "한글abc"] {
            for cap in 1...64 {
                if let result = VoiceFilter.check(text, language: "ko", byteCap: cap) {
                    XCTAssertLessThanOrEqual(result.utf8.count, cap)
                    XCTAssertTrue(text.precomposedStringWithCanonicalMapping.hasPrefix(result))
                    XCTAssertFalse(result.contains("�"))
                }
            }
        }
    }
}
