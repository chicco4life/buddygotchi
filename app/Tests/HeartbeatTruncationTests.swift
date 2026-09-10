import Foundation
import XCTest
@testable import BoopCore

final class HeartbeatTruncationTests: XCTestCase {
    private func object(_ frame: RenderState) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any])
    }

    func testEveryTextCapWithKoreanAndEmoji() throws {
        for glyph in ["한", "🐛", "👩‍👩‍👧‍👦"] {
            let text = String(repeating: glyph, count: 100)
            var f = RenderState(state: .needsYou, bubble: text, t: 42)
            f.card = .needsYou(id: text, tool: text, gloss: text, stakes: .careful, n: 1, of: 2, approval: true)
            f.snap = .init(name: text)
            f.cosmetic = .init(skin: text, accessory: text, silhouette: text)
            var o = try object(f)
            for (container, fields) in [("card", [("id", 23), ("tool", 23), ("gloss", 63)]), ("snap", [("name", 23)]), ("cosmetic", [("skin", 15), ("accessory", 15), ("silhouette", 15)])] {
                let nested = try XCTUnwrap(o[container] as? [String: Any])
                for (key, cap) in fields { XCTAssertEqual(nested[key] as? String, text.prefix(utf8Bytes: cap)) }
            }
            XCTAssertEqual(o["bubble"] as? String, text.prefix(utf8Bytes: 63))
            XCTAssertNil(o["giftLine"])
            f.card = .system(kind: .pair, text: text)
            o = try object(f)
            XCTAssertEqual((o["card"] as? [String: Any])?["text"] as? String, text.prefix(utf8Bytes: 63))
            o = try object(f)
            XCTAssertNil(o["agent"])
        }
        for cap in [7, 15, 23, 40, 63] {
            let exact = String(repeating: "a", count: cap - 7) + "한🐛"
            XCTAssertEqual((exact + "🐛").prefix(utf8Bytes: cap), exact)
        }
    }

    func testOptionalKeysAbsentAndSnapshotPresentInMapper() throws {
        let bare = try object(RenderState(state: .asleep, t: 0))
        for key in ["effort", "cheer", "uhoh", "overlay", "greetLevel", "dotAlert", "card", "bubble", "giftLine", "posture", "cosmetic", "snap", "agent"] {
            XCTAssertNil(bare[key], key)
        }
        let suite = "BoopTests.wire.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("테스트", forKey: DefaultsKey.buddyName)
        defaults.set(false, forKey: DefaultsKey.soundsEnabled)
        let mapped = renderState(from: .initial, defaults: defaults, now: 1234)
        XCTAssertEqual(mapped.v, 2)
        XCTAssertEqual(mapped.t, 1234)
        XCTAssertEqual(mapped.mute, 0)
        XCTAssertEqual(mapped.snap?.name, "테스트")
        XCTAssertEqual(mapped.snap?.growth.level, 1)
        XCTAssertEqual(mapped.snap?.growth.xpNext, 150)
        XCTAssertEqual(mapped.cosmetic?.skin, "default")
    }

    func testAgentNeverCoexistsWithEitherCard() throws {
        var frame = RenderState(state: .needsYou, t: 0)
        for card in [RenderState.Card.needsYou(id: "1", tool: "Bash", gloss: "test", stakes: .fine, n: 1, of: 1, approval: true), .system(kind: .update, text: "Updating")] {
            frame.card = card
            let o = try object(frame)
            XCTAssertNotNil(o["card"])
            XCTAssertNil(o["agent"])
        }
    }

    func testStateParametersAndRanges() throws {
        for state in CreatureState.allCases {
            var buddy = BuddyState.initial
            buddy.creature.state = state
            buddy.creature.effort = .hard
            buddy.creature.cheer = .dance
            buddy.creature.uhoh = .error
            buddy.creature.dots = 100
            buddy.creature.dotAlert = 8
            let o = try object(renderState(from: buddy, now: 0))
            XCTAssertEqual(o["state"] as? String, state.rawValue)
            XCTAssertEqual(o["effort"] as? String, state == .working ? "hard" : nil)
            XCTAssertEqual(o["cheer"] as? String, state == .done ? "dance" : nil)
            XCTAssertEqual(o["uhoh"] as? String, state == .uhoh ? "error" : nil)
            XCTAssertEqual(o["dots"] as? Int, 5)
            XCTAssertNil(o["dotAlert"])
        }
    }

    func testFrameCapShedsInOrderIncludingEscapedText() throws {
        // Control bytes are legal JSON strings and expand to six bytes each.
        let text = String(repeating: "\u{01}", count: 100)
        var frame = RenderState(state: .needsYou, bubble: text.prefix(utf8Bytes: 63), t: Int.max)
        frame.card = .needsYou(id: text, tool: text, gloss: text, stakes: .careful, n: Int.max, of: Int.max, approval: true)
        frame.overlay = .greet
        frame.greetLevel = 3
        frame.posture = .travel
        frame.snap = .init(name: text)
        frame.cosmetic = .init(skin: text, accessory: text, silhouette: text)
        var sawSnapOnly = false
        var sawCosmetic = false
        for length in 0...63 {
            frame.bubble = String(repeating: "\u{01}", count: length)
            let full = try JSONEncoder().encode(frame)
            let data = try XCTUnwrap(renderStateData(from: frame))
            XCTAssertLessThanOrEqual(data.count, maxHeartbeatBytes)
            XCTAssertEqual(data.last, 10)
            let o = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(o["bubble"] as? String, frame.bubble, "The remaining text fits after shedding optional fields")
            if full.count + 1 <= maxHeartbeatBytes { XCTAssertNotNil(o["snap"]); continue }
            XCTAssertNil(o["snap"])
            var withoutSnap = frame
            withoutSnap.snap = nil
            if try JSONEncoder().encode(withoutSnap).count + 1 <= maxHeartbeatBytes {
                XCTAssertNotNil(o["cosmetic"])
                sawSnapOnly = true
            } else {
                XCTAssertNil(o["cosmetic"])
                sawCosmetic = true

            }
        }
        XCTAssertTrue(sawSnapOnly)
        XCTAssertTrue(sawCosmetic)
    }
}
