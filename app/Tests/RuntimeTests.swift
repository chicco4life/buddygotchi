import Foundation
import XCTest
@testable import BoopKit
@testable import HookWire

/// The runtime end to end in-process: real hook socket, real core, harness
/// with the rules classifier, no writer, and memory in a temporary state directory; a fake
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
        options.classifier = "rules"
        options.writer = "none"
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
        runtime.home.sync { runtime.onChange = { shown.append($0.listening) } }
        transport.onLine?(#"{"t":"input","k":"talk_on"}"#)
        wait("listening shows") { runtime.home.sync { heard.count == 3 && shown.last == true } }
        transport.onConnection?(false)
        wait("mic off when the link drops") { runtime.home.sync { heard } == [true, false, true, false] }
        XCTAssertEqual(runtime.home.sync { shown.last }, false)
        transport.onConnection?(true)

        // The Talk button: the device shows listening, then thinking.
        runtime.setListening(true)
        wait("listening on the device") { transport.sent.contains { $0.contains("\"anim\":\"listening\"") } }
        runtime.setListening(false)
        wait("thinking on the device") { transport.sent.contains { $0.contains("\"anim\":\"thinking\"") } }
        XCTAssertEqual(runtime.home.sync { heard }, [true, false, true, false, true, false])

        // A finished turn clears "needs you", cheers, and counts
        // in the record.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("cheer") { transport.sent.contains { $0.contains("\"anim\":\"cheer\"") } }
        wait("record") { AppSettings.load(from: self.dir).finished == 1 }
        XCTAssertEqual(AppSettings.load(from: dir).projects, ["jetpack"])
        XCTAssertEqual(AppSettings.load(from: dir).classifier, "rules")
        XCTAssertEqual(AppSettings.load(from: dir).writer, "apple", "--writer is for this run only")
        wait("today's short-term memory") {
            (try? String(contentsOf: self.dir.appendingPathComponent("short-term.md"), encoding: .utf8))?.contains("## Today") == true
        }
    }

    func testTalkFromTheDevLineReachesTheBrain() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        let socket = dir.appendingPathComponent("boop.sock").path
        func talk(_ words: String, yelled: Bool = false) throws {
            var data = try JSONSerialization.data(withJSONObject: ["dev": "talk", "words": words, "yelled": yelled] as [String: Any])
            data.append(0x0A)
            XCTAssertTrue(HookSocket.send(data, to: socket))
        }
        func quiet(_ line: String) -> Bool { line.contains("\"t\":\"state\"") && !line.contains("\"quiet\":0") }
        // BEHAVIORS.md §3.3: told off, the rules classifier has Boop mumble
        // something sad, and it doesn't quiet Boop.
        try talk("shut up")
        wait("a sad mumble") { transport.sent.contains { $0.contains("\"anim\":\"worried\"") && $0.contains("\"say\"") } }
        XCTAssertFalse(transport.sent.contains(where: quiet))
        // "be quiet" zips Boop's mouth and quiets it.
        try talk("be quiet")
        wait("quiet in the next state") { transport.sent.contains(where: quiet) }
        XCTAssertTrue(transport.sent.contains { $0.contains("\"anim\":\"zip\"") })
        // Yelled at while quiet: the sad face without a mumble, once the zip is over.
        let before = transport.sent.count
        try talk("", yelled: true)
        wait("a sad face") { transport.sent.dropFirst(before).contains { $0.contains("\"anim\":\"worried\"") && !$0.contains("\"say\"") } }
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
        XCTAssertEqual([settings.classifier, settings.writer], ["rules", "none"], "rules only wrote nothing")
        XCTAssertEqual(settings.volume, 6)
        XCTAssertEqual(settings.finished, 0)
        XCTAssertFalse(settings.away)
        XCTAssertNil(settings.awaySince)
    }

    /// HARNESS.md §6: the old one `brain` setting becomes the two stages;
    /// Apple's model and Jev keep Apple's model for the words.
    func testTheOldBrainSettingBecomesTwo() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases = [(#"{"brain":"apple"}"#, "rules", "apple"), (#"{"brain":"jev"}"#, "jev", "apple"),
                     (#"{"brain":"cloud:x"}"#, "rules", "apple"), (#"{}"#, "rules", "apple"),
                     (#"{"brain":"jev","classifier":"rules","writer":"none"}"#, "rules", "none")]
        for (json, classifier, writer) in cases {
            try Data(json.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
            let settings = AppSettings.load(from: dir)
            XCTAssertEqual([settings.classifier, settings.writer], [classifier, writer], json)
        }
        var saved = AppSettings.load(from: dir)
        saved.classifier = "jev"
        try saved.save(to: dir)
        let text = try String(contentsOf: dir.appendingPathComponent(AppSettings.file), encoding: .utf8)
        XCTAssertFalse(text.contains("\"brain\""), "the old key isn't written back")
        XCTAssertEqual(AppSettings.load(from: dir).classifier, "jev")
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// the rules cheer at size 2 at once, and the brain's moment waits until
    /// the cheer has played instead of cutting it off.
    func testTheBrainWaitsForTheRulesMoment() throws {
        let transport = FakeTransport()
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: try String(contentsOf: Self.steering, encoding: .utf8))
        options.classifier = "rules"
        options.writer = "none"
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
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":30000}"#.utf8), to: socket))
        wait("clock moved") { skew.withLock { skewMs } == 30_000 }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("size 2 cheer") { transport.sent.contains { $0.contains("\"anim\":\"cheer\",\"size\":2") } }
        let cheered = Date()
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        let afterCheer = moments().count
        wait("the brain's moment", timeout: 4) { moments().count > afterCheer }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(cheered), 1.5,
                                    "a size-2 cheer plays 2400 ms × 100 ÷ pace, about 2.4 s after a long win")
    }

    /// ARCHITECTURE.md §3: the app knows how long each rule moment plays on
    /// the device. The numbers are firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play`, and firmware/src/render/anim.cpp's
    /// `animDuration`, with the mood from the last `state`.
    func testMomentLengthsFollowTheFirmware() {
        let neutral = Mood()
        XCTAssertEqual(DeviceMoment(anim: "cheer", size: 2).playMs(mood: neutral), 2400)
        XCTAssertEqual(DeviceMoment(anim: "proud").playMs(mood: neutral), 2500)
        XCTAssertEqual(DeviceMoment(anim: "thinking").playMs(mood: neutral), 0, "the brain's reply replaces thinking")

        // Pace scales every animation by 100 ÷ pace, held to 70–140, rounded down.
        let oops = DeviceMoment(anim: "oops")
        XCTAssertEqual(oops.playMs(mood: Mood(pace: 70)), 2000)
        XCTAssertEqual(oops.playMs(mood: Mood(pace: 100)), 1400)
        XCTAssertEqual(oops.playMs(mood: Mood(pace: 140)), 1000)
        XCTAssertEqual(oops.playMs(mood: Mood(pace: 20)), 2000)
        XCTAssertEqual(oops.playMs(mood: Mood(pace: 200)), 1000)
        XCTAssertEqual(DeviceMoment(anim: "nod").playMs(mood: Mood(pace: 89)), 674)

        // A tired cheer (energy under 60) is a size smaller, a bouncy one
        // (140 or more) a size bigger, within 1–3.
        let cheer = DeviceMoment(anim: "cheer", size: 2)
        XCTAssertEqual(cheer.playMs(mood: Mood(energy: 59)), 2000)
        XCTAssertEqual(cheer.playMs(mood: Mood(energy: 60)), 2400)
        XCTAssertEqual(cheer.playMs(mood: Mood(energy: 140)), 2800)
        XCTAssertEqual(DeviceMoment(anim: "cheer", size: 1).playMs(mood: Mood(energy: 30)), 2000)
        XCTAssertEqual(DeviceMoment(anim: "cheer", size: 3).playMs(mood: Mood(energy: 180)), 2800)
        XCTAssertEqual(cheer.playMs(mood: Mood(energy: 150, pace: 140)), 2000, "bigger, and faster")
        XCTAssertEqual(DeviceMoment(anim: "oops").playMs(mood: Mood(energy: 30)), 1400, "only a cheer changes size")

        // A mumble lasts its syllables plus two beats for a word, at 60–400
        // ms a beat, then 1.2 s of bubble, when that's longer than the face.
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(anim: "nod", say: line).playMs(mood: neutral), 1920)
        var plain = line
        plain.word = nil
        XCTAssertEqual(DeviceMoment(anim: "nod", say: plain).playMs(mood: neutral), 1680)
        var slow = line
        slow.ms = 500
        XCTAssertEqual(DeviceMoment(anim: "happy", say: slow).playMs(mood: neutral), 3600)
        var quick = line
        quick.ms = 20
        XCTAssertEqual(DeviceMoment(anim: "happy", say: quick).playMs(mood: neutral), 2500, "6 × 60 + 1200 is shorter")
        XCTAssertEqual(DeviceMoment(anim: "happy", say: line).playMs(mood: Mood(pace: 70)), 3571, "the slow face is longer")
    }

    /// BEHAVIORS.md §4: "I'm away" pauses hunger, and settings keep the day
    /// it started, so a restart doesn't start the pause again. An older
    /// settings file without that day starts it on launch and saves it.
    func testAwayKeepsItsFirstDayAcrossARestart() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        try Data(#"{"brain":"rules","away":true}"#.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        let skew = NSLock()
        nonisolated(unsafe) var skewMs: Int64 = 0
        let dir = self.dir!
        func openRuntime() throws -> Runtime {
            var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                          link: FakeTransport(), steering: "")
            options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.withLock { skewMs } }
            return try Runtime(options)
        }
        let since: String?
        do {
            let first = try openRuntime()
            since = first.home.sync { first.core.awaySince }
            XCTAssertNotNil(since)
            XCTAssertEqual(AppSettings.load(from: dir).awaySince, since, "saved on launch")
        }

        skew.withLock { skewMs = 3 * 24 * 3600 * 1000 }
        let second = try openRuntime()
        XCTAssertEqual(second.home.sync { second.core.awaySince }, since, "three days later it still started then")
        second.setAway(false)
        second.home.sync {}
        XCTAssertFalse(AppSettings.load(from: dir).away)
        XCTAssertNil(AppSettings.load(from: dir).awaySince)
        second.setAway(true)
        second.home.sync {}
        XCTAssertEqual(AppSettings.load(from: dir).awaySince, second.home.sync { second.core.awaySince })
        XCTAssertNotEqual(AppSettings.load(from: dir).awaySince, since)
    }
}
