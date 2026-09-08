import Foundation
import XCTest
@testable import BoopCore

/// The heartbeat is the desktop→firmware wire contract, and the firmware reads
/// it into fixed `char[N]` buffers with `strncpy` — which counts BYTES. Bounding
/// these fields by Swift Characters let a multi-byte one straddle the buffer
/// edge, so the device kept a dangling lead byte.
///
/// Observed on hardware before the fix: a prompt hint of `"x"*18 + "🐛"*12`
/// (66 bytes) left the device holding 63 bytes ending mid-emoji, which made the
/// device's own `state` reply invalid UTF-8 and crashed buddyctl — so the HIL
/// suite could not even read the device while such a prompt was up.
final class HeartbeatTruncationTests: XCTestCase {

    func testRenderStateUsesIsolatedDefaults() throws {
        let suiteName = "BoopTests.heartbeat.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("cat", forKey: DefaultsKey.buddySpecies)
        defaults.set(false, forKey: DefaultsKey.soundsEnabled)
        let frame = renderState(from: .initial, defaults: defaults)
        XCTAssertEqual(frame.species, "cat")
        XCTAssertEqual(frame.mute, true)
        let data = try JSONEncoder().encode(BuddyState.initial)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((body["creature"] as? [String: Any])?["state"] as? String, "asleep")
        XCTAssertNotNil(body["activeSessions"])
    }

    func testPrefixByBytesNeverSplitsACharacter() {
        let s = String(repeating: "x", count: 18) + String(repeating: "🐛", count: 12)
        let cut = s.prefix(utf8Bytes: 63)
        XCTAssertLessThanOrEqual(cut.utf8.count, 63)
        // The real assertion: it round-trips. A split scalar would not.
        XCTAssertEqual(String(data: Data(cut.utf8), encoding: .utf8), cut)
        XCTAssertTrue(s.hasPrefix(cut))
    }

    func testPrefixByBytesKeepsWholeCharactersForCJK() {
        let s = String(repeating: "修", count: 40)     // 3 bytes each
        let cut = s.prefix(utf8Bytes: 23)
        XCTAssertEqual(cut.count, 7)                  // 7*3 = 21 <= 23
        XCTAssertEqual(cut.utf8.count, 21)
        XCTAssertEqual(String(data: Data(cut.utf8), encoding: .utf8), cut)
    }

    func testPrefixByBytesLeavesShortAsciiUntouched() {
        XCTAssertEqual("git push --force".prefix(utf8Bytes: 63), "git push --force")
        XCTAssertEqual("".prefix(utf8Bytes: 10), "")
    }

    func testPrefixByBytesHandlesAGraphemeWiderThanTheBudget() {
        // A family emoji is a single Character of ~25 bytes; with a 10-byte
        // budget the only valid answer is to emit nothing rather than a shard.
        let family = "👩‍👩‍👧‍👦"
        let cut = family.prefix(utf8Bytes: 10)
        XCTAssertEqual(cut, "")
    }

    // MARK: Whole-frame invariants

    // Throws rather than returning a placeholder: the shim's XCTFail is
    // `Never` while real XCTest's is `Void`, so a `return` after it is
    // unreachable under one toolchain and required by the other.
    private func heartbeat(_ mutate: (inout BuddyState) -> Void) throws -> Data {
        var state = BuddyState.initial
        mutate(&state)
        return try XCTUnwrap(renderStateData(from: state), "heartbeat failed to encode")
    }

    func testEmojiHintProducesValidUTF8OnTheWire() throws {
        let data = try heartbeat { state in
            state.pet = Pet(state: .attention, species: "blob")
            state.prompt = Prompt(
                id: "req_1",
                tool: "Bash",
                hint: String(repeating: "x", count: 18) + String(repeating: "🐛", count: 12),
                arrivedAt: 0,
                sessionLabel: nil,
                source: "claude-code",
                isApproval: true,
                activityKind: .shell
            )
        }
        XCTAssertNotNil(String(data: data, encoding: .utf8), "heartbeat is not valid UTF-8")

        // And the field the firmware will strncpy must already fit its buffer.
        let obj = (try? JSONSerialization.jsonObject(with: data.dropLast())) as? [String: Any]
        let hint = (obj?["promptHint"] as? String) ?? ""
        XCTAssertLessThanOrEqual(hint.utf8.count, 63, "promptHint overruns char promptHint[64]")
    }

    /// An oversize frame is not truncated by the firmware — it is dropped
    /// whole, and the 10s keepalive re-sends the same oversize state, so the
    /// device stops hearing from a working Mac and naps after 30s.
    func testOversizeStateShedsExtrasRatherThanBlowingTheFrame() throws {
        let data = try heartbeat { state in
            state.pet = Pet(state: .busy, species: "blob")
            state.msg = String(repeating: "修", count: 40)
            state.entries = (0..<6).map { _ in String(repeating: "修", count: 200) }
        }
        XCTAssertLessThanOrEqual(data.count, 1536, "frame exceeds the firmware's line buffer budget")
        XCTAssertNotNil(String(data: data, encoding: .utf8))
    }

    /// Personality and agent-overlay fields ride the same frame; worst-case
    /// (all present at max width, on top of unbounded entries) must still
    /// shed down under the budget, and the overlay must survive the shed.
    func testPersonalityFieldsFitTheFrame() throws {
        let data = try heartbeat { state in
            state.pet = Pet(state: .busy, species: "blob")
            state.msg = String(repeating: "修", count: 40)
            state.entries = (0..<6).map { _ in String(repeating: "修", count: 200) }
            state.greetUntil = 1
            state.greetLevel = 2
            state.mood = .surprised
            state.effortTier = .grinding
            state.agentOverlay = AgentOverlay(
                agentId: "claude-code",
                color: "lavender",
                emotion: "dramatic-collapse",
                intensity: "medium",
                motion: "look-at-user",
                say: String(repeating: "x", count: 38) + "🐛",
                delivery: "deadpan",
                until: 2
            )
        }
        XCTAssertLessThanOrEqual(data.count, 1536, "frame exceeds the firmware's line buffer budget")
        XCTAssertNotNil(String(data: data, encoding: .utf8))

        let obj = (try? JSONSerialization.jsonObject(with: data.dropLast())) as? [String: Any]
        XCTAssertEqual(obj?["agentEmotion"] as? String, "dramatic-collapse")
        XCTAssertEqual(obj?["effort"] as? String, "grinding")
        XCTAssertEqual(obj?["greet"] as? Bool, true)
        let say = (obj?["agentSay"] as? String) ?? ""
        XCTAssertLessThanOrEqual(say.utf8.count, 40)
    }
}
