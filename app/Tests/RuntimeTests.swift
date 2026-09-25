import Foundation
import XCTest
@testable import BoopKit
@testable import HookWire

/// The runtime end to end in-process: real hook socket, real core, harness
/// with the rules brain and memory in a temporary state directory; a fake
/// device.
final class RuntimeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-rt-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    static let steering = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../plan/steering.md")

    func makeRuntime(_ transport: FakeTransport) throws -> Runtime {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: try String(contentsOf: Self.steering, encoding: .utf8))
        options.brain = "rules"
        options.devLines = true
        return try Runtime(options)
    }

    func wait(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(condition(), what)
    }

    func hook(_ hook: String, tool: String? = nil) -> Data {
        HookLine(agent: "claude", hook: hook, session: "s1", cwd: "/tmp/jetpack", tool: tool,
                 ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded()
    }

    func testHooksReachTheDeviceAndInputsComeBack() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        wait("first state on start") { transport.types().contains("state") }
        transport.onConnection?(true)

        let socket = dir.appendingPathComponent("boop.sock").path
        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socket))
        wait("working state") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        XCTAssertTrue(HookSocket.send(hook("PermissionRequest", tool: "Bash"), to: socket))
        wait("needs you") { transport.sent.contains { $0.contains("\"attn\":{\"agent\":\"claude\",\"project\":\"jetpack\"") } }

        // The device's status gets a state back.
        let before = transport.types().filter { $0 == "state" }.count
        transport.onLine?(#"{"t":"status","v":1,"id":"b00p-54fe","fw":"1.0.0","bat":0,"usb":1}"#)
        wait("state after status") { transport.types().filter { $0 == "state" }.count > before }
        XCTAssertEqual(runtime.home.sync { runtime.link.status?.id }, "b00p-54fe")

        // Push-to-talk reaches the Mac's listener.
        var heard: [Bool] = []
        runtime.home.sync { runtime.onListen = { heard.append($0) } }
        transport.onLine?(#"{"t":"input","k":"talk_on"}"#)
        transport.onLine?(#"{"t":"input","k":"talk_off"}"#)
        wait("listen on and off") { runtime.home.sync { heard } == [true, false] }

        // A finished turn clears "needs you", nods (it was quick), and counts
        // in the record.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("nod") { transport.sent.contains { $0.contains("\"anim\":\"nod\"") } }
        wait("record") { AppSettings.load(from: self.dir).finished == 1 }
        XCTAssertEqual(AppSettings.load(from: dir).projects, ["jetpack"])
        XCTAssertEqual(AppSettings.load(from: dir).brain, "apple", "--brain is for this run only")
        wait("today's short-term memory") {
            (try? String(contentsOf: self.dir.appendingPathComponent("short-term.md"), encoding: .utf8))?.contains("## Today") == true
        }
    }

    func testTalkFromTheDevLineReachesTheBrain() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        var data = try JSONSerialization.data(withJSONObject: ["dev": "talk", "words": "shut up"])
        data.append(0x0A)
        XCTAssertTrue(HookSocket.send(data, to: dir.appendingPathComponent("boop.sock").path))
        // The rules brain answers "shut up" with a sulky face and quiet.
        wait("quiet in the next state") { transport.sent.contains { $0.contains("\"t\":\"state\"") && !$0.contains("\"quiet\":0") } }
    }

    func testStopRemovesTheSocketAndReleasesTheLock() throws {
        let runtime = try makeRuntime(FakeTransport())
        try runtime.start()
        let socket = dir.appendingPathComponent("boop.sock").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: socket))
        try XCTAssertThrowsError(try Runtime(runtime.options)) // one app per state directory
        runtime.stop()
        runtime.home.sync {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket))
        XCTAssertFalse(HookSocket.send(hook("Stop"), to: socket))
    }

    func testNotSetUpIsAnError() throws {
        let options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: nil, steering: "")
        try XCTAssertThrowsError(try Runtime(options)) { XCTAssertEqual("\($0)", "\(Runtime.OpenError.notSetUp)") }
    }

    func testTheBundledSteeringIsTheSpec() throws {
        let bundled = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Boop/Resources/steering.md")
        try XCTAssertEqual(try String(contentsOf: bundled, encoding: .utf8),
                       try String(contentsOf: Self.steering, encoding: .utf8),
                       "app/Boop/Resources/steering.md must be a copy of plan/steering.md")
    }

    func testSettingsLoadOlderFiles() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"brain":"rules"}"#.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        let settings = AppSettings.load(from: dir)
        XCTAssertEqual(settings.brain, "rules")
        XCTAssertEqual(settings.volume, 6)
        XCTAssertEqual(settings.finished, 0)
    }
}
