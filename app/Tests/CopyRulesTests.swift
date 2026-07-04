import Foundation
import XCTest
@testable import Buddygotchi

final class CopyRulesTests: XCTestCase {
    func testBuddyCopyFollowsBrandLaw() throws {
        let bannedWords = [
            "revolutionary",
            "supercharge",
            "ai-powered",
            "productivity",
            "game-changer",
            "premium",
        ]

        for copy in BuddyCopy.manifest {
            XCTAssertFalse(copy.contains("!"), "Exclamation mark in copy: \(copy)")
            XCTAssertFalse(copy.contains("..."), "Use a real ellipsis in copy: \(copy)")

            let lowercased = copy.lowercased()
            for word in bannedWords {
                XCTAssertFalse(lowercased.contains(word), "Banned word '\(word)' in copy: \(copy)")
            }

            for word in uppercaseWords(in: copy) where word.count > 4 {
                XCTAssertTrue(
                    BuddyCopy.allowedUppercaseWords.contains(word),
                    "Unexpected all-caps word '\(word)' in copy: \(copy)"
                )
            }
        }
    }

    private func uppercaseWords(in copy: String) -> [String] {
        copy
            .split { !$0.isLetter }
            .map(String.init)
            .filter { word in
                word.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
                    && word == word.uppercased()
            }
    }
}
