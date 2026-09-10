import Foundation
import XCTest
@testable import BoopCore

final class VoiceBankTests: XCTestCase {
    func testOnlyShareCardsRetainAuthoredBanks() {
        XCTAssertEqual(VoiceBanks.occasions, ["share"])
        for language in ["en", "ko"] {
            for register in VoiceRegister.allCases {
                XCTAssertFalse(VoiceBanks.lines(language: language, occasion: "share", register: register).isEmpty)
            }
        }
    }
    func testPromptContainsGuideAndBoundedContext() {
        let request = VoiceRequest(occasion: .periodic, profile: ["a", "b", "c", "FOURTH"], state: .working, sessionCount: 2, effort: .hard)
        let prompt = VoicePrompt.make(request, guide: "Use a gentle nautical voice.")
        XCTAssertTrue(prompt.contains("Use a gentle nautical voice."))
        XCTAssertTrue(prompt.contains("periodic"))
        XCTAssertTrue(prompt.contains("working"))
        XCTAssertFalse(prompt.contains("FOURTH"))
        XCTAssertTrue(VoiceRuntimes.make(setting: "off") is NullRuntime)
    }
}
