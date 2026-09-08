import Foundation
import XCTest
@testable import BoopCore

final class ExtractorPrivacyTests: XCTestCase {
    @MainActor func testCapturedLeaderboardBodyExcludesPrivateContext() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        var config = BuddyConfig.default; config.headless = true
        let defaults = UserDefaults(suiteName: "privacy-" + UUID().uuidString)!
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        let engine = BuddyEngine(config: config, store: store, defaults: defaults)
        let payload = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PreToolUse","session_id":"secret","cwd":"/private/PROJECT_SECRET","tool_name":"Bash","tool_input":{"command":"HINT_SECRET"}}"#.utf8), source: "claude-code", at: 0))
        await engine.ingest(payload)
        try await store.addProfileLine("PROFILE_SECRET", source: "rules", at: 0)
        let signer = TestDeviceSigner()
        try await store.acceptIdentity(signer.identity, at: 0)
        try await store.saveSignature(signer.sign(SignRequest(day: "2026-09-09", xp: 12)))
        let body = try await engine.submissionPreview()
        let session = LeaderboardURLProtocol.session(); defer { session.invalidateAndCancel() }
        LeaderboardURLProtocol.capture.reset()
        try await LeaderboardClient(url: URL(string: "https://leaderboard.invalid")!, session: session).submit(body)
        let capturedData = try XCTUnwrap(LeaderboardURLProtocol.capture.captured.first?.httpBody)
        let captured = String(decoding: capturedData, as: UTF8.self)
        for secret in ["PROJECT_SECRET", "Bash", "HINT_SECRET", "PROFILE_SECRET", "claude-code", "cwd", "tool_name"] {
            XCTAssertFalse(captured.contains(secret), secret)
        }
        let object = try JSONSerialization.jsonObject(with: Data(captured.utf8)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), Set(["buddyName", "silhouette", "xpTotal", "signatures", "unit", "pub", "alg"]))
    }

    @MainActor func testFixturesNeverReachDiskOrDiagnostics() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = BuddyConfig.default
        config.stateDir = dir.path
        let store = try Store(stateDir: dir.path, now: Date.now.timeIntervalSince1970 * 1000)
        let engine = BuddyEngine(config: config, store: store)
        let privacyExtractor = Extractor()
        for url in hookFixtureURLs() {
            let source = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let p = try XCTUnwrap(RawHookPayload.parse(Data(line.utf8), source: source, at: 0))
                await engine.ingest(p)
                let extraction = await privacyExtractor.ingest(p)
                let surfaces = String(decoding: try JSONEncoder().encode(engine.state), as: UTF8.self)
                    + String(decoding: try JSONEncoder().encode(extraction.facts), as: UTF8.self)
                    + String(decoding: try JSONEncoder().encode(engine.diagnosticLog.entries), as: UTF8.self)
                for marker in ["swift test", "npm test", "/private/project", "PRIVATE_PROMPT_8431", "PRIVATE_OUTPUT_9823", "PRIVATE_CLOSING_7182"] {
                    XCTAssertFalse(surfaces.contains(marker), marker)
                }
            }
        }
        await engine.flushStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("boop.sqlite").path))
        var content = String(decoding: try JSONEncoder().encode(engine.diagnosticLog.entries), as: UTF8.self)
        content += String(decoding: try JSONEncoder().encode(try await engine.storedFacts()), as: UTF8.self)
        let files = FileManager.default.enumerator(atPath: engine.stateDir)?.allObjects as? [String] ?? []
        XCTAssertFalse(files.isEmpty, "Exercise real memory persistence, not an empty directory")
        for file in files {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(file)) {
                content += String(decoding: data, as: UTF8.self)
                // Inspect SQLite, WAL, and shared-memory bytes, including free pages.
                for marker in ["PRIVATE_PROMPT_8431", "PRIVATE_OUTPUT_9823", "PRIVATE_CLOSING_7182", "swift test", "npm test", "/private/project"] {
                    XCTAssertNil(data.range(of: Data(marker.utf8)), "\(file): \(marker)")
                }
            }
        }
        for marker in ["PRIVATE_PROMPT_8431", "PRIVATE_OUTPUT_9823", "PRIVATE_CLOSING_7182"] { XCTAssertFalse(content.contains(marker), marker) }
    }

    func testTenThousandHooksRetainOnlyTallies() async throws {
        let extractor = Extractor()
        let call = Data(#"{"hook_event_name":"PreToolUse","session_id":"large","tool_name":"Bash","tool_input":{"command":"swift test"}}"#.utf8)
        let result = Data(#"{"hook_event_name":"PostToolUse","session_id":"large","tool_name":"Bash","exit_code":1,"output":"failed"}"#.utf8)
        for i in 0..<10_000 {
            let p = try XCTUnwrap(RawHookPayload.parse(i % 2 == 0 ? call : result, source: "claude-code", at: Double(i)))
            _ = await extractor.ingest(p)
        }
        let snapshot = await extractor.windows["large"]
        let window = try XCTUnwrap(snapshot)
        XCTAssertTrue(window.pending.isEmpty)
        XCTAssertEqual(window.goals.count, 1)
        XCTAssertEqual(window.goals.values.first?.attempts, 5000)
        let end = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"SessionEnd","session_id":"large"}"#.utf8), source: "claude-code", at: 10_001))
        _ = await extractor.ingest(end)
        let remaining = await extractor.windows.count
        XCTAssertEqual(remaining, 0)
    }

    func testUnknownAndExitStatusPrecedence() throws {
        let runner = try XCTUnwrap(GoalsReader.runner("swift test"))
        var p = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PostToolUse","tool_name":"Bash","output":"unrecognized"}"#.utf8), source: "claude-code", at: 0))
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .unknown)
        p.outputHead = "FAILED"; p.exitStatus = 0
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .pass)
        p.exitStatus = 2; p.outputHead = "passed"
        XCTAssertEqual(GoalsReader.outcome(p, runner: runner), .fail)
    }

    func testAdapterDegradesOncePerSource() async throws {
        let extractor = Extractor()
        let p = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PreToolUse"}"#.utf8), source: "claude-code", at: 0))
        let first = await extractor.ingest(p)
        let second = await extractor.ingest(p)
        XCTAssertEqual(first.events.filter { $0.name == "adapterDegraded" }.count, 1)
        XCTAssertEqual(second.events.filter { $0.name == "adapterDegraded" }.count, 0)
    }

    func testRunnerCoverageAndSignatures() {
        for command in ["swift test", "swift build", "xcodebuild", "npm test", "pnpm build", "yarn lint", "jest", "vitest", "pytest", "cargo test", "cargo build", "cargo clippy", "go test", "go build", "go vet", "make test", "make build", "tsc", "eslint", "ruff", "mypy", "gradle", "mvn"] { XCTAssertNotNil(GoalsReader.runner(command), command) }
        XCTAssertEqual(GoalsReader.signature("swift test --filter /tmp/Foo 2>&1"), GoalsReader.signature("swift   test --filter Foo"))
    }
}

