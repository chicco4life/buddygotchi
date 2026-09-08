import AppKit
import CoreText
import Foundation
import XCTest
@testable import BoopCore

final class ResourceTests: XCTestCase {
    func testModuleBundleContainsFontAndSoundResources() {
        XCTAssertNotNil(
            BuddyResources.moduleResourceURL(
                forResource: "Geist-Regular",
                withExtension: "otf",
                subdirectory: "Fonts"
            )
        )
        XCTAssertNotNil(
            BuddyResources.moduleResourceURL(
                forResource: "attention",
                withExtension: "caf",
                subdirectory: "Sounds"
            )
        )
    }

    /// Pins the chirp grammar to the shipped assets rather than to
    /// make-chirps.py: completion is one note, attention is two, so the
    /// completion sound has to be the shorter of the pair.
    func testCompletionChirpIsShorterThanAttentionChirp() throws {
        let celebrate = try XCTUnwrap(BuddyResources.soundURL("celebrate"))
        let attention = try XCTUnwrap(BuddyResources.soundURL("attention"))

        let celebrateSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: celebrate.path)[.size] as? Int)
        let attentionSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: attention.path)[.size] as? Int)

        // Same format and sample rate, so bytes stand in for duration.
        XCTAssertLessThan(celebrateSize, attentionSize)
    }

    func testGeistSemiBoldRegistersAndResolves() {
        BuddyResources.registerFonts()
        XCTAssertNotNil(NSFont(name: BuddyTheme.geistSemiBoldPostScriptName, size: 12))
    }
}
