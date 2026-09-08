import XCTest
@testable import BoopCore

/// The approval request id is a wire value, not just a dictionary key.
///
/// The firmware stores it in a fixed `char promptId[N]`, echoes it back with
/// the user's decision, and the engine matches that reply by exact string
/// equality. So an id the device can't hold verbatim is an approval that can
/// never be resolved from the device — and it fails silently, because the
/// truncated reply simply matches no pending entry.
///
/// That shipped: ids were "<session_id>_<12 random>", and Claude Code's
/// session_id is a 36-char UUID, so real ids ran 49 chars into a 40-byte
/// buffer. Pressing the crown showed "yes!" on the device forever while the
/// agent stayed blocked waiting on a hook that never returned.
final class RequestIdTests: XCTestCase {

    /// The buffer that shipped when this bug was found. The device side has
    /// since been widened, but ids must stay under the OLD bound so a desktop
    /// update alone fixes already-flashed hardware — nobody should have to
    /// reflash a pet to make its button work.
    private let legacyDeviceCapacity = 39   // char promptId[40], minus the NUL

    func testFitsLegacyDeviceBufferForUUIDSession() {
        // A real Claude Code session_id.
        let id = makeRequestId(sessionId: "0d4f8e2a-9c31-4b7d-8e6f-1a2b3c4d5e6f")
        XCTAssertLessThanOrEqual(id.count, legacyDeviceCapacity,
            "id '\(id)' is \(id.count) chars and would be truncated on device")
    }

    /// Cursor and Codex derive ids differently, and a cwd-hashed fallback is
    /// longer than it looks. Anything that reaches the buffer must fit.
    func testFitsForEveryPlausibleSessionShape() {
        let sessions = [
            "0d4f8e2a-9c31-4b7d-8e6f-1a2b3c4d5e6f",          // Claude Code UUID
            "claude-code_a1b2c3d4",                            // cwd-hash fallback
            "cursor_00000000",
            "",                                                // absent session
            String(repeating: "x", count: 200),                // pathological
        ]
        for session in sessions {
            let id = makeRequestId(sessionId: session)
            XCTAssertLessThanOrEqual(id.count, legacyDeviceCapacity,
                "session '\(session.prefix(20))...' produced a \(id.count)-char id")
        }
    }

    /// Truncation only bites because ids share a long prefix — two ids that
    /// differ solely past the cut collapse into one on the device. The random
    /// suffix has to survive, so keep it late and keep ids distinct.
    func testIdsAreUniqueWithinOneSession() {
        let session = "0d4f8e2a-9c31-4b7d-8e6f-1a2b3c4d5e6f"
        let ids = Set((0..<200).map { _ in makeRequestId(sessionId: session) })
        XCTAssertEqual(ids.count, 200, "request ids collided within a session")
    }

    /// Two concurrent sessions must not produce ids that are equal after the
    /// device truncates them, or approving one resolves the other.
    func testIdsStayDistinctAcrossSessionsAfterTruncation() {
        let a = makeRequestId(sessionId: "0d4f8e2a-9c31-4b7d-8e6f-1a2b3c4d5e6f")
        let b = makeRequestId(sessionId: "0d4f8e2a-9c31-4b7d-8e6f-999999999999")
        XCTAssertNotEqual(String(a.prefix(legacyDeviceCapacity)),
                          String(b.prefix(legacyDeviceCapacity)))
    }
}
