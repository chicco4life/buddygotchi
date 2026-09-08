import Foundation
import XCTest
@testable import BoopCore

final class VoiceBankTests: XCTestCase {
    func testAllBanksParseAndPassWithLongPlaceholders() {
        XCTAssertEqual(VoiceBanks.banks.count, VoiceBanks.occasions.count * 2)
        for language in ["en", "ko"] {
            for key in VoiceBanks.occasions {
                for register in VoiceRegister.allCases {
                    let lines = VoiceBanks.lines(language: language, occasion: key, register: register)
                    XCTAssertGreaterThanOrEqual(Set(lines).count, 8)
                    var request = VoiceRequest(occasion: .cheer(Moment(kind: .hardWonPass, facts: ["attempts": "9999", "path": String(repeating: "파일", count: 100), "project": String(repeating: "project", count: 100)]), .dance, String(repeating: "test", count: 100)), agent: String(repeating: "agent", count: 100), language: language)
                    if key == "recapParagraph" { request = VoiceRequest(occasion: .recap(RecapFacts(turns: 17, tasks: 4)), language: language, byteCap: VoiceCap.paragraph.rawValue) }
                    for line in lines {
                        let rendered = VoiceBanks.render(line, request: request)
                        let filtered = VoiceFilter.check(rendered, language: language, byteCap: request.byteCap)
                        XCTAssertNotNil(filtered, "\(language)/\(key)/\(register): \(rendered)")
                        XCTAssertLessThanOrEqual(filtered?.utf8.count ?? 0, request.byteCap)
                    }
                }
            }
        }
    }
    func testFortyDrawsPerOccasionAndRegisterNeverRepeat() async {
        for language in ["en", "ko"] {
            for occasion in Self.occasions {
                for cheek in [0, 128, 255] {
                    let voice = Voice(localDay: { "2026-09-09" })
                    let request = VoiceRequest(occasion: occasion, traits: ["cheek": cheek], language: language)
                    var seen: Set<String> = []
                    var seasoned = 0
                    for draw in 1...40 {
                        let line = await voice.line(for: request)
                        let leads = VoiceBanks.leadIns[language]?[request.register.rawValue] ?? []
                        if leads.contains(where: { line.text.hasPrefix($0) }) { seasoned += 1 }
                        XCTAssertLessThanOrEqual(seasoned, draw * 4 / 10)
                        XCTAssertFalse(line.text.isEmpty, "\(language) \(occasion.key) \(cheek)")
                        XCTAssertTrue(seen.insert(line.text).inserted, "\(language) \(occasion.key) \(cheek): \(line.text)")
                    }
                }
            }
        }
    }
    static var occasions: [Occasion] {
        [.greet(1), .cheer(nil, .hop, nil), .cheer(nil, .cheer, nil), .cheer(nil, .dance, nil), .uhoh(.error, nil), .uhoh(.stuck, nil), .uhoh(.hungry, nil), .recap(RecapFacts(turns: 10))]
        + Moment.Kind.allCases.map { .cheer(Moment(kind: $0, facts: ["attempts": "10"]), .dance, "swift-test") }
    }
    func testSeedAndStoreExclusionsSurviveNewVoice() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let request = VoiceRequest(occasion: .greet(1))
        let a = Voice(localDay: { "2026-09-09" }), b = Voice(localDay: { "2026-09-09" })
        let first = await a.line(for: request), same = await b.line(for: request)
        XCTAssertEqual(first, same)
        var seen: Set<String> = []
        for _ in 0..<40 {
            let voice = Voice(store: store, localDay: { "2026-09-09" })
            let line = await voice.line(for: request)
            XCTAssertFalse(line.text.isEmpty); XCTAssertTrue(seen.insert(line.text).inserted)
        }
        let nextDay = Voice(store: store, localDay: { "2026-09-10" })
        let prior = try await store.voiceExclusions(localDay: "2026-09-10")
        XCTAssertEqual(prior.count, 20)
        let next = await nextDay.line(for: request)
        XCTAssertFalse(prior.contains(next.text))
    }
    func testRegisterBoundariesAndPromptPrivacy() {
        XCTAssertTrue(VoiceRuntimes.make(setting: "off") is NullRuntime)
        for (cheek, expected) in [(95, VoiceRegister.earnest), (96, .wry), (191, .wry), (192, .cheeky)] {
            XCTAssertEqual(VoiceRegister(cheek: cheek), expected)
        }
        let request = VoiceRequest(occasion: .cheer(Moment(kind: .hardWonPass, facts: ["raw": "SECRET", "goalKey": "OPAQUE", "attempts": "10"]), .dance, nil), profile: ["a", "b", "c", "FOURTH"])
        let prompt = VoicePrompt.make(request)
        for secret in ["SECRET", "OPAQUE", "FOURTH"] { XCTAssertFalse(prompt.contains(secret)) }
        XCTAssertTrue(prompt.contains("10"))
    }
}
