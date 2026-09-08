import Foundation
import XCTest
@testable import BoopCore

/// A completion is celebrated once.
final class CelebrateOnceTests: XCTestCase {

    func testNewWorkPreservesDoneWithoutReplayingIt() {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4_000)
        s = reduce(s, .sessionStarted(at: 0, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .activitySignal(at: 0, sessionId: "s1", source: "claude-code",
                                      signal: .startWorking, tool: "Bash", hint: "build"))
        s = reduce(s, .activitySignal(at: 40_000, sessionId: "s1", source: "claude-code",
                                      signal: .celebrate, tool: "Bash", hint: "build"))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        // A second session starts and finishes inside the hop window.
        s = reduce(s, .sessionStarted(at: 40_500, sessionId: "s2", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .activitySignal(at: 40_500, sessionId: "s2", source: "claude-code",
                                      signal: .startWorking, tool: "Read", hint: "/tmp/a"))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)

        s = reduce(s, .sessionEnded(at: 42_000, sessionId: "s2"))
        XCTAssertNotEqual(s.buddy.pet.state, .celebrate,
                          "the same completion celebrated twice")
    }

    func testAnOrdinaryCelebrationStillHappens() {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4_000)
        s = reduce(s, .sessionStarted(at: 0, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .activitySignal(at: 0, sessionId: "s1", source: "claude-code",
                                      signal: .startWorking, tool: "Bash", hint: "build"))
        s = reduce(s, .activitySignal(at: 40_000, sessionId: "s1", source: "claude-code",
                                      signal: .celebrate, tool: "Bash", hint: "build"))
        XCTAssertEqual(s.buddy.pet.state, .celebrate)
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 40_000)
    }

    /// A session Boop first meets at an approval must still get a start time,
    /// or it can never look stalled and its completion has no duration.
    func testApprovalAllowStampsAStartTime() {
        var s = InternalState.initial(staleMs: 600_000, celebrateDurationMs: 4_000)
        s = reduce(s, .sessionStarted(at: 0, sessionId: "s1", source: "claude-code", cwd: "/tmp"))
        s = reduce(s, .approvalArrived(at: 100, sessionId: "s1", requestId: "r1",
                                       tool: "Bash", hint: "npm i", sessionLabel: nil, source: "claude-code"))
        s = reduce(s, .approvalResolved(at: 200, sessionId: "s1", requestId: "r1", decision: .allow))
        XCTAssertEqual(s.sessions["s1"]?.workStartedAt, 200)

        s = reduce(s, .activitySignal(at: 30_200, sessionId: "s1", source: "claude-code",
                                      signal: .celebrate, tool: "Bash", hint: "npm i"))
        XCTAssertEqual(s.buddy.lastTaskDurationMs, 30_000, "completion had no measurable duration")
    }
}

/// A payload we can't fully understand must still produce a prompt. Failing to
/// decode one field used to fail the whole /hook/approve route with a 500,
/// which means the user never sees the card and the tool proceeds unreviewed.
final class ToolInputDecodingTests: XCTestCase {

    private func decode(_ json: String) -> HookEventBody? {
        try? JSONDecoder().decode(HookEventBody.self, from: Data(json.utf8))
    }

    /// Cursor's beforeMCPExecution sends tool_input as a JSON *string*.
    func testToolInputAsJSONStringIsAccepted() {
        let body = decode(#"{"tool_name":"search","tool_input":"{\"query\":\"hello\"}"}"#)
        XCTAssertNotNil(body, "a string tool_input threw and 500'd the route")
        XCTAssertEqual(body?.tool_input?.query, "hello")
    }

    func testToolInputAsNonJSONStringBecomesADescription() {
        let body = decode(#"{"tool_name":"x","tool_input":"just some text"}"#)
        XCTAssertNotNil(body)
        XCTAssertEqual(body?.tool_input?.description, "just some text")
    }

    /// A non-string under a name we read costs us that field, not the prompt.
    func testNonStringFieldDoesNotFailTheWholePayload() {
        let body = decode(#"{"tool_name":"x","tool_input":{"query":{"q":"x"},"command":"ls -la"}}"#)
        XCTAssertNotNil(body, "a structured field threw and 500'd the route")
        XCTAssertEqual(body?.tool_input?.command, "ls -la")
        XCTAssertNil(body?.tool_input?.query)
    }

    func testOrdinaryObjectStillDecodes() {
        let body = decode(#"{"tool_name":"Bash","tool_input":{"command":"git push"}}"#)
        XCTAssertEqual(body?.tool_input?.command, "git push")
    }
}
