import Foundation
import XCTest
@testable import BoopCore

final class HookFixtureTests: XCTestCase {
    /// Replay the raw captures so an agent's schema drift fails at the input boundary.
    func testRecordedHooksDecode() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hooks")
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in files {
            guard file.pathExtension == "json" else { continue }
            let body = try JSONDecoder().decode(HookEventBody.self, from: Data(contentsOf: file))
            XCTAssertNotNil(body.effectiveEventName, file.path)
            XCTAssertNotNil(body.session_id ?? body.conversation_id, file.path)
        }
    }
}

func hookFixtureURLs() -> [URL] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/hooks")
    return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
}

extension HookFixtureTests {
    func testTenthTryAllAgents() async throws {
        for url in hookFixtureURLs() where url.lastPathComponent == "tenth-try.jsonl" {
            let fixtureSource = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            for source in fixtureSource == "claude-code" ? ["claude-code", "codex"] : [fixtureSource] {
            let extractor = Extractor()
            var state = InternalState.initial(staleMs: 10_000_000, celebrateDurationMs: 4000)
            var grinding = false
            var session = ""
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            for (i, line) in lines.enumerated() {
                let payload = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: source, at: Double(i) * 1000))
                session = payload.sessionId
                let result = await extractor.ingest(payload, localHour: 12)
                for event in result.events { state = reduce(state, event) }
                grinding = grinding || state.buddy.creature.effort == .grinding
            }
            let window = await extractor.windows[session]
            XCTAssertFalse(grinding)
            XCTAssertEqual(state.buddy.creature.cheer, .hop)
            state = reduce(state, .staleTick(at: 100_000))
            }
        }
    }

    func testStuckAndRateLimitStreams() async throws {
        for url in hookFixtureURLs() where url.lastPathComponent != "tenth-try.jsonl" {
            let extractor = Extractor()
            var state = InternalState.initial(staleMs: 10_000_000, celebrateDurationMs: 4000)
            for (i, line) in try String(contentsOf: url, encoding: .utf8).split(separator: "\n").enumerated() {
                let payload = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: "claude-code", at: Double(i) * 1000))
                for event in await extractor.ingest(payload).events { state = reduce(state, event) }
                if payload.errorClass == "rate_limit" { XCTAssertEqual(state.buddy.creature.uhoh, .error) }
            }
            if url.lastPathComponent == "stuck.jsonl" { XCTAssertNil(state.buddy.creature.uhoh) }
            else { XCTAssertNil(state.buddy.creature.bubble) }
        }
    }
}
