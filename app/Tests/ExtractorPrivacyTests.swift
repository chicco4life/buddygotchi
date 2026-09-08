import Foundation
import XCTest
@testable import BoopCore

final class ExtractorPrivacyTests: XCTestCase {
    @MainActor func testFixturesNeverReachDiskOrDiagnostics() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = BuddyConfig.default
        config.stateDir = dir.path
        let engine = BuddyEngine(config: config, memoryStore: FilePetMemoryStore(stateDir: dir.path))
        for url in hookFixtureURLs() {
            let source = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let p = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: source, at: 0))
                await engine.ingest(p)
            }
        }
        var content = String(decoding: try JSONEncoder().encode(engine.diagnosticLog.entries), as: UTF8.self)
        content += String(decoding: try JSONEncoder().encode(engine.factRing.facts), as: UTF8.self)
        let files = FileManager.default.enumerator(atPath: engine.stateDir)?.allObjects as? [String] ?? []
        XCTAssertFalse(files.isEmpty, "Exercise real memory persistence, not an empty directory")
        for file in files { if let data = try? Data(contentsOf: dir.appendingPathComponent(file)) { content += String(decoding: data, as: UTF8.self) } }
        for marker in ["PRIVATE_PROMPT_8431", "PRIVATE_OUTPUT_9823", "PRIVATE_CLOSING_7182"] { XCTAssertFalse(content.contains(marker), marker) }
        XCTAssertTrue(engine.diagnosticLog.entries.allSatisfy { $0.rawPayload == nil })
    }

    func testTenThousandEntriesEvictWithoutLosingTally() async throws {
        let extractor = Extractor()
        let call = Data(#"{"hook_event_name":"PreToolUse","session_id":"large","tool_name":"Bash","tool_input":{"command":"swift test"}}"#.utf8)
        let result = Data(#"{"hook_event_name":"PostToolUse","session_id":"large","tool_name":"Bash","exit_code":1,"output":"failed"}"#.utf8)
        for i in 0..<10_000 {
            let p = try XCTUnwrap(RawHookPayload.claudeCode(i % 2 == 0 ? call : result, at: Double(i)))
            _ = await extractor.ingest(p)
        }
        let snapshot = await extractor.windows["large"]
        let window = try XCTUnwrap(snapshot)
        XCTAssertLessThanOrEqual(window.entries.count, 400)
        XCTAssertLessThanOrEqual(window.byteCount, 512 * 1024)
        XCTAssertEqual(window.goals.values.first?.attempts, 5000)
        let end = try XCTUnwrap(RawHookPayload.claudeCode(Data(#"{"hook_event_name":"SessionEnd","session_id":"large"}"#.utf8), at: 10_001))
        _ = await extractor.ingest(end)
        let remaining = await extractor.windows.count
        XCTAssertEqual(remaining, 0)
    }

    func testWindowByteCapAndUnicode() {
        var window = SessionWindow(project: "p", startedAt: 0)
        for i in 0..<500 { window.append(.init(kind: .toolResult, at: Double(i), text: String(repeating: "한", count: 1000))) }
        XCTAssertLessThanOrEqual(window.byteCount, 512 * 1024)
        XCTAssertEqual(window.byteCount, window.entries.reduce(0) { $0 + $1.text.utf8.count })
        XCTAssertEqual(capUTF8("한한", 4), "한")
    }

    func testUnknownAndExitStatusPrecedence() throws {
        let runner = try XCTUnwrap(GoalsReader.runner("swift test"))
        var p = try XCTUnwrap(RawHookPayload.claudeCode(Data(#"{"hook_event_name":"PostToolUse","tool_name":"Bash","output":"unrecognized"}"#.utf8), at: 0))
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .unknown)
        p.outputHead = "FAILED"; p.exitStatus = 0
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .pass)
        p.exitStatus = 2; p.outputHead = "passed"
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .fail)
    }

    func testAdapterDegradesOncePerSource() async throws {
        let extractor = Extractor()
        let p = try XCTUnwrap(RawHookPayload.claudeCode(Data(#"{"hook_event_name":"PreToolUse","tool_name":"Bash"}"#.utf8), at: 0))
        let first = await extractor.ingest(p)
        let second = await extractor.ingest(p)
        XCTAssertEqual(first.events.filter { $0.name == "adapterDegraded" }.count, 1)
        XCTAssertEqual(second.events.filter { $0.name == "adapterDegraded" }.count, 0)
    }

    func testRunnerCoverageAndSignatures() {
        for command in ["swift test", "swift build", "xcodebuild", "npm test", "pnpm build", "yarn lint", "jest", "vitest", "pytest", "cargo test", "cargo build", "cargo clippy", "go test", "go build", "go vet", "make test", "make build", "tsc", "eslint", "ruff", "mypy", "gradle", "mvn"] { XCTAssertNotNil(GoalsReader.runner(command), command) }
        XCTAssertEqual(GoalsReader.signature("swift test --filter /tmp/Foo 2>&1", project: "p"), GoalsReader.signature("swift   test --filter Foo", project: "p"))
    }
}

extension ExtractorPrivacyTests {
    @MainActor func testFactRingEvictsAtFiveHundred() {
        let ring = FactRing()
        ring.receive((0..<1000).map { Fact(kind: .theme, sessionId: "s", project: "p", at: Double($0), payload: [:]) })
        XCTAssertEqual(ring.facts.count, 500)
        XCTAssertEqual(ring.facts.first?.at, 500)
    }
    func testInterleavedResultsUseCallIds() async throws {
        let extractor = Extractor()
        let bodies = [
            #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"a","tool_input":{"command":"swift test"}}"#,
            #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"b","tool_input":{"command":"swift build"}}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"b","exit_code":0}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"a","exit_code":1}"#
        ]
        for (i, body) in bodies.enumerated() {
            let p = try XCTUnwrap(RawHookPayload.claudeCode(Data(body.utf8), at: Double(i)))
            _ = await extractor.ingest(p)
        }
        let goals = await extractor.windows["s"]?.goals
        XCTAssertEqual(goals?["unknown|swift test"]?.lastOutcome, .fail)
        XCTAssertEqual(goals?["unknown|swift build"]?.lastOutcome, .pass)
    }
    func testClosingCallbackDoesNotCompleteTwice() async throws {
        let extractor = Extractor()
        let p = try XCTUnwrap(RawHookPayload.cursor(Data(#"{"hook_event_name":"afterAgentResponse","conversation_id":"s","text":"private closing text"}"#.utf8), at: 0))
        let extraction = await extractor.ingest(p)
        XCTAssertTrue(extraction.events.isEmpty)
        XCTAssertTrue(extraction.facts.isEmpty)
        let windows = await extractor.windows
        XCTAssertEqual(windows["s"]?.entries.last?.text, "private closing text")
        await extractor.reset()
        let empty = await extractor.windows.isEmpty
        XCTAssertTrue(empty)
    }
    func testStakesAndGlossTemplates() {
        XCTAssertEqual(StakesReader.read(tool: "Bash", input: "rm -rf ../data").0, .careful)
        XCTAssertEqual(StakesReader.read(tool: "Bash", input: #"{"command":"ls\nls"}"#).0, .careful)
        XCTAssertEqual(GlossWriter.read(tool: "Bash", input: "rm -rf ./data"), "deletes files in this folder")
        XCTAssertEqual(GlossWriter.read(tool: "Bash", input: "npm install"), "installs packages")
        XCTAssertEqual(GlossWriter.read(tool: "Read", input: ""), "reads files")
        XCTAssertEqual(GlossWriter.read(tool: "Bash", input: "curl https://example.com"), "reaches the internet")
        XCTAssertEqual(GlossWriter.read(tool: "Edit", input: #"{"file_path":"/tmp/main.swift"}"#), "edits main.swift")
        XCTAssertEqual(GlossWriter.read(tool: "Bash", input: "swift test"), "runs a command")
    }
}
