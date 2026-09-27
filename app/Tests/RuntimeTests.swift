import Foundation
import XCTest
@testable import BoopKit
@testable import HookWire

/// The runtime end to end in-process: real hook socket, real core, harness
/// in chatty mode with no writer, and memory in a temporary state directory;
/// a fake device. Never normal mode, whose Jev key would come from the
/// Keychain.
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
        options.mode = .chatty
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

        // The Talk button: the device shows listening; the mic failing
        // ends it at once with the empty moment.
        runtime.setListening(true)
        wait("listening on the device") { transport.sent.contains { $0.contains("\"anim\":\"listening\"") } }
        runtime.setListening(false)
        wait("mic off") { runtime.home.sync { heard } == [true, false, true, false, true, false] }
        XCTAssertFalse(transport.sent.contains(#"{"t":"moment","ttl":5}"#), "the empty moment waits 8 s")
        runtime.setListening(true)
        runtime.micFailed()
        wait("the empty moment") { transport.sent.contains(#"{"t":"moment","ttl":5}"#) }

        // A finished turn clears "needs you" and cheers.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("cheer") { transport.sent.contains { $0 == #"{"t":"moment","anim":"cheer","ttl":5}"# } }
        XCTAssertEqual(AppSettings.load(from: dir).mode, .normal, "--mode is for this run only")
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
        // BEHAVIORS.md §3.3: told off, the chatty rules have Boop mumble
        // something sad (a mumble on its own: no face), and it doesn't quiet Boop.
        try talk("shut up")
        wait("a sad mumble") { transport.sent.contains { $0.contains("\"t\":\"moment\"") && $0.contains("\"say\"") && !$0.contains("\"anim\"") } }
        XCTAssertFalse(transport.sent.contains(where: quiet))
        // "be quiet" quiets it, with no zip: that animation is parked.
        try talk("be quiet")
        wait("quiet in the next state") { transport.sent.contains(where: quiet) }
        XCTAssertFalse(transport.sent.contains { $0.contains("\"anim\":\"zip\"") })
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

    /// Settings from before the modes and the 2026-09-26 cut still load, in
    /// normal mode; the keys that went are ignored and aren't written back.
    func testSettingsFromBeforeTheModesStartInNormal() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"{"brain":"jev","classifier":"rules","writer":"none","volume":3,"focus":true,"away":true,"awaySince":"2026-09-20","finished":148,"projects":["jetpack"]}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        let settings = AppSettings.load(from: dir)
        XCTAssertEqual(settings.mode, .normal)
        XCTAssertEqual(settings.volume, 3)
        try settings.save(to: dir)
        let text = try String(contentsOf: dir.appendingPathComponent(AppSettings.file), encoding: .utf8)
        for key in ["brain", "classifier", "writer", "focus", "away", "finished", "projects"] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    /// BEHAVIORS.md §6: the mode is saved; a missing or unknown one is normal.
    func testSettingsKeepTheMode() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, Mode)] = [(#"{"mode":"calm"}"#, .calm), (#"{"mode":"chatty","volume":2}"#, .chatty),
                                       (#"{"mode":"loud"}"#, .normal), (#"{}"#, .normal)]
        for (json, mode) in cases {
            try Data(json.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
            XCTAssertEqual(AppSettings.load(from: dir).mode, mode, json)
        }
        var saved = AppSettings()
        saved.mode = .calm
        try saved.save(to: dir)
        XCTAssertEqual(AppSettings.load(from: dir), saved)
    }

    /// BEHAVIORS.md §6: a new mode takes effect at once, brain included, and
    /// is saved.
    func testANewModeTakesEffectAtOnce() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        wait("started chatty") { runtime.home.sync { statuses.last?.classifier == "chatty@1" } }
        runtime.setMode(.calm)
        wait("calm now") { runtime.home.sync { statuses.last?.mode == .calm && statuses.last?.classifier == "calm@1" } }
        XCTAssertEqual(runtime.home.sync { runtime.core.config.mode }, .calm)
        XCTAssertEqual(AppSettings.load(from: dir).mode, .calm)
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// the rules cheer at once, and the brain's mumble waits until the cheer
    /// has played instead of cutting it off.
    func testTheBrainWaitsForTheRulesMoment() throws {
        let transport = FakeTransport()
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: try String(contentsOf: Self.steering, encoding: .utf8))
        options.mode = .chatty
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
        wait("cheer") { transport.sent.contains { $0.contains("\"anim\":\"cheer\"") } }
        let cheered = Date()
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        let afterCheer = moments().count
        wait("the brain's mumble", timeout: 4) { moments().count > afterCheer }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(cheered), 1.5, "a cheer plays 2 s")
        let mumble = try XCTUnwrap(moments().last)
        XCTAssertTrue(mumble.hasPrefix(#"{"t":"moment","say":"#), "a mumble has no anim: \(mumble)")
    }

    /// ARCHITECTURE.md §3.2: the brain's moments play one at a time, each
    /// after whatever is playing, so none cuts off a rule moment or another
    /// of the brain's; a newer rule moment pushes them back; one that waited
    /// past its ttl is dropped.
    func testBrainMomentsTakeTurns() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let mumble = DeviceMoment(say: line)  // 1920 ms
        var schedule = MomentSchedule()
        schedule.rule(DeviceMoment(anim: "cheer"), now: 0)
        schedule.brain(mumble, now: 100)
        schedule.brain(mumble, now: 200)
        var due = schedule.due(now: 500)
        XCTAssertNil(due.play, "the cheer is still playing")
        XCTAssertEqual(due.next, 2000)
        due = schedule.due(now: 2000)
        XCTAssertEqual(due.play, mumble, "the first, once the cheer is over")
        XCTAssertEqual(due.next, 3920, "the second waits for the first")
        XCTAssertNil(schedule.due(now: 3000).play)
        due = schedule.due(now: 3920)
        XCTAssertEqual(due.play, mumble, "then the second")
        XCTAssertNil(due.next, "nothing left")

        var pushed = MomentSchedule()
        pushed.rule(DeviceMoment(anim: "cheer"), now: 0)
        pushed.brain(mumble, now: 1000)
        pushed.rule(DeviceMoment(anim: "cheer"), now: 1500)  // a new finish
        XCTAssertNil(pushed.due(now: 2000).play, "pushed back by the rules")
        XCTAssertEqual(pushed.due(now: 2000).next, 3500)
        XCTAssertEqual(pushed.due(now: 3500).play, mumble)

        var late = MomentSchedule()
        late.rule(DeviceMoment(anim: "cheer"), now: 0)
        late.brain(mumble, now: 0)
        late.rule(DeviceMoment(anim: "cheer"), now: 1900)
        late.rule(DeviceMoment(anim: "cheer"), now: 3800)
        due = late.due(now: 5800)
        XCTAssertNil(due.play)
        XCTAssertEqual(due.dropped, [mumble], "5.8 s is past its 5 s ttl")
        XCTAssertNil(due.next)
    }

    /// BEHAVIORS.md §3.3: a "you said" pass that sends no mumble ends the
    /// device's `listening` face at once with the empty moment; one that
    /// mumbles leaves the reply to end it.
    func testNoReplyEndsListeningAtOnce() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        let empty = #"{"t":"moment","ttl":5}"#
        func holdBOOT() {
            transport.onLine?(#"{"t":"input","k":"talk_on"}"#)
            transport.onLine?(#"{"t":"input","k":"talk_off"}"#)
            wait("waiting for the reply") { runtime.home.sync { runtime.core.replyWait != nil } }
        }
        holdBOOT()
        runtime.talk("good job")
        wait("a mumble") { transport.sent.contains { $0.contains("\"say\"") } }
        runtime.home.sync {}
        XCTAssertFalse(transport.sent.contains(empty), "the reply ends it")
        holdBOOT()
        let asked = Date()
        runtime.talk("be quiet")
        wait("the empty moment", timeout: 2) { transport.sent.contains(empty) }
        XCTAssertLessThan(Date().timeIntervalSince(asked), 2, "not 8 s later")
    }

    /// BEHAVIORS.md §2: working chatter never cuts a moment that's playing,
    /// such as the brain's reply, or jumps one waiting its turn.
    func testChatterNeverCutsAMoment() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        let says = { transport.sent.filter { $0.contains("\"say\"") }.count }
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        runtime.home.sync {
            let now = runtime.options.clock()
            runtime.moments.schedule.brain(DeviceMoment(say: line), now: now)
            runtime.run([.mumble(feeling: "happy", word: nil)])
        }
        XCTAssertEqual(says(), 0, "a brain moment is waiting its turn")
        runtime.home.sync {
            let now = runtime.options.clock()
            _ = runtime.moments.schedule.due(now: now)
            XCTAssertFalse(runtime.moments.schedule.idle(now: now), "it's playing")
            runtime.run([.mumble(feeling: "happy", word: nil)])
        }
        XCTAssertEqual(says(), 0, "the reply is playing")
        runtime.home.sync {
            runtime.moments.schedule = MomentSchedule()
            runtime.run([.mumble(feeling: "happy", word: nil)])
        }
        XCTAssertEqual(says(), 1, "nothing playing: chatter plays")
    }

    /// BEHAVIORS.md §3.3: a brain mumble still waiting its turn when the mic
    /// goes on (here behind a cheer) is dropped: it can only be about an
    /// agent, and would end `listening` before the reply.
    func testMicOnDropsWaitingBrainMumbles() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        let says = { transport.sent.filter { $0.contains("\"say\"") }.count }
        runtime.home.sync {
            runtime.run([.moment(anim: "cheer")])
            runtime.react.run(ToolCall("react", ["feeling": .string("happy"), "voice": .string("mumble")]))
            XCTAssertEqual(runtime.moments.schedule.waiting.count, 1, "waiting behind the cheer")
            runtime.device(#"{"t":"input","k":"talk_on"}"#)
            XCTAssertTrue(runtime.moments.schedule.waiting.isEmpty, "the mic went on")
            let later = runtime.options.clock() + 3000
            Runtime.pump(runtime.moments, link: runtime.link, clock: { later }, home: runtime.home, log: { _ in })
        }
        XCTAssertEqual(says(), 0, "the cheer has played and nothing follows it")
    }

    /// ARCHITECTURE.md §3: the app knows how long each rule moment plays on
    /// the device. The numbers are firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play`, and firmware/src/render/anim.cpp's
    /// `animDuration` (BEHAVIORS.md §5: a cheer is 2 s).
    func testMomentLengthsFollowTheFirmware() {
        XCTAssertEqual(DeviceMoment(anim: "cheer").playMs, 2000)
        XCTAssertEqual(DeviceMoment(anim: "wiggle").playMs, 700)
        XCTAssertEqual(DeviceMoment(anim: "listening").playMs, 0, "the reply or the empty moment ends it")
        XCTAssertEqual(DeviceMoment.empty.playMs, 0)

        // A mumble lasts its syllables plus two beats for a word, at 60–400
        // ms a beat, then 1.2 s of bubble, when that's longer than the face.
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(say: line).playMs, 1920)
        XCTAssertEqual(DeviceMoment(anim: "wiggle", say: line).playMs, 1920)
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
