import Foundation
import XCTest
@testable import BoopCore

final class VoiceFilterTests: XCTestCase {
    func testEveryBannedPatternRejectsWithCaseSpacingAndUnsafeSuffix() {
        for language in ["en", "ko"] {
            for pattern in VoiceFilter.banned {
                for variant in [pattern, pattern.uppercased(), pattern.replacingOccurrences(of: " ", with: "  ")] {
                    XCTAssertNil(VoiceFilter.check("a safe start " + variant, language: language, byteCap: 5), variant)
                }
            }
        }
    }
    func testEveryByteBoundaryPreservesCharacters() {
        for text in ["조용히 곁에 있어요", "café again", "e\u{301}chos", "한글abc"] {
            for cap in 1...64 {
                if let result = VoiceFilter.check(text, language: "ko", byteCap: cap) {
                    XCTAssertLessThanOrEqual(result.utf8.count, cap)
                    XCTAssertTrue(text.precomposedStringWithCompatibilityMapping.lowercased().hasPrefix(result))
                    XCTAssertFalse(result.contains("�"))
                }
            }
        }
    }
    func testEmojiPunctuationAndDeviceControls() {
        for emoji in ["😀", "♥", "☀️", "1️⃣", "🇰🇷", "👩‍💻"] {
            XCTAssertNil(VoiceFilter.check("hello " + emoji, language: "en", byteCap: 63))
        }
        XCTAssertNil(VoiceFilter.check("hello!", language: "en", byteCap: 63))
        XCTAssertEqual(VoiceFilter.check("dance!", language: "en", byteCap: 40, allowExclamation: true), "dance!")
        XCTAssertNil(VoiceFilter.check("hello\nthere", language: "en", byteCap: 63))
        XCTAssertNil(VoiceFilter.check("you\u{200B} always", language: "en", byteCap: 63))
        XCTAssertNil(VoiceFilter.check("one line. another line", language: "en", byteCap: 63))
        XCTAssertNotNil(VoiceFilter.check("one line. another line.", language: "en", byteCap: 240))
        XCTAssertNil(VoiceFilter.check("you—always", language: "en", byteCap: 63))
        XCTAssertNotNil(VoiceFilter.check("a different color at last", language: "en", byteCap: 40))
        XCTAssertEqual(VoiceFilter.check("10 tries", language: "en", byteCap: 40), "10 tries")
    }
}