extension ExtractorPrivacyTests {
    func testInterleavedResultsUseCallIds() async throws {
        let extractor = Extractor()
        let bodies = [
            #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"a","tool_input":{"command":"swift test"}}"#,
            #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"b","tool_input":{"command":"swift build"}}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"b","exit_code":0}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"a","exit_code":1}"#
        ]
        for (i, body) in bodies.enumerated() {
            let p = try XCTUnwrap(RawHookPayload.parse(Data(body.utf8), source: "claude-code", at: Double(i)))
            _ = await extractor.ingest(p)
        }
        let goals = await extractor.windows["s"]?.goals
        XCTAssertEqual(goals?[GoalsReader.signature("swift test")]?.lastOutcome, .fail)
        XCTAssertEqual(goals?[GoalsReader.signature("swift build")]?.lastOutcome, .pass)
    }
    func testClosingCallbackDoesNotCompleteTwice() async throws {
        let extractor = Extractor()
        let p = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"afterAgentResponse","conversation_id":"s","text":"private closing text"}"#.utf8), source: "cursor", at: 0))
        let extraction = await extractor.ingest(p)
        XCTAssertTrue(extraction.events.isEmpty)
        XCTAssertTrue(extraction.facts.isEmpty)
        let windows = await extractor.windows
        XCTAssertEqual(windows["s"]?.closingLine, "private closing text")
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

extension ExtractorPrivacyTests {
    func testOpaqueKeyAndGoalReset() {
        let key = GoalsReader.signature("swift test --filter /tmp/SecretTests")
        XCTAssertEqual(key.count, 16)
        XCTAssertTrue(key.allSatisfy { "0123456789abcdef".contains($0) })
        var tally = GoalTally()
        tally.record(.fail, at: 10)
        tally.record(.fail, at: 20)
        XCTAssertEqual(tally.attemptsWithoutPass, 2)
        XCTAssertEqual(tally.firstFailureAt, 10)
        tally.record(.pass, at: 30)
        XCTAssertEqual(tally.attempts, 3)
        XCTAssertEqual(tally.attemptsWithoutPass, 0)
        XCTAssertNil(tally.firstFailureAt)
        tally.record(.fail, at: 40)
        XCTAssertEqual(tally.firstFailureAt, 40)
        tally.record(.unknown, at: 50)
        XCTAssertNil(tally.firstFailureAt)
    }

