import Foundation
import XCTest
@testable import BoopKit
@testable import HookWire

/// The runtime end to end in-process: real hook socket, real core, the
/// harness with a scripted brain, and memory in a temporary state
/// directory; a fake device. Jev's key is never read from the Keychain, and
/// nothing reaches Jev.
final class RuntimeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-rt-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    static let steeringDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../plan/steering").standardizedFileURL
    static let steering = try! Steering(directory: steeringDir)

    /// A runtime whose brain is `brain` once the key reads, or none.
    func options(_ transport: FakeTransport?, brain: ScriptedBrain = .pipelineCheck,
                 readJevKey: @escaping @Sendable () -> String? = { "k" }) throws -> Runtime.Options {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: Self.steering)
        options.devLines = true
        options.readJevKey = readJevKey
        options.brain = { key in key.map { _ in brain } }
        return options
    }

    func makeRuntime(_ transport: FakeTransport, brain: ScriptedBrain = .pipelineCheck,
                     readJevKey: @escaping @Sendable () -> String? = { "k" }) throws -> Runtime {
        try Runtime(options(transport, brain: brain, readJevKey: readJevKey))
    }

    /// harness/HARNESS.md §7: Jev's key is read off `home`, since a Keychain
    /// prompt would stall every event, and no event wakes the brain until it
    /// arrives; a key Settings saves or clears takes over at once. The read
    /// starts with `start`, once the callbacks are set, so it never races
    /// the app setting them.
    func testJevsKeyIsReadOffHome() throws {
        let prompt = DispatchSemaphore(value: 0)
        let reads = Lines()
        let runtime = try makeRuntime(FakeTransport(), brain: ScriptedBrain(id: "jev-test", always: [:])) {
            reads.add("read")
            prompt.wait()  // as a Keychain prompt waits for an answer
            return "k"
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(reads.all, [], "not before start")
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        wait("home answers while the key is read") { runtime.home.sync { statuses.last?.brain == "none" } }
        prompt.signal()
        wait("the brain once it's read") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
        XCTAssertTrue(runtime.home.sync { runtime.core.config.brain })
        runtime.reloadBrain(jevKey: nil)
        wait("none when Settings clears it") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertFalse(runtime.home.sync { runtime.core.config.brain }, "so no event wakes it")
        runtime.reloadBrain(jevKey: "k2")
        wait("the brain when Settings saves one") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
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

        // A finished turn clears "needs you" and cheers.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        wait("cheer") { transport.sent.contains { $0 == #"{"t":"moment","anim":"cheer","ttl":5}"# } }
        XCTAssertEqual(AppSettings.load(from: dir).personality, .boop)
        wait("today's short-term memory") {
            (try? String(contentsOf: self.dir.appendingPathComponent("short-term.md"), encoding: .utf8))?.contains("## Today") == true
        }
    }

    /// harness/HARNESS.md §3–5: an event that wakes the brain gets a pass;
    /// the answers become a mumble on the device, and the mood action's
    /// change reaches the mood file, the status, and the next pass's MOOD.
    func testAPassMumblesAndChangesTheMood() throws {
        let transport = FakeTransport()
        let lines = DebugLines()
        var options = try options(transport, brain: ScriptedBrain(id: "scripted", always: [
            "mood": Answer(choice: "grumpy", probabilities: ["grumpy": 0.7]),
            "react": Answer(choice: "annoyed", probabilities: ["annoyed": 0.6]),
            "word.feeling": Answer(choice: "again", probabilities: ["again": 0.5]),
        ]))
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        wait("the brain") { runtime.home.sync { statuses.last?.brain == "scripted" } }
        let socket = dir.appendingPathComponent("boop.sock").path
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socket))
        wait("a mumble") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":"#) } }
        wait("grumpy") { runtime.home.sync { runtime.mood.current == "grumpy" } }
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(MoodStore.fileName), encoding: .utf8), "grumpy\n")
        wait("the log line") { lines.lock.withLock { lines.log.contains { $0.hasPrefix("brain turn_start ") && $0.hasSuffix("→ mood, react") } } }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socket))
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        func passes() -> [Substring] {
            ((try? String(contentsOf: debugLog, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains("\"pass\":") }
        }
        wait("the second pass") { passes().count == 2 }
        XCTAssertTrue(passes()[0].contains("Happy. Boop is in good spirits"), "the first pass read happy")
        XCTAssertTrue(passes()[1].contains("Grumpy. Boop is fed up"), "the next reads the new mood's file")
        XCTAssertTrue(passes()[1].contains(#"Boop mumbled, annoyed: \"…again!\""#), "HISTORY shows what the actions did")
        XCTAssertFalse(lines.lock.withLock { lines.log.contains { $0.contains("PERSONALITY") } }, "the state stays out of boop.log")
    }

    /// harness/HARNESS.md §9: debug mode logs every hook with what it became
    /// and every line to the device, starts debug.jsonl afresh with every
    /// entry, and prints them readably, but Jev's state stays out of
    /// boop.log.
    func testDebugModePrintsEverythingAndStartsItsLogAfresh() throws {
        let lines = DebugLines()
        var options = try options(FakeTransport())
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        try Data("{\"seq\":1}\n".utf8).write(to: debugLog)
        func file() -> Int? { (try? FileManager.default.attributesOfItem(atPath: debugLog.path))?[.systemFileNumber] as? Int }
        let lastLaunch = try XCTUnwrap(file())
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        options.debugPrint = { line in lines.lock.withLock { lines.printed.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        try XCTAssertEqual(try String(contentsOf: debugLog, encoding: .utf8), "", "each launch starts afresh")
        XCTAssertEqual(file(), lastLaunch, "in place, so a boopdev watch on it sees it start again")

        let socket = dir.appendingPathComponent("boop.sock").path
        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socket))
        XCTAssertTrue(HookSocket.send(hook("PreToolUse", tool: "Bash"), to: socket))
        wait("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socket))
        wait("the pass in debug.jsonl") {
            (try? String(contentsOf: debugLog, encoding: .utf8))?.contains("\"action\"") == true
        }
        let log = lines.lock.withLock { lines.log }
        let printed = lines.lock.withLock { lines.printed }
        XCTAssertTrue(log.contains("hook: claude SessionStart s1 → session_start jetpack"), "\(log)")
        XCTAssertTrue(log.contains("hook: claude PreToolUse s1 → activity jetpack · tool Bash"), "\(log)")
        XCTAssertTrue(log.contains { $0.hasPrefix("link rules → ") })
        XCTAssertFalse(log.contains { $0.contains("How to read HISTORY") }, "the state stays out of boop.log")
        XCTAssertTrue(printed.contains { $0.hasPrefix("core: event turn_start") })
        XCTAssertTrue(printed.contains { $0.hasPrefix("▸ 1 turn_start: claude started turn 1") }, "\(printed)")
        let pass = try XCTUnwrap(printed.first { $0.hasPrefix("  pass scripted") })
        XCTAssertTrue(pass.contains("react excited 1.00"), pass)
        XCTAssertTrue(pass.contains("    │ You are the mind of Boop"), "the first state in full")
        XCTAssertTrue(printed.contains("  ✓ react: Boop mumbled, excited: \"…yay!\""), "\(printed)")
        let records = try String(contentsOf: debugLog, encoding: .utf8).split(separator: "\n")
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(records[1].utf8)) as? [String: Any])
        let p = try XCTUnwrap(o["pass"] as? [String: Any])
        XCTAssertTrue((p["state"] as? String)?.hasPrefix("You are the mind of Boop") == true)
        XCTAssertEqual(p["questions"] as? [String], ["mood", "react", "word.feeling", "word.about"])
    }

    /// ADAPTERS.md §6: while the doctor has armed the app it logs every
    /// hook, and an arm lasts 10 minutes, so one never confirmed doesn't
    /// keep hooks in boop.log for good.
    func testTheDoctorsArmLastsTenMinutes() throws {
        let lines = DebugLines()
        var options = try options(FakeTransport())
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        let socket = dir.appendingPathComponent("boop.sock").path
        let arm = dir.appendingPathComponent(Runtime.doctorArm)
        func logged(_ session: String) -> Bool { lines.lock.withLock { lines.log.contains("hook: claude Stop \(session)") } }
        func send(_ session: String) {
            XCTAssertTrue(HookSocket.send(HookLine(agent: "claude", hook: "Stop", session: session, cwd: "/tmp/jetpack",
                                                   ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded(), to: socket))
            runtime.home.sync {}
        }

        try Data("0\n".utf8).write(to: arm)
        send("armed")
        wait("an armed app logs hooks") { logged("armed") }

        XCTAssertEqual(Runtime.doctorArmSeconds, 600)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 60 - 50)], ofItemAtPath: arm.path)
        send("nine-fifty")
        wait("still armed just under 10 minutes") { logged("nine-fifty") }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 60 - 1)], ofItemAtPath: arm.path)
        send("expired")
        send("after")
        wait("an expired arm is removed") { !FileManager.default.fileExists(atPath: arm.path) }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(logged("expired"))
        XCTAssertFalse(logged("after"))
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
                                      link: nil, steering: Self.steering)
        try XCTAssertThrowsError(try Runtime(options)) { XCTAssertEqual("\($0)", "\(Runtime.OpenError.notSetUp)") }
    }

    /// The app bundles a copy of plan/steering/, file for file.
    func testTheBundledSteeringIsTheSpec() throws {
        let bundled = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../app/Boop/Resources/steering").standardizedFileURL
        let files = try XCTUnwrap(FileManager.default.subpaths(atPath: Self.steeringDir.path)).filter { $0.hasSuffix(".md") }.sorted()
        XCTAssertEqual(files, ["guide.md", "mood/curious.md", "mood/determined.md", "mood/excited.md", "mood/grumpy.md",
                               "mood/happy.md", "mood/proud.md", "mood/sad.md", "personality/boop.md", "personality/chatter.md"])
        for file in files {
            try XCTAssertEqual(try String(contentsOf: bundled.appendingPathComponent(file), encoding: .utf8),
                               try String(contentsOf: Self.steeringDir.appendingPathComponent(file), encoding: .utf8),
                               "app/Boop/Resources/steering/\(file) must be a copy of plan/steering/\(file)")
        }
        XCTAssertEqual(FileManager.default.subpaths(atPath: bundled.path)?.filter { $0.hasSuffix(".md") }.sorted(), files)
    }

    /// harness/HARNESS.md §6.2: the static parts stay within their budgets,
    /// and the personalities' settings are BEHAVIORS.md §6's.
    func testTheSteeringFitsItsBudgetsAndSettings() {
        XCTAssertEqual(Self.steering.overBudget(), [])
        XCTAssertEqual(Self.steering.personality(.boop).rules,
                       Personality.Rules(cheer: .every, chatterMs: 120_000...240_000, toolUses: .notable))
        XCTAssertEqual(Self.steering.personality(.chatter).rules,
                       Personality.Rules(cheer: .every, chatterMs: 30_000...60_000, toolUses: .all))
        XCTAssertFalse(Self.steering.guide.contains("<!--"), "comments are left out")
        XCTAssertTrue(Self.steering.personality(.boop).text.hasPrefix("PERSONALITY\n"))
        XCTAssertTrue(Self.steering.mood("grumpy").hasPrefix("MOOD\nGrumpy."))
    }

    /// Settings from before the personalities and the 2026-09-26 cut still
    /// load, as boop; the keys that went are ignored and aren't written back.
    func testOldSettingsStartAsBoop() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"{"mode":"calm","brain":"jev","classifier":"rules","writer":"none","volume":3,"focus":true,"away":true,"awaySince":"2026-09-20","finished":148,"projects":["jetpack"]}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        let settings = AppSettings.load(from: dir)
        XCTAssertEqual(settings.personality, .boop)
        XCTAssertEqual(settings.volume, 3)
        try settings.save(to: dir)
        let text = try String(contentsOf: dir.appendingPathComponent(AppSettings.file), encoding: .utf8)
        for key in ["mode", "brain", "classifier", "writer", "focus", "away", "finished", "projects"] {
            XCTAssertFalse(text.contains("\"\(key)\""), key)
        }
    }

    /// BEHAVIORS.md §6: the personality is saved; a missing or unknown one
    /// is boop.
    func testSettingsKeepThePersonality() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, Personality)] = [(#"{"personality":"chatter"}"#, .chatter), (#"{"personality":"loud"}"#, .boop),
                                              (#"{}"#, .boop)]
        for (json, p) in cases {
            try Data(json.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
            XCTAssertEqual(AppSettings.load(from: dir).personality, p, json)
        }
        var saved = AppSettings()
        saved.personality = .chatter
        try saved.save(to: dir)
        XCTAssertEqual(AppSettings.load(from: dir), saved)
    }

    /// BEHAVIORS.md §6: a new personality takes effect from the next event,
    /// its rules included, and is saved.
    func testANewPersonalityTakesEffectAtOnce() throws {
        let runtime = try makeRuntime(FakeTransport())
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        wait("started as boop") { runtime.home.sync { statuses.last?.personality == .boop } }
        runtime.setPersonality(.chatter)
        wait("chatter now") { runtime.home.sync { statuses.last?.personality == .chatter } }
        XCTAssertEqual(runtime.home.sync { runtime.core.config.rules.toolUses }, .all)
        XCTAssertEqual(AppSettings.load(from: dir).personality, .chatter)
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// the rules cheer at once, and the brain's mumble waits until the cheer
    /// has played instead of cutting it off.
    func testTheBrainWaitsForTheRulesMoment() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let skew = NSLock()
        nonisolated(unsafe) var skewMs: Int64 = 0
        options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.withLock { skewMs } }
        options.advance = { ms in skew.withLock { skewMs += ms } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)

        let socket = dir.appendingPathComponent("boop.sock").path
        wait("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socket))
        wait("working") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        wait("the start's mumble has played", timeout: 5) {
            transport.sent.contains { $0.contains("\"say\"") } && runtime.home.sync { runtime.moments.schedule.idle(now: runtime.options.clock()) }
        }
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

    /// ARCHITECTURE.md §3.2: the app knows how long each rule moment plays on
    /// the device. The numbers are firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play`, and firmware/src/render/anim.cpp's
    /// `animDuration` (BEHAVIORS.md §5: a cheer is 2 s).
    func testMomentLengthsFollowTheFirmware() {
        XCTAssertEqual(DeviceMoment(anim: "cheer").playMs, 2000)
        XCTAssertEqual(DeviceMoment(anim: "wiggle").playMs, 700)

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

/// What a runtime in debug mode logged and printed. Not nested in a test:
/// the shim's runner generator would take it for the test class.
final class DebugLines: @unchecked Sendable {
    let lock = NSLock()
    var log: [String] = []
    var printed: [String] = []
}

/// Lines gathered from any thread, for tests.
final class Lines: @unchecked Sendable {
    let lock = NSLock()
    var all: [String] { lock.withLock { stored } }
    private var stored: [String] = []
    func add(_ line: String) { lock.withLock { stored.append(line) } }
}
