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

        for copy in reflectedCopyStrings(in: BuddyCopy.shared) {
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

    func testInlineViewTextLiteralRatchet() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsRoot = sourceRoot.appendingPathComponent("Buddygotchi/Views", isDirectory: true)
        let notificationManager = sourceRoot.appendingPathComponent("Buddygotchi/Notifications/NotificationManager.swift")
        let appDelegate = sourceRoot.appendingPathComponent("Buddygotchi/App/AppDelegate.swift")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: viewsRoot.path),
            "Source files are not available for the inline copy ratchet."
        )

        var files = swiftFiles(under: viewsRoot)
        for file in [notificationManager, appDelegate] where FileManager.default.fileExists(atPath: file.path) {
            files.append(file)
        }

        let regex = try NSRegularExpression(pattern: #"Text\("[A-Za-z]"#)
        let count = try files.reduce(0) { total, file in
            let source = try String(contentsOf: file)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            return total + regex.numberOfMatches(in: source, range: range)
        }

        // Delete this test when the baseline reaches 0.
        let baseline = 0
        XCTAssertFalse(count > baseline, "Inline Text string literal count grew from \(baseline) to \(count).")
    }

    private func reflectedCopyStrings(in value: Any) -> [String] {
        var strings: [String] = []
        collectCopyStrings(in: value, into: &strings)
        return strings
    }

    private func collectCopyStrings(in value: Any, into strings: inout [String]) {
        if let string = value as? String {
            strings.append(string)
            return
        }

        for child in Mirror(reflecting: value).children {
            collectCopyStrings(in: child.value, into: &strings)
        }
    }

    private func swiftFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
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
