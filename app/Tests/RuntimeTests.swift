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

        // The menu bar sees the mic on, and a dropped link turns it off.
        var shown: [Bool] = []
        var sessions: [SessionSummary] = []
        runtime.home.sync {
            runtime.onChange = {
                shown.append($0.listening)
                sessions = $0.sessions
            }
        }
        transport.onLine?(#"{"t":"input","k":"talk_on"}"#)
        wait("listening shows") { runtime.home.sync { heard.count == 3 && shown.last == true } }
        transport.onConnection?(false)
        wait("mic off when the link drops") { runtime.home.sync { heard } == [true, false, true, false] }
        XCTAssertEqual(runtime.home.sync { shown.last }, false)
        XCTAssertEqual(runtime.home.sync { sessions }, [SessionSummary(agent: "claude", project: "jetpack", status: .waiting)],
                       "the popover's list comes with the status, not the state")
        XCTAssertFalse(transport.sent.contains { $0.contains("threads") })
        transport.onConnection?(true)

        // The Talk button: the device shows listening, then thinking.
        runtime.setListening(true)
        wait("listening on the device") { transport.sent.contains { $0.contains("\"anim\":\"listening\"") } }
        runtime.setListening(false)
        wait("thinking on the device") { transport.sent.contains { $0.contains("\"anim\":\"thinking\"") } }
        XCTAssertEqual(runtime.home.sync { heard }, [true, false, true, false, true, false])

        // A finished turn clears "needs you" and cheers.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("cheer") { transport.sent.contains { $0 == #"{"t":"moment","anim":"cheer","ttl":5}"# } }
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
        // The rules brain answers "shut up" with quiet.
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
    }

    /// Settings saved before the cut (2026-09-26) carry focus, away and the
    /// record. They still load, those keys are ignored, and the next save
    /// drops them.
    func testSettingsFromBeforeTheCutStillLoad() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        let old = #"{"awaySince":"2026-09-20","away":true,"brain":"rules","finished":148,"focus":true,"projects":["jetpack","landing"],"volume":3}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        XCTAssertEqual(AppSettings.load(from: dir).brain, "rules")
        XCTAssertEqual(AppSettings.load(from: dir).volume, 3)

        let transport = FakeTransport()
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: "")
        options.brain = "rules"
        let runtime = try Runtime(options)
        XCTAssertEqual(runtime.core.snapshot(at: 0).vol, 3)
        XCTAssertTrue(runtime.home.sync { runtime.core.canMumble(at: 0) }, "focus is gone: mumbles aren't held back")
        runtime.setVolume(4)
        runtime.home.sync {}
        let saved = try String(contentsOf: dir.appendingPathComponent(AppSettings.file), encoding: .utf8)
        let keys = try JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: AnyHashable]
        XCTAssertEqual(keys, ["brain": "rules", "volume": 4])
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// the rules cheer at once, and the brain's mumble waits until the cheer
    /// has played instead of cutting it off (BEHAVIORS.md §3).
    func testTheBrainWaitsForTheRulesMoment() throws {
        let transport = FakeTransport()
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: try String(contentsOf: Self.steering, encoding: .utf8))
        options.brain = "rules"
        options.devLines = true
        let skew = NSLock()
        nonisolated(unsafe) var skewMs: Int64 = 0
        options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.withLock { skewMs } }
        options.advance = { ms in skew.withLock { skewMs += ms } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)

        let socket = dir.appendingPathComponent("boop.sock").path
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socket))
        wait("working") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":400000}"#.utf8), to: socket))
        wait("clock moved") { skew.withLock { skewMs } == 400_000 }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("cheer") { transport.sent.contains { $0.contains("\"anim\":\"cheer\"") } }
        let cheered = Date()
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        let afterCheer = moments().count
        wait("the brain's mumble", timeout: 4) { moments().count > afterCheer }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(cheered), 1.5, "a cheer plays 2 s")
        let mumble = try XCTUnwrap(moments().last)
        XCTAssertTrue(mumble.hasPrefix(#"{"t":"moment","say":"#), "a mumble has no anim: \(mumble)")
    }

    /// ARCHITECTURE.md §3: the app knows how long each rule moment plays on
    /// the device. The numbers are firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play`, and firmware/src/render/anim.cpp's
    /// `animDuration` (BEHAVIORS.md §5: a cheer is 2 s).
    func testMomentLengthsFollowTheFirmware() {
        XCTAssertEqual(DeviceMoment(anim: "cheer").playMs, 2000)
        XCTAssertEqual(DeviceMoment(anim: "nod").playMs, 600)
        XCTAssertEqual(DeviceMoment(anim: "wiggle").playMs, 700)
        XCTAssertEqual(DeviceMoment(anim: "shrug").playMs, 1200)
        XCTAssertEqual(DeviceMoment(anim: "thinking").playMs, 0, "the brain's reply replaces thinking")
        XCTAssertEqual(DeviceMoment(anim: "listening").playMs, 0)

        // A mumble lasts its syllables plus two beats for a word, at 60–400
        // ms a beat, then 1.2 s of bubble, when that's longer than the face.
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(say: line).playMs, 1920)
        XCTAssertEqual(DeviceMoment(anim: "nod", say: line).playMs, 1920)
        var plain = line
        plain.word = nil
        XCTAssertEqual(DeviceMoment(say: plain).playMs, 1680)
        var slow = line
        slow.ms = 500
        XCTAssertEqual(DeviceMoment(say: slow).playMs, 3600)
        var quick = line
        quick.ms = 20
        XCTAssertEqual(DeviceMoment(say: quick).playMs, 1560, "6 × 60 + 1200")
        XCTAssertEqual(DeviceMoment(anim: "cheer", say: quick).playMs, 2000, "the cheer is longer")
    }
}
