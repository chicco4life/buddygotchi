import Foundation
import XCTest
@testable import BoopCore

final class GlanceTests: XCTestCase {
    private func finish(_ s: InternalState, _ id: String, _ at: Double) -> InternalState {
        let started = reduce(s, .turnStarted(at: at-10, sessionId: id, source: "codex"))
        return reduce(started, .turnEnded(at: at, sessionId: id, source: "codex", outcome: .completed))
    }
    func testShortTurnDuplicateFailureAndRemoval() {
        var s = finish(.test(), "a", NOW)
        XCTAssertEqual(s.buddy.completionNotice?.cheer, .hop)
        XCTAssertEqual(s.buddy.recentFinishes.count, 1)
        s = reduce(s, .turnEnded(at: NOW+1, sessionId: "a", source: "codex", outcome: .completed))
        s = reduce(s, .turnEnded(at: NOW+2, sessionId: "b", source: "codex", outcome: .failed(errorClass: nil)))
        s = reduce(s, .sessionEnded(at: NOW+3, sessionId: "a"))
        XCTAssertEqual(s.buddy.recentFinishes.count, 1)
        XCTAssertNil(s.buddy.completionNotice) // errors outrank celebration
    }
    func testCoalescingDeadlineCooldownAndHistoryBound() {
        var s = finish(.test(), "a", NOW)
        let id = s.buddy.completionNotice?.id
        s = finish(s, "b", NOW+4500)
        XCTAssertEqual(s.buddy.completionNotice?.id, id)
        XCTAssertEqual(s.buddy.completionNotice?.until, NOW+6500)
        s = finish(s, "c", NOW+6400)
        XCTAssertEqual(s.buddy.completionNotice?.until, NOW+8000)
        s = finish(s, "d", NOW+7900)
        XCTAssertEqual(s.buddy.completionNotice?.until, NOW+8000)
        s = finish(s, "e", NOW+8100)
        XCTAssertNil(s.buddy.completionNotice)
        s = finish(s, "f", NOW+10900)
        XCTAssertNil(s.buddy.completionNotice)
        s = finish(s, "g", NOW+11100)
        XCTAssertEqual(s.buddy.completionNotice?.count, 1)
        XCTAssertEqual(s.buddy.recentFinishes.count, 6)
        XCTAssertEqual(s.buddy.recentFinishes.first?.sequence, 7)
    }
    func testTimerExpiryPublishesAndAttentionDoesNotReplay() {
        var s = finish(.test(), "a", NOW)
        let version = s.buddy.version
        s = reduce(s, .staleTick(at: NOW+5000))
        XCTAssertNil(s.buddy.completionNotice)
        XCTAssertGreaterThan(s.buddy.version, version)
        s = finish(s, "b", NOW+9000)
        s = reduce(s, .requestArrived(at: NOW+9100, sessionId: "a", requestId: "request", tool: "Question", hint: "Input", sessionLabel: nil))
        XCTAssertNil(s.buddy.completionNotice)
        s = reduce(s, .requestCleared(at: NOW+9200, sessionId: "a"))
        XCTAssertNil(s.buddy.completionNotice)
    }
    func testTitlesAreExplicitAndFallbackDistinguishesSameProject() {
        var s = applyEvents(.test(),
            .sessionStarted(at: NOW, sessionId: "a", source: "codex", cwd: "/private/project"),
            .sessionStarted(at: NOW, sessionId: "b", source: "codex", cwd: "/private/project"))
        XCTAssertNotEqual(s.buddy.deviceThreads[0].title, s.buddy.deviceThreads[1].title)
        XCTAssertFalse(s.buddy.deviceThreads[0].title.contains("/private"))
        s = reduce(s, .sessionTitleChanged(at: NOW+1, sessionId: "a", title: "Repair\nlayout"))
        s = finish(s, "a", NOW+100)
        XCTAssertEqual(s.buddy.recentFinishes.first?.title, "Repair layout")
    }
    func testWirePreservesNoticeAndTotalsUnderEscapingPressure() throws {
        var s = InternalState.test()
        for i in 0..<30 {
            s = reduce(s, .turnStarted(at: NOW, sessionId: "a\(i)", source: "codex"))
            s = reduce(s, .sessionTitleChanged(at: NOW, sessionId: "a\(i)", title: String(repeating: "\"한", count: 25)))
        }
        for i in 0..<6 { s = finish(s, "a\(i)", NOW+100+Double(i)) }
        var frame = renderState(from: s.buddy, now: NOW+200)
        XCTAssertEqual(frame.state, .working)
        frame.card = .needsYou(id: String(repeating: "\u{1}", count: 23), tool: "Ask", gloss: String(repeating: "\u{1}", count: 63), stakes: .fine, n: 1, of: 1, approval: false)
        let data = try XCTUnwrap(renderStateData(from: frame))
        XCTAssertLessThanOrEqual(data.count, maxHeartbeatBytes)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["threadTotal"] as? Int, 30)
        XCTAssertNotNil(object["notice"])
        XCTAssertFalse((object["recent"] as? [[Any]] ?? []).isEmpty)
    }
    func testHookTitleDoesNotUseRawPrompt() throws {
        let data = Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"a","prompt":"private prompt","thread_title":"Fix layout"}"#.utf8)
        let titled = try RawHookPayload.parse(data, source: "codex", at: NOW)
        XCTAssertEqual(titled?.displayTitle, "Fix layout")
        let bare = Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"a","prompt":"private prompt"}"#.utf8)
        let untitled = try RawHookPayload.parse(bare, source: "codex", at: NOW)
        XCTAssertNil(untitled?.displayTitle)
    }
    func testCodexIndexUsesNewestMatchingTitleAndToleratesBrokenRecords() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [#"{"id":"a","thread_name":"Old"}"#, "broken", #"{"id":"a","thread_name":"New"}"#, #"{"id":"b","thread_name":"Other"}"#].joined(separator: "\n")
        try Data(lines.utf8).write(to: url)
        XCTAssertEqual(SessionTitleReader.codexTitle(sessionId: "a", index: url), "New")
        XCTAssertNil(SessionTitleReader.codexTitle(sessionId: "missing", index: url))
    }

    func testThreadRowsKeepTheirPositionsAcrossCompletion() {
        var s = applyEvents(.test(),
            .sessionStarted(at: NOW, sessionId: "a", source: "codex", cwd: nil),
            .turnStarted(at: NOW, sessionId: "b", source: "codex"))
        let before = s.buddy.deviceThreads.map(\.id)
        s = reduce(s, .turnEnded(at: NOW+1, sessionId: "b", source: "codex", outcome: .completed))
        XCTAssertEqual(s.buddy.deviceThreads.map(\.id), before)
        XCTAssertEqual(s.buddy.deviceThreads.last?.status, 0)
    }

}
