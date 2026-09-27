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

    /// ADAPTERS.md §2: a failed call's error text never gets this far, only
    /// whether you interrupted it.
    func testPostToolUseFailureKeepsOnlyWhetherYouInterruptedIt() throws {
        let failure = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "PostToolUseFailure", "session_id": "s", "tool_name": "Bash",
            "tool_input": ["command": "npm test"], "error": "PRIVATE Command exited with non-zero status code 1",
            "is_interrupt": false,
        ]), ts: 0))
        XCTAssertEqual(failure, HookLine(agent: "claude", hook: "PostToolUseFailure", session: "s", tool: "Bash", topic: "tests", ts: 0))
        let wire = String(decoding: failure.encoded(), as: UTF8.self)
        XCTAssertFalse(wire.contains("PRIVATE") || wire.contains("interrupt"), wire)
        let interrupted = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "PostToolUseFailure", "session_id": "s", "tool_name": "Bash",
            "tool_input": ["command": "npm test"], "is_interrupt": true,
        ]), ts: 0))
        XCTAssertTrue(interrupted.interrupt)
        XCTAssertEqual(HookLine.decode(interrupted.encoded()), interrupted)
        let succeeded = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash", "is_interrupt": true,
        ]), ts: 0))
        XCTAssertFalse(succeeded.interrupt, "only a failure can be an interrupt")
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

    /// ADAPTERS.md §2: a subagent's hooks carry the parent's session plus
    /// its `agent_id`, which the line keeps (an opaque id; `agent_type` is
    /// dropped), even from a payload cut off at the cap.
    func testASubagentsIDIsKept() throws {
        let raw = payload([
            "hook_event_name": "PreToolUse", "session_id": "s1", "agent_id": "a1b2", "agent_type": "general-purpose",
            "tool_name": "Read", "tool_input": ["file_path": "/w/x.swift"],
        ])
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: raw, ts: 0))
        XCTAssertEqual(line.agentID, "a1b2")
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
        XCTAssertFalse(String(decoding: line.encoded(), as: UTF8.self).contains("general-purpose"))
        let main = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload(["hook_event_name": "Stop", "session_id": "s1"]), ts: 0))
        XCTAssertNil(main.agentID)
        XCTAssertFalse(String(decoding: main.encoded(), as: UTF8.self).contains("agent_id"))
        let big = String(repeating: "x", count: 300_000)
        let cut = Data(#"{"session_id": "s1", "agent_id": "a1b2", "hook_event_name": "PostToolUse", "tool_name": "Read", "tool_response": "\#(big)"}"#.utf8).prefix(256 * 1024)
        XCTAssertEqual(HookLine.extract(agent: "claude", payload: Data(cut), ts: 0)?.agentID, "a1b2")
    }

    func testPayloadWithoutHookNameOrSessionIsDropped() {
        XCTAssertNil(HookLine.extract(agent: "claude", payload: payload(["session_id": "s"]), ts: 0))
        XCTAssertNil(HookLine.extract(agent: "claude", payload: payload(["hook_event_name": "Stop"]), ts: 0))
        XCTAssertNil(HookLine.extract(agent: "claude", payload: Data("not json".utf8), ts: 0))
    }

    func testAPayloadCutOffAtTheCapStillGivesTheEvent() throws {
        let big = String(repeating: "x", count: 300_000)
        // Agents send the small fields first, as the recorded fixtures show.
        let raw = Data(#"{"session_id": "s9", "cwd": "/w/jetpack", "hook_event_name": "PostToolUse", "tool_name": "Read", "tool_response": "\#(big)"}"#.utf8)
        let cut = raw.prefix(256 * 1024)
        let line = try XCTUnwrap(HookLine.extract(agent: "codex", payload: Data(cut), ts: 1))
        XCTAssertEqual(line.hook, "PostToolUse")
        XCTAssertEqual(line.session, "s9")
        XCTAssertNil(line.topic)
    }

    /// ADAPTERS.md §2: a cut that lands inside a multibyte character still
    /// gives the event (a Write of 300 KB of accented text).
    func testACutInsideACharacterStillGivesTheEvent() throws {
        let big = String(repeating: "é", count: 200_000)
        let raw = Data(#"{"session_id": "s9", "hook_event_name": "PostToolUse", "tool_name": "Write", "tool_input": {"content": "\#(big)"}}"#.utf8)
        for cut in [256 * 1024, 256 * 1024 - 1] {
            let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: Data(raw.prefix(cut)), ts: 1), "\(cut)")
            XCTAssertEqual(line.hook, "PostToolUse")
            XCTAssertEqual(line.tool, "Write")
        }
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

    /// ADAPTERS.md §3: the topic comes from what the command runs, after
    /// `VAR=value`, `cd … &&` and wrappers, never from a word in its
    /// arguments, quoted text or a heredoc. A failing grep for "make test"
    /// must not fail a turn, and a commit message about pytest must not
    /// hide one. Real commands, as agents write them.
    func testTopicComesFromWhatTheCommandRuns() {
        let cases: [(String, String?)] = [
            // What runs.
            ("cd app && swift test", "tests"), ("FOO=1 npm test", "tests"), ("CI=true npx vitest run", "tests"),
            ("uv run pytest -q tests/test_api.py", "tests"), ("python3 -m pytest -x", "tests"),
            ("bundle exec rspec spec/models", "tests"), ("make -C firmware test", "tests"),
            ("swift test 2>&1 | tail -20", "tests"), ("timeout 600 make fw-test", "tests"),
            ("env -i PATH=/usr/bin make test", "tests"), ("(cd app && cargo test --release)", "tests"),
            ("xcodebuild -scheme Boop -destination 'platform=macOS' test", "tests"),
            ("bash -lc 'cd app && go test ./...'", "tests"), ("make build && make test", "tests"),
            ("bash --norc -c \"pytest -x\"", "tests"), ("zsh --no-rcs -c 'npm test'", "tests"),
            ("bash --rcfile x -c 'go test ./...'", "tests"), ("bash -o pipefail -c 'make test'", "tests"),
            ("cd /Users/me/src/landing && npm run build 2>&1 | tail -40", "build"),
            ("make 2>&1 | grep -i error", "build"), ("sudo make install", "build"),
            ("git push heroku main", "deploy"), ("npx vercel --prod", "deploy"),
            ("gcloud app deploy --quiet", "deploy"), ("make test && vercel --prod", "deploy"),
            // Inside shell syntax, behind a wrapper's flag value, or run by
            // a package manager or a container.
            ("for i in 1 2 3; do make test || break; done", "tests"), ("if [ -f Makefile ]; then make test; fi", "tests"),
            ("{ make test; } 2>&1 | tee out.log", "tests"), ("! make test", "tests"),
            ("while ! make fw-test; do sleep 5; done", "tests"), ("timeout -s KILL 600 make test", "tests"),
            ("sudo -u ci make test", "tests"), ("env -u DEBUG cargo test", "tests"), ("yarn jest --ci", "tests"),
            ("pnpm vitest run", "tests"), ("bun x vitest", "tests"), ("yarn test --watch=false", "tests"),
            ("bun test", "tests"), ("bun run build", "build"), ("yarn tsc --noEmit", "build"),
            ("docker compose run --rm web pytest", "tests"), ("docker exec -it api make test", "tests"),
            ("docker compose -f compose.test.yml run -e CI=1 web bundle exec rspec", "tests"),
            ("docker build -t app .", "build"),
            // Only mentioned.
            ("grep -rn \"make webcam-test\" README.md plan/", nil), ("grep -n 'make test' Makefile", nil),
            ("git commit -m \"run pytest in CI\"", nil), ("python3 -c \"import pytest\"", nil),
            ("which tsc", nil), ("ls node_modules/.bin/jest", nil), ("rg -l 'cargo test' docs", nil),
            ("echo \"now run: make test\"", nil), ("go run ./cmd/test", nil),
            ("git log --oneline | grep -i vercel", nil), ("cat package.json | jq .scripts.test", nil),
            ("git commit -F - <<'EOF'\nmake test passes again\n\nCo-Authored-By: x\nEOF", nil),
            ("git commit -m \"$(cat <<'EOF'\nFix: pytest runs in CI\nEOF\n)\"", nil),
            ("cat > /tmp/run.sh <<EOF\nnpm test\nEOF\nchmod +x /tmp/run.sh", nil),
            ("command -v pytest", nil), ("command -v make >/dev/null || brew install make", nil), ("type jest", nil),
            ("hash tsc", nil), ("for f in *.test.js; do echo $f; done", nil), ("docker compose up -d", nil),
            ("if grep -q 'make test' Makefile; then echo yes; fi", nil),
        ]
        for (command, topic) in cases {
            XCTAssertEqual(Topic.tag(command: command), topic, command)
        }
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["grep", "-rn", "make test", "docs"]]), nil)
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["zsh", "-c", "npm run build"]]), "build")
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["bash", "--noprofile", "--norc", "-c", "cargo test"]]), "tests")
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

    /// ADAPTERS.md §2 and ARCHITECTURE.md §9: the hook gives up if the app
    /// is slow to accept, and connecting and writing share one 50 ms budget,
    /// so the write never starts a fresh one.
    func testConnectingAndWritingShareOneDeadline() throws {
        // An app that listens but never reads: a big line fills the socket
        // buffer, so the write has to wait for room.
        let path = "/tmp/boop-slow-\(getpid()).sock"
        unlink(path)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(server, 0)
        defer {
            close(server)
            unlink(path)
        }
        var address = try XCTUnwrap(HookSocket.unixAddress(path))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(server, 8), 0)
        let big = Data(count: 1 << 20)

        // A budget already spent (on connecting) leaves the write none.
        var start = Date()
        XCTAssertFalse(HookSocket.send(big, to: path, deadline: DispatchTime.now().uptimeNanoseconds))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.045, "no fresh 50 ms for the write")

        // The whole send gives up within its budget, give or take scheduling.
        start = Date()
        XCTAssertFalse(HookSocket.send(big, to: path, timeoutMs: 50))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)

        // A line that fits goes straight through, with time to spare.
        XCTAssertTrue(HookSocket.send(Data("x\n".utf8), to: path))
    }

    func testDefaultSocketPath() {
        XCTAssertEqual(HookSocket.defaultPath(environment: ["HOME": "/Users/x"]),
                       "/Users/x/Library/Application Support/Boop/boop.sock")
        XCTAssertEqual(HookSocket.defaultPath(environment: ["HOME": "/Users/x", "BOOP_SOCKET": "/tmp/b.sock"]), "/tmp/b.sock")
    }
}
