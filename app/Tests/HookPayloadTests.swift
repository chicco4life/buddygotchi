import Foundation
import XCTest
@testable import BoopCore

final class HookPayloadTests: XCTestCase {
    @MainActor private func forwarded(_ body: [String: Any], forbidPython: Bool = false, source: String = "claude-code", approvalMode: Bool = false, codexApprovalMode: Bool = false) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent(".boop")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try JSONSerialization.data(withJSONObject: ["port": 21321, "token": "test", "approvalMode": approvalMode, "codexApprovalMode": codexApprovalMode]).write(to: config.appendingPathComponent("config.json"))
        let hook = root.appendingPathComponent("hook.sh")
        try HookInstaller.hookScriptContent.write(to: hook, atomically: true, encoding: .utf8)
        let curl = root.appendingPathComponent("curl")
        try "#!/bin/bash\nwhile [ $# -gt 0 ]; do if [ \"$1\" = -d ]; then printf '%s' \"$2\"; exit 0; fi; shift; done\n".write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        if forbidPython {
            let python = root.appendingPathComponent("python3")
            try "#!/bin/bash\necho PYTHON_MUST_NOT_RUN\nexit 99\n".write(to: python, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        }
        let syntax = Process(); syntax.executableURL = URL(fileURLWithPath: "/bin/bash"); syntax.arguments = ["-n", hook.path]
        try syntax.run(); syntax.waitUntilExit(); XCTAssertEqual(syntax.terminationStatus, 0)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [hook.path, source]
        var env = ProcessInfo.processInfo.environment; env["HOME"] = root.path; env["PATH"] = root.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: body))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return data
    }
    @MainActor func testV6ForwardsFullInput() throws {
        let input = ["command": String(repeating: "x", count: 9000), "other": "kept"]
        let data = try forwarded(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash", "tool_input": input])
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(d["tool_input"] as? [String: String], input)
        XCTAssertLessThanOrEqual(data.count, 16 * 1024)
    }
    @MainActor func testV6OutputEndsAndClosingCap() throws {
        let output = "HEAD" + String(repeating: "한", count: 4000) + "TAIL"
        let data = try forwarded(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash", "tool_response": ["exit_code": 1, "stdout": output]])
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(d["exit_code"]) // Transport does not normalize nested metadata.
        let payload = try XCTUnwrap(RawHookPayload.parse(data, source: "claude-code", at: 0))
        XCTAssertEqual(payload.exitStatus, 1)
        XCTAssertTrue((d["output_head"] as? String ?? "").contains("HEAD"))
        XCTAssertTrue((d["output_tail"] as? String ?? "").contains("TAIL"))
        XCTAssertLessThanOrEqual((d["output_head"] as? String ?? "").utf8.count, 1024)
        let closing = try forwarded(["hook_event_name": "Stop", "last_assistant_message": output])
        let c = try XCTUnwrap(JSONSerialization.jsonObject(with: closing) as? [String: Any])
        XCTAssertLessThanOrEqual((c["last_assistant_message"] as? String ?? "").utf8.count, 2048)
    }
    @MainActor func testV6OversizedBodyStaysValidAndDropsTailsFirst() throws {
        let data = try forwarded(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash", "message": String(repeating: "x", count: 15_000), "output": String(repeating: "y", count: 5000)])
        XCTAssertLessThanOrEqual(data.count, 16 * 1024)
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(d["output_head"]); XCTAssertNil(d["output_tail"])
        XCTAssertEqual((d["message"] as? String)?.count, 15_000)
        let huge = try forwarded(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash", "tool_input": ["command": String(repeating: "z", count: 100_000)]])
        XCTAssertLessThanOrEqual(huge.count, 16 * 1024)
        let p = try XCTUnwrap(RawHookPayload.parse(huge, source: "claude-code", at: 0))
        XCTAssertEqual(p.kind, .toolCall); XCTAssertNil(p.toolInput)
    }
}

extension HookPayloadTests {
    @MainActor func testCodexNativeApprovalsAreNotInterceptedByGlobalMode() throws {
        let request: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "s", "tool_name": "Bash", "tool_input": ["command": "swift test"]]
        for global in [false, true] {
            try XCTAssertTrue(try forwarded(request, source: "codex", approvalMode: global).isEmpty)
        }
        try XCTAssertFalse(try forwarded(request, source: "codex", approvalMode: true, codexApprovalMode: true).isEmpty)
        try XCTAssertFalse(try forwarded(["hook_event_name": "PreToolUse", "session_id": "s"], source: "codex", approvalMode: true).isEmpty)
        try XCTAssertFalse(try forwarded(request, source: "claude-code", approvalMode: true).isEmpty)
    }

    @MainActor func testTransportPreservesAliasesAndCallIdentity() throws {
        let data = try forwarded(["hookEventName": "postToolUse", "conversation_id": "cursor-s",
                                  "tool": ["name": "Shell"], "input": ["command": "swift test"],
                                  "tool_call_id": "call-42", "exit_code": 1, "error_class": "test_failure"])
        let payload = try XCTUnwrap(RawHookPayload.parse(data, source: "cursor", at: 0))
        XCTAssertEqual(payload.kind, .toolResult)
        XCTAssertEqual(payload.sessionId, "cursor-s")
        XCTAssertEqual(payload.toolName, "Shell")
        XCTAssertEqual(payload.callId, "call-42")
        XCTAssertEqual(payload.errorClass, "test_failure")
        XCTAssertEqual(payload.exitStatus, 1)
        XCTAssertNotNil(payload.toolInput)
        let codex = try forwarded(["hook_event_name": "PostToolUse", "session_id": "codex-s",
                                   "tool_name": "Bash", "tool_use_id": "call-99", "tool_response": "done"])
        try XCTAssertEqual(try RawHookPayload.parse(codex, source: "codex", at: 0)?.callId, "call-99")
    }

    func testApprovalDescriptionIsDisplayOnly() throws {
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean build artifacts"}}"#
        let body = try JSONDecoder().decode(HookEventBody.self, from: Data(json.utf8))
        let payload = try XCTUnwrap(RawHookPayload.parse(Data(json.utf8), source: "codex", at: 0))
        XCTAssertEqual(payload.displayHint, "Clean build artifacts")
        XCTAssertEqual(approvalGloss(from: body, fallback: "runs a command"), "Clean build artifacts")
        XCTAssertEqual(approvalOperation(from: body), "rm -rf build")
        XCTAssertNil(shouldAutoApprove(tool: "Shell", command: approvalOperation(from: body), source: "cursor"))
        XCTAssertTrue(payload.toolInput?.contains("rm -rf") == true)
        XCTAssertEqual(StakesReader.read(tool: "Bash", input: payload.toolInput ?? "").0, .careful)
    }

    @MainActor func testFastEventsNeverForkPython() throws {
        for event in ["PreToolUse", "preToolUse", "beforeShellExecution", "beforeMCPExecution", "SessionStart", "SessionEnd", "Notification", "PermissionRequest"] {
            for size in [10, 20_000] {
                let data = try forwarded(["hook_event_name": event, "session_id": "s", "tool_input": ["command": String(repeating: "한", count: size)]], forbidPython: true)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(body["hook_event_name"] as? String, event)
                XCTAssertEqual(body["session_id"] as? String, "s")
                XCTAssertLessThanOrEqual(data.count, 16384)
            }
        }
    }
    func testRawAndV5ShapesNormalizeAndCursorEditIsCall() throws {
        let cases = [
            (#"{"hookEventName":"beforeShellExecution","conversation_id":"s","command":"pytest","workspace_roots":["/tmp/p"]}"#, RawHookPayload.Kind.toolCall, "Shell"),
            (#"{"event_name":"afterFileEdit","conversation_id":"s","file_path":"/tmp/p/main.swift"}"#, .toolCall, "Edit"),
            (#"{"hook_event_name":"afterFileEdit","session_id":"s","tool_name":"Edit","tool_input":{"file_path":"main.swift"}}"#, .toolCall, "Edit"),
            (#"{"hook_event_name":"postToolUse","session_id":"s","tool":{"name":"Bash"},"input":{"command":"pytest"},"exit_status":0,"output_head":"pass","output_tail":"pass"}"#, .toolResult, "Bash")
        ]
        for (json, kind, tool) in cases {
            let p = try XCTUnwrap(RawHookPayload.parse(Data(json.utf8), source: "cursor", at: 0))
            XCTAssertEqual(p.kind, kind); XCTAssertEqual(p.toolName, tool); XCTAssertEqual(p.sessionId, "s")
            XCTAssertNotNil(p.toolInput)
        }
    }
}

extension HookPayloadTests {
    @MainActor func testV7ForwardsOnlyNumericUsage() throws {
        let claude = try forwarded(["hook_event_name":"Stop","session_id":"s","usage":["output_tokens":125000,"private":"PRIVATE_USAGE"]])
        let p = try XCTUnwrap(RawHookPayload.parse(claude,source:"claude-code",at:0))
        XCTAssertEqual(p.outputTokens,125000)
        XCTAssertFalse(String(decoding:claude,as:UTF8.self).contains("PRIVATE_USAGE"))
        let codex = try forwarded(["hook_event_name":"Stop","session_id":"s","info":["total_token_usage":["output_tokens":225000]]])
        let c = try XCTUnwrap(RawHookPayload.parse(codex,source:"codex",at:0))
        XCTAssertEqual(c.outputTokens,225000); XCTAssertTrue(c.cumulativeTokens)
        let message: [String: Any] = ["hook_event_name":"Stop","session_id":"s","message":["usage":["output_tokens":100000],"content":"PRIVATE_TRANSCRIPT"]]
        let raw = try XCTUnwrap(RawHookPayload.parse(JSONSerialization.data(withJSONObject:message),source:"claude-code",at:0))
        XCTAssertEqual(raw.outputTokens,100000)
        let forwardedMessage = try forwarded(message)
        let parsed = try XCTUnwrap(RawHookPayload.parse(forwardedMessage,source:"claude-code",at:0))
        XCTAssertEqual(parsed.outputTokens,100000)
        XCTAssertFalse(String(decoding:forwardedMessage,as:UTF8.self).contains("PRIVATE_TRANSCRIPT"))
    }
}
