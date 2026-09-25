import Foundation
import XCTest
@testable import HookWire

final class HookWireTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/hooks")

    func payload(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testKeepsOnlyTheMappedFields() throws {
        let raw = payload([
            "hook_event_name": "PreToolUse", "session_id": "s1", "cwd": "/w/landing", "tool_name": "Bash",
            "tool_input": ["command": "npm test -- SECRET_ARG"], "transcript_path": "/secret/t.jsonl",
        ])
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: raw, ts: 42))
        XCTAssertEqual(line, HookLine(agent: "claude", hook: "PreToolUse", session: "s1", cwd: "/w/landing",
                                      tool: "Bash", topic: "tests", ts: 42))
        let wire = String(decoding: line.encoded(), as: UTF8.self)
        XCTAssertFalse(wire.contains("SECRET"))
        XCTAssertFalse(wire.contains("transcript"))
        XCTAssertTrue(wire.hasSuffix("\n"))
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
    }

    func testStopFailureKeepsTheErrorClassAndNotificationItsType() throws {
        let failure = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "StopFailure", "session_id": "s", "error": "rate_limit",
            "last_assistant_message": "PRIVATE",
        ]), ts: 0))
        XCTAssertEqual(failure.error, "rate_limit")
        XCTAssertFalse(String(decoding: failure.encoded(), as: UTF8.self).contains("PRIVATE"))
        let note = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "Notification", "session_id": "s", "notification_type": "permission_prompt",
            "message": "Claude needs your permission to use Bash",
        ]), ts: 0))
        XCTAssertEqual(note.kind, "permission_prompt")
        XCTAssertFalse(String(decoding: note.encoded(), as: UTF8.self).contains("Bash"))
    }

    func testNoPromptOrOutputFromAnyRecordedFixtureReachesTheLine() throws {
        let files = FileManager.default.enumerator(at: HookWireTests.fixtures, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { ["json", "jsonl"].contains($0.pathExtension) }
        XCTAssertGreaterThan(files.count, 3)
        var lines = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let payloads = file.pathExtension == "json" ? [text] : text.split(separator: "\n").map(String.init)
            for raw in payloads where !raw.isEmpty {
                guard let line = HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0) else { continue }
                lines += 1
                XCTAssertFalse(String(decoding: line.encoded(), as: UTF8.self).contains("PRIVATE"), file.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(lines, 40)
    }

    func testPayloadWithoutHookNameOrSessionIsDropped() {
        XCTAssertNil(HookLine.extract(agent: "claude", payload: payload(["session_id": "s"]), ts: 0))
        XCTAssertNil(HookLine.extract(agent: "claude", payload: payload(["hook_event_name": "Stop"]), ts: 0))
        XCTAssertNil(HookLine.extract(agent: "claude", payload: Data("not json".utf8), ts: 0))
    }

    func testAPayloadCutOffAtTheCapStillGivesTheEvent() throws {
        let big = String(repeating: "x", count: 300_000)
        let raw = payload(["hook_event_name": "PostToolUse", "session_id": "s9", "cwd": "/w/jetpack",
                           "tool_name": "Read", "tool_response": big])
        let cut = raw.prefix(256 * 1024)
        let line = try XCTUnwrap(HookLine.extract(agent: "codex", payload: Data(cut), ts: 1))
        XCTAssertEqual(line.hook, "PostToolUse")
        XCTAssertEqual(line.session, "s9")
        XCTAssertNil(line.topic)
    }

    func testCodexShellArgvAndPatchesGetTopics() {
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["bash", "-lc", "cargo test -q"]]), "tests")
        XCTAssertEqual(Topic.tag(tool: "exec_command", input: ["cmd": "pnpm run build"]), "build")
        XCTAssertEqual(Topic.tag(tool: "apply_patch", input: ["input": "*** Begin Patch\n*** Update File: docs/intro.md\n@@"]), "docs")
        XCTAssertEqual(Topic.tag(tool: "apply_patch", input: ["input": "*** Begin Patch\n*** Update File: src/a.swift\n@@"]), nil)
    }

    func testTopicTable() {
        let cases: [(String, String?)] = [
            ("pytest -x tests/", "tests"), ("npm test", "tests"), ("npx jest --watch=false", "tests"),
            ("vitest run", "tests"), ("go test ./...", "tests"), ("cargo test", "tests"),
            ("swift test --filter Foo", "tests"), ("cd app && make test", "tests"), ("./gradlew test", "tests"),
            ("make", "build"), ("make -j8 all", "build"), ("npm run build", "build"), ("cargo build --release", "build"),
            ("swift build", "build"), ("xcodebuild -scheme Boop", "build"), ("tsc -p .", "build"),
            ("vercel --prod", "deploy"), ("fly deploy", "deploy"), ("kubectl apply -f k8s/", "deploy"),
            ("terraform apply -auto-approve", "deploy"),
            ("ls -la", nil), ("cat Makefile", nil), ("git status", nil), ("echo testing", nil), ("", nil),
        ]
        for (command, topic) in cases {
            XCTAssertEqual(Topic.tag(command: command), topic, command)
        }
    }

    func testEditsToMarkdownOrTextAreDocs() {
        XCTAssertEqual(Topic.tag(tool: "Edit", input: ["file_path": "/w/README.md"]), "docs")
        XCTAssertEqual(Topic.tag(tool: "Write", input: ["file_path": "/w/notes.txt"]), "docs")
        XCTAssertEqual(Topic.tag(tool: "Edit", input: ["file_path": "/w/main.swift"]), nil)
        XCTAssertEqual(Topic.tag(tool: "Read", input: ["file_path": "/w/README.md"]), nil)
        XCTAssertEqual(Topic.tag(tool: nil, input: nil), nil)
    }

    func testSendingToAMissingSocketGivesUpAtOnce() {
        let start = Date()
        XCTAssertFalse(HookSocket.send(Data("x\n".utf8), to: "/tmp/boop-missing-\(getpid()).sock"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }

    func testDefaultSocketPath() {
        XCTAssertEqual(HookSocket.defaultPath(environment: ["HOME": "/Users/x"]),
                       "/Users/x/Library/Application Support/Boop/boop.sock")
        XCTAssertEqual(HookSocket.defaultPath(environment: ["HOME": "/Users/x", "BOOP_SOCKET": "/tmp/b.sock"]), "/tmp/b.sock")
    }
}
