import Foundation
import XCTest
@testable import BoopCore

final class HookPayloadTests: XCTestCase {
    @MainActor private func forwarded(_ body: [String: Any]) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent(".boop")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"port":21321,"token":"test"}"#.utf8).write(to: config.appendingPathComponent("config.json"))
        let hook = root.appendingPathComponent("hook.sh")
        try HookInstaller.hookScriptContent.write(to: hook, atomically: true, encoding: .utf8)
        let curl = root.appendingPathComponent("curl")
        try "#!/bin/bash\nwhile [ $# -gt 0 ]; do if [ \"$1\" = -d ]; then printf '%s' \"$2\"; exit 0; fi; shift; done\n".write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [hook.path]
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
    @MainActor func testV5ForwardsFullInput() throws {
        let input = ["command": String(repeating: "x", count: 9000), "other": "kept"]
        let data = try forwarded(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash", "tool_input": input])
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(d["tool_input"] as? [String: String], input)
        XCTAssertLessThanOrEqual(data.count, 16 * 1024)
    }
    @MainActor func testV5OutputEndsAndClosingCap() throws {
        let output = "HEAD" + String(repeating: "한", count: 4000) + "TAIL"
        let data = try forwarded(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash", "tool_response": ["exit_code": 1, "stdout": output]])
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(d["exit_code"] as? Int, 1)
        XCTAssertTrue((d["output_head"] as? String ?? "").contains("HEAD"))
        XCTAssertTrue((d["output_tail"] as? String ?? "").contains("TAIL"))
        XCTAssertLessThanOrEqual((d["output_head"] as? String ?? "").utf8.count, 1024)
        let closing = try forwarded(["hook_event_name": "Stop", "last_assistant_message": output])
        let c = try XCTUnwrap(JSONSerialization.jsonObject(with: closing) as? [String: Any])
        XCTAssertLessThanOrEqual((c["closing_message"] as? String ?? "").utf8.count, 2048)
    }
    @MainActor func testV5OversizedBodyStaysValidAndDropsTailsFirst() throws {
        let data = try forwarded(["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "Bash", "message": String(repeating: "x", count: 15_000), "output": String(repeating: "y", count: 5000)])
        XCTAssertLessThanOrEqual(data.count, 16 * 1024)
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(d["output_head"]); XCTAssertNil(d["output_tail"])
        XCTAssertEqual((d["message"] as? String)?.count, 15_000)
        let huge = try forwarded(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash", "tool_input": ["command": String(repeating: "z", count: 100_000)]])
        XCTAssertLessThanOrEqual(huge.count, 16 * 1024)
        let p = try XCTUnwrap(RawHookPayload.claudeCode(huge, at: 0))
        XCTAssertEqual(p.kind, .toolCall); XCTAssertNil(p.toolInput)
    }
}
