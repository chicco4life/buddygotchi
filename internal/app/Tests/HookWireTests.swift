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

    /// ADAPTERS.md §2: the app the agent runs in, from the hook's
    /// environment: a launched app's bundle ID, which its children keep;
    /// the Codex app's server marks itself instead; and the Claude app's
    /// own ID for the session. Nothing else of the environment leaves.
    func testTheHookSaysWhatAppTheAgentRunsIn() throws {
        let raw = payload(["hook_event_name": "Stop", "session_id": "s1"])
        func line(_ agent: String, _ env: [String: String]) throws -> HookLine {
            try XCTUnwrap(HookLine.extract(agent: agent, payload: raw, ts: 1, env: env))
        }
        let claude = try line("claude", ["__CFBundleIdentifier": "com.anthropic.claudefordesktop",
                                         "CLAUDE_CODE_HOST_SESSION_ID": "local_7db5", "HOME": "/Users/secret"])
        XCTAssertEqual(claude.app, HostApp.claude)
        XCTAssertEqual(claude.appSession, "local_7db5")
        let wire = String(decoding: claude.encoded(), as: UTF8.self)
        XCTAssertTrue(wire.contains(#""app_session":"local_7db5""#))
        XCTAssertFalse(wire.contains("secret"))
        XCTAssertEqual(HookLine.decode(claude.encoded()), claude)

        let terminal = try line("claude", ["__CFBundleIdentifier": "com.mitchellh.ghostty"])
        XCTAssertEqual(terminal.app, "com.mitchellh.ghostty")
        XCTAssertNil(terminal.appSession)
        try XCTAssertNil(line("claude", ["CLAUDE_CODE_HOST_SESSION_ID": "cse_1"]).appSession, "only the app's local IDs")
        try XCTAssertEqual(line("codex", ["CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "Codex"]).app, HostApp.codex)
        try XCTAssertEqual(line("codex", ["__CFBundleIdentifier": "com.googlecode.iterm2",
                                          "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "Codex"]).app, "com.googlecode.iterm2")
        try XCTAssertNil(line("codex", ["CLAUDE_CODE_HOST_SESSION_ID": "local_1"]).appSession, "Claude's alone")
        try XCTAssertNil(line("claude", [:]).app, "no environment, no app")
        // A payload too big to parse keeps them too.
        let cut = Data(#"{"hook_event_name":"Stop","session_id":"s1","x":"#.utf8)
        XCTAssertEqual(HookLine.extract(agent: "claude", payload: cut, ts: 1, env: ["__CFBundleIdentifier": "a.b"])?.app, "a.b")
    }

    /// ADAPTERS.md §2: every hook gets the thread's name: Claude's last
    /// title in the transcript, yours over its own, and Codex's from its
    /// session index. Nothing else of either file leaves.
    func testEveryHookGetsTheThreadsName() throws {
        let dir = tempDir("threadname")
        defer { try? FileManager.default.removeItem(at: dir) }
        func jsonl(_ rows: [[String: Any]]) -> Data {
            Data(rows.map { String(decoding: payload($0), as: UTF8.self) + "\n" }.joined().utf8)
        }
        let transcript = dir.appendingPathComponent("t.jsonl")
        try jsonl([
            ["type": "custom-title", "customTitle": "Old name", "sessionId": "s"],
            ["type": "user", "message": ["content": "SECRET prompt"]],
            ["type": "custom-title", "customTitle": "Thread name on \"needs you\" screen", "sessionId": "s"],
            ["type": "ai-title", "aiTitle": "Made-up name", "sessionId": "s"],
            ["type": "assistant", "message": ["content": "SECRET reply"]],
        ]).write(to: transcript)
        let names = ThreadName.Source(codexHome: dir.path)
        func ask(_ agent: String, _ hook: String, session: String = "s", _ extra: [String: Any] = [:]) -> HookLine? {
            var object: [String: Any] = ["hook_event_name": hook, "session_id": session,
                                         "transcript_path": transcript.path, "tool_name": "Bash"]
            object.merge(extra) { $1 }
            return HookLine.extract(agent: agent, payload: payload(object), ts: 1, names: names)
        }
        let line = try XCTUnwrap(ask("claude", "PermissionRequest"))
        XCTAssertEqual(line.name, "Thread name on \"needs you\" screen")
        let wire = String(decoding: line.encoded(), as: UTF8.self)
        XCTAssertFalse(wire.contains("SECRET"))
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
        XCTAssertEqual(ask("claude", "Notification", ["notification_type": "permission_prompt"])?.name,
                       "Thread name on \"needs you\" screen")
        for hook in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] {
            XCTAssertEqual(ask("claude", hook)?.name, "Thread name on \"needs you\" screen", hook)
        }
        XCTAssertNil(HookLine.extract(agent: "claude", payload: payload(["hook_event_name": "PermissionRequest",
                                                                         "session_id": "s", "transcript_path": transcript.path]),
                                      ts: 1)?.name, "nor without a source")

        // With no title of yours, Claude's own; with none at all, no name.
        try jsonl([["type": "ai-title", "aiTitle": "Made-up name"], ["type": "user"]]).write(to: transcript)
        XCTAssertEqual(ask("claude", "PermissionRequest")?.name, "Made-up name")
        try jsonl([["type": "user"]]).write(to: transcript)
        XCTAssertNil(ask("claude", "PermissionRequest")?.name)
        XCTAssertNil(ask("claude", "PermissionRequest", ["transcript_path": "/nowhere/t.jsonl"])?.name)

        // A title far back in a long transcript is still found.
        var long = jsonl([["type": "custom-title", "customTitle": "Far back"]])
        let filler = jsonl([["type": "assistant", "text": String(repeating: "x", count: 1000)]])
        for _ in 0..<400 { long.append(filler) }
        try long.write(to: transcript)
        XCTAssertEqual(ask("claude", "PermissionRequest")?.name, "Far back")
        XCTAssertEqual(ask("claude", "Stop")?.name, "Far back")
        XCTAssertNil(ask("claude", "PreToolUse")?.name, "a tool call's hook reads only the last 256 KB")

        try jsonl([
            ["id": "t1", "thread_name": "Old codex name"], ["id": "t2", "thread_name": "Another thread"],
            ["id": "t1", "thread_name": "Codex thread"],
        ]).write(to: dir.appendingPathComponent("session_index.jsonl"))
        XCTAssertEqual(ask("codex", "PermissionRequest", session: "t1")?.name, "Codex thread")
        XCTAssertEqual(ask("codex", "PreToolUse", session: "t1")?.name, "Codex thread")
        XCTAssertNil(ask("codex", "PermissionRequest", session: "t3")?.name)
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
    /// its class and whether you interrupted it.
    func testPostToolUseFailureKeepsOnlyWhetherYouInterruptedIt() throws {
        let failure = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "PostToolUseFailure", "session_id": "s", "tool_name": "Bash",
            "tool_input": ["command": "npm test"], "error": "PRIVATE Command exited with non-zero status code 1",
            "is_interrupt": false,
        ]), ts: 0))
        XCTAssertEqual(failure, HookLine(agent: "claude", hook: "PostToolUseFailure", session: "s", tool: "Bash", topic: "tests",
                                         toolError: "exit_code", ts: 0))
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

    /// ADAPTERS.md §2: from every recorded payload, the only words that
    /// reach the line are your prompt and the agent's last message: no
    /// tool input or output, error text or transcript.
    func testOnlyThePromptAndLastMessageFromAnyRecordedFixtureReachTheLine() throws {
        let files = FileManager.default.enumerator(at: HookWireTests.fixtures, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { ["json", "jsonl"].contains($0.pathExtension) }
        XCTAssertGreaterThan(files.count, 3)
        var lines = 0, words = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let payloads = file.pathExtension == "json" ? [text] : text.split(separator: "\n").map(String.init)
            for raw in payloads where !raw.isEmpty {
                guard var line = HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0) else { continue }
                lines += 1
                if line.prompt != nil || line.message != nil { words += 1 }
                line.prompt = nil
                line.message = nil
                XCTAssertFalse(String(decoding: line.encoded(), as: UTF8.self).contains("PRIVATE"), file.lastPathComponent)
            }
        }
        XCTAssertGreaterThan(lines, 40)
        XCTAssertGreaterThan(words, 5, "prompts and last messages do get through")
    }

    /// ADAPTERS.md §2: `UserPromptSubmit` keeps what you asked and `Stop`
    /// what the agent said last, each cut to 2,000 characters.
    func testThePromptAndLastMessageAreKept() throws {
        let prompt = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "UserPromptSubmit", "session_id": "s", "prompt": "fix the nav",
        ]), ts: 0))
        XCTAssertEqual(prompt.prompt, "fix the nav")
        XCTAssertEqual(HookLine.decode(prompt.encoded()), prompt)
        let long = String(repeating: "y", count: 3000)
        let stop = try XCTUnwrap(HookLine.extract(agent: "codex", payload: payload([
            "hook_event_name": "Stop", "session_id": "s", "last_assistant_message": long,
        ]), ts: 0))
        XCTAssertEqual(stop.message?.count, HookLine.maxMessage)
        XCTAssertEqual(HookLine.decode(stop.encoded()), stop)
    }

    /// ADAPTERS.md §2: a subagent's hooks carry the parent's session plus
    /// its `agent_id` and `agent_type`, which the line keeps (harness/EVENTS.md
    /// §3), the id even from a payload cut off at the cap.
    func testASubagentsIDIsKept() throws {
        let raw = payload([
            "hook_event_name": "PreToolUse", "session_id": "s1", "agent_id": "a1b2", "agent_type": "general-purpose",
            "tool_name": "Read", "tool_input": ["file_path": "/w/x.swift"],
        ])
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: raw, ts: 0))
        XCTAssertEqual(line.agentID, "a1b2")
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
        XCTAssertEqual(line.agentType, "general-purpose")
        let main = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload(["hook_event_name": "Stop", "session_id": "s1"]), ts: 0))
        XCTAssertNil(main.agentID)
        XCTAssertFalse(String(decoding: main.encoded(), as: UTF8.self).contains("agent_id"))
        let big = String(repeating: "x", count: 300_000)
        let cut = Data(#"{"session_id": "s1", "agent_id": "a1b2", "hook_event_name": "PostToolUse", "tool_name": "Read", "tool_response": "\#(big)"}"#.utf8).prefix(256 * 1024)
        XCTAssertEqual(HookLine.extract(agent: "claude", payload: Data(cut), ts: 0)?.agentID, "a1b2")
    }

    /// ADAPTERS.md §2: `SubagentStop` keeps which subagent ended, never its
    /// last message or transcript, and a payload cut off at the cap by a
    /// long last message still says which subagent.
    func testSubagentStopKeepsOnlyWhichSubagentEnded() throws {
        let raw = payload([
            "hook_event_name": "SubagentStop", "session_id": "s1", "cwd": "/w/landing", "stop_hook_active": false,
            "agent_id": "a1", "agent_type": "Explore", "agent_transcript_path": "/PRIVATE/agent-a1.jsonl",
            "last_assistant_message": "PRIVATE found 3 issues",
        ])
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: raw, ts: 3))
        XCTAssertEqual(line, HookLine(agent: "claude", hook: "SubagentStop", session: "s1", cwd: "/w/landing",
                                      agentType: "Explore", agentID: "a1", ts: 3))
        XCTAssertFalse(String(decoding: line.encoded(), as: UTF8.self).contains("PRIVATE"))
        let big = String(repeating: "x", count: 300_000)
        let cut = Data(#"{"session_id": "s1", "hook_event_name": "SubagentStop", "agent_id": "a1", "last_assistant_message": "\#(big)"}"#.utf8).prefix(256 * 1024)
        let salvaged = try XCTUnwrap(HookLine.extract(agent: "claude", payload: Data(cut), ts: 0))
        XCTAssertEqual(salvaged.hook, "SubagentStop")
        XCTAssertEqual(salvaged.agentID, "a1")
    }

    /// ADAPTERS.md §2: `SessionStart` keeps its `source`, and every hook
    /// its `permission_mode`, even from a payload cut off at the cap.
    func testSessionStartsSourceAndThePermissionModeAreKept() throws {
        for agent in ["claude-code", "codex"] {
            let raw = try Data(contentsOf: Self.fixtures.appendingPathComponent("\(agent)/2026-09-08/SessionStart-1.json"))
            let line = try XCTUnwrap(HookLine.extract(agent: agent == "codex" ? "codex" : "claude", payload: raw, ts: 1))
            XCTAssertEqual(line.source, "startup", agent)
            XCTAssertEqual(HookLine.decode(line.encoded()), line)
        }
        let raw = payload(["hook_event_name": "PreToolUse", "session_id": "s1", "permission_mode": "plan", "tool_name": "Read",
                           "tool_input": ["file_path": "/w/x.swift"], "source": "not a start"])
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: raw, ts: 1))
        XCTAssertEqual(line.mode, "plan")
        XCTAssertNil(line.source, "only a start has a source")
        XCTAssertTrue(String(decoding: line.encoded(), as: UTF8.self).contains(#""mode":"plan""#))
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
        let big = String(repeating: "x", count: 300_000)
        let cut = Data(#"{"session_id": "s1", "permission_mode": "plan", "hook_event_name": "PostToolUse", "tool_name": "Read", "tool_response": "\#(big)"}"#.utf8).prefix(256 * 1024)
        XCTAssertEqual(HookLine.extract(agent: "claude", payload: Data(cut), ts: 0)?.mode, "plan")
    }

    /// ADAPTERS.md §3: a shell command that only looks at files is
    /// `inspect`, so the look shows it as analyzing: every command in it
    /// reads (`rg`, `grep`, `cat`, `sed -n`, `find`, `ls`, `head`, `tail`,
    /// `wc`, `nl`, `sort`, `uniq`, `cut`) or neither reads nor changes
    /// anything (`cd`, `echo`), and none writes a file. A check comes first.
    func testShellReadsAreInspect() {
        let reads = [
            "rg -n 'func tick' app/", "grep -rn TODO .", "cat Package.swift", "sed -n '1,80p' app/Core.swift",
            "find . -name '*.swift'", "ls -la", "head -50 README.md", "tail -n 20 log.txt", "wc -l *.swift",
            "nl -ba app/Core.swift | sed -n '120,200p'", "cd app && rg -l Core", "cat a.md; echo ---; cat b.md",
            "rg foo 2>/dev/null | sort | uniq -c", "grep -n 'make test' Makefile", "ls node_modules/.bin/jest",
            "bash -lc 'rg -n foo src'", "sed -ne 's/a/b/p' x",
        ]
        for command in reads {
            XCTAssertTrue(Topic.inspects(command: command), command)
            XCTAssertEqual(Topic.tag(tool: "Bash", input: ["command": command]), "inspect", command)
        }
        let others = [
            "sed -i 's/a/b/' x", "sed 's/a/b/' x", "sed -n -i 's/a/b/p' x", "find . -name '*.o' -delete",
            "find . -exec rm {} \\;", "cat > /tmp/x.py <<'EOF'\nprint(1)\nEOF", "echo hi > notes.txt",
            "rg foo > out.txt", "cat a >> b", "ls && git status", "cd app", "echo hello", "git log | head",
            "cat x | python3 -c 'import sys'", "tee out.txt", "",
        ]
        for command in others { XCTAssertFalse(Topic.inspects(command: command), command) }
        XCTAssertEqual(Topic.tag(tool: "Bash", input: ["command": "swift test 2>&1 | tail -20"]), "tests", "a check first")
        XCTAssertEqual(Topic.tag(tool: "Bash", input: ["command": "make 2>&1 | grep -i error"]), "build")
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["bash", "-lc", "nl -ba x | sed -n '1,40p'"]]), "inspect",
                       "Codex's argv")
        XCTAssertEqual(Topic.tag(tool: "exec_command", input: ["cmd": "rg -n foo"]), "inspect")
        XCTAssertNil(Topic.tag(tool: "Read", input: ["file_path": "/w/x.swift"]), "a tool without a command")
        XCTAssertNil(Topic.tag(tool: "Edit", input: ["file_path": "/w/x.swift", "command": "cat x"]), "an edit is an edit")
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
        // An argv is one command already: its words are never split again.
        XCTAssertEqual(Topic.tag(tool: "container.exec", input: ["command": ["make", "test"]]), "tests")
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["echo", "make test && vercel"]]), nil)
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["sh", "-c", "cd app && make test"]]), "tests")
        XCTAssertEqual(Topic.tag(tool: "shell", input: [:]), nil)
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
        XCTAssertEqual(Topic.tag(tool: "shell", input: ["command": ["grep", "-rn", "make test", "docs"]]), "inspect",
                       "a search, not tests")
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

    /// harness/EVENTS.md §4: a tool error's text becomes one of four classes.
    func testToolErrorClasses() {
        XCTAssertEqual(ToolError.classify("Command exited with non-zero status code 1"), "exit_code")
        XCTAssertEqual(ToolError.classify("Command timed out after 2m"), "timeout")
        XCTAssertEqual(ToolError.classify("Permission to use Bash has been denied."), "denied")
        XCTAssertEqual(ToolError.classify("something odd"), "other")
        XCTAssertEqual(ToolError.classify(nil), "other")
    }

    /// The tool call's ID and a subagent's type are kept; they carry no content.
    func testKeepsTheToolUseIDAndAgentType() throws {
        let line = try XCTUnwrap(HookLine.extract(agent: "claude", payload: payload([
            "hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Read", "tool_use_id": "toolu_9",
            "agent_id": "a1", "agent_type": "Explore", "tool_input": ["file_path": "/PRIVATE"],
        ]), ts: 0))
        XCTAssertEqual(line.toolUseID, "toolu_9")
        XCTAssertEqual(line.agentType, "Explore")
        XCTAssertEqual(HookLine.decode(line.encoded()), line)
        XCTAssertFalse(String(decoding: line.encoded(), as: UTF8.self).contains("PRIVATE"))
    }
}