    func testLivenessDoesNotDegradeAndSourcesAreIndependent() async throws {
        let extractor = Extractor()
        for source in ["claude-code", "codex", "cursor"] {
            let ping = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PostToolUse","session_id":"ping"}"#.utf8), source: source, at: 0))
            let result = await extractor.ingest(ping)
            XCTAssertFalse(result.events.contains { $0.name == "adapterDegraded" })
        }
        let broken = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PreToolUse","session_id":"broken"}"#.utf8), source: "codex", at: 1))
        _ = await extractor.ingest(broken)
        let healthy = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PreToolUse","session_id":"healthy","tool_name":"Bash","tool_input":{"command":"pytest"}}"#.utf8), source: "claude-code", at: 2))
        let result = await extractor.ingest(healthy)
        XCTAssertEqual(result.goalRunner, "pytest")
        XCTAssertTrue(result.events.contains { $0.name == "toolCalled" })
    }

    func testProjectResolvedOnceAndClosingLineCapped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".git/config")
        try "[remote \"origin\"]\nurl = https://example.com/one\n".write(to: config, atomically: true, encoding: .utf8)
        let extractor = Extractor()
        var p = RawHookPayload(source: "codex", sessionId: "s", kind: .sessionStart, toolName: "", cwd: root.path, timestamp: 0)
        let first = await extractor.ingest(p)
        let project = await extractor.windows["s"]?.project
        XCTAssertNotEqual(project, root.lastPathComponent)
        XCTAssertTrue(first.events.contains { $0.name == "sessionStarted" })
        try "[remote \"origin\"]\nurl = https://example.com/two\n".write(to: config, atomically: true, encoding: .utf8)
        p.kind = .turnEnd; p.closingOnly = true; p.closingMessage = String(repeating: "한 ", count: 200)
        _ = await extractor.ingest(p)
        let w = await extractor.windows["s"]
        XCTAssertEqual(w?.project, project)
        XCTAssertEqual(w?.closingLine?.count, 120)
    }

    func testEffortOnlyEmitsChangesAndUsesThresholds() async throws {
        let extractor = Extractor()
        var p = RawHookPayload(source: "codex", sessionId: "s", kind: .toolCall, toolName: "Bash", toolInput: "pytest", timestamp: 0)
        var emissions = 0
        for i in 0..<8 {
            p.kind = .toolCall; p.exitStatus = nil; p.timestamp = Double(i * 2)
            emissions += await extractor.ingest(p).events.filter { $0.name == "effortObserved" }.count
            p.kind = .toolResult; p.exitStatus = 1; p.timestamp += 1
            emissions += await extractor.ingest(p).events.filter { $0.name == "effortObserved" }.count
        }
        XCTAssertEqual(emissions, 2)
        var thresholds = MomentThresholds.defaults
        thresholds.effortHardErrors = 5; thresholds.effortGrindingErrors = 7
        var w = SessionWindow(project: "p", startedAt: 0); w.errors = 4
        XCTAssertEqual(EffortReader.read(w, at: 0, thresholds: thresholds), .light)
        w.errors = 5
        XCTAssertEqual(EffortReader.read(w, at: 0, thresholds: thresholds), .hard)
    }
}

extension ExtractorPrivacyTests {
    @MainActor func testCommandsAndPathsNeverBecomeHintsOrFacts() async throws {
        let engine = BuddyEngine(config: .default)
        let privacyExtractor = Extractor()
        for command in ["swift test --filter /private/SECRET.swift", "npm test -- /tmp/private-test.js"] {
            let data = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "privacy", "tool_name": "Bash", "tool_input": ["command": command]])
            let p = try XCTUnwrap(RawHookPayload.parse(data, source: "codex", at: 0))
            await engine.ingest(p)
            let result = try XCTUnwrap(RawHookPayload.parse(Data(#"{"hook_event_name":"PostToolUse","session_id":"privacy","tool_name":"Bash","exit_code":0}"#.utf8), source: "codex", at: 1))
            await engine.ingest(result)
            let callFacts = await privacyExtractor.ingest(p).facts
            let resultFacts = await privacyExtractor.ingest(result).facts
            engine.turnEnded(sessionId: "privacy", source: "codex", outcome: .completed)
            let surfaces = String(decoding: try JSONEncoder().encode(engine.state), as: UTF8.self)
                + String(decoding: try JSONEncoder().encode(engine.diagnosticLog.entries), as: UTF8.self)
                + String(decoding: try JSONEncoder().encode(callFacts + resultFacts), as: UTF8.self)
            for marker in [command, "swift test", "npm test", "/private/SECRET.swift", "/tmp/private-test.js"] {
                XCTAssertFalse(surfaces.contains(marker), marker)
            }
        }
    }
    func testUnknownOutcomesCannotCreateHardWonEvidence() {
        var tally = GoalTally()
        for i in 0..<10 { tally.record(.unknown, at: Double(i)) }
        XCTAssertEqual(tally.attempts, 10)
        XCTAssertEqual(tally.attemptsWithoutPass, 0)
        XCTAssertNil(tally.firstFailureAt)
    }
}
