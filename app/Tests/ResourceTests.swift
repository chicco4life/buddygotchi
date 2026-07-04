import AppKit
import CoreText
import Foundation
import XCTest
@testable import Buddygotchi

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

    func testGeistSemiBoldRegistersAndResolves() {
        BuddyResources.registerFonts()
        XCTAssertNotNil(NSFont(name: BuddyTheme.geistSemiBoldPostScriptName, size: 12))
    }
}
