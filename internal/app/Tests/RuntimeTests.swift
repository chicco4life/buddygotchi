import Foundation
import XCTest
@testable import BoopDevKit
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
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet)
        var options = Runtime.Options(stateDir: dir, socketPath: socketPath, link: transport, steering: Self.steering)
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
        eventually("home answers while the key is read") { runtime.home.sync { statuses.last?.brain == "none" } }
        prompt.signal()
        eventually("the brain once it's read") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
        XCTAssertTrue(runtime.home.sync { runtime.core.config.brain })
        runtime.reloadBrain(jevKey: nil)
        eventually("none when Settings clears it") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertFalse(runtime.home.sync { runtime.core.config.brain }, "so no event wakes it")
        runtime.reloadBrain(jevKey: "k2")
        eventually("the brain when Settings saves one") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
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
        eventually("first state on start") { transport.types().contains("state") }
        transport.onConnection?(true)

        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("working state") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        XCTAssertTrue(HookSocket.send(hook("PermissionRequest", tool: "Bash"), to: socketPath))
        eventually("needs you") { transport.sent.contains { $0.contains("\"attn\":{\"agent\":\"claude\",\"project\":\"jetpack\"") } }

        // The device's status gets a state back.
        let before = transport.types().filter { $0 == "state" }.count
        transport.onLine?(#"{"t":"status","v":1,"id":"b00p-54fe","fw":"1.0.0"}"#)
        eventually("state after status") { transport.types().filter { $0 == "state" }.count > before }
        XCTAssertEqual(runtime.home.sync { runtime.link.status?.id }, "b00p-54fe")

        // A finished turn clears "needs you" and cheers.
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("cheer") { transport.sent.contains { $0 == #"{"t":"moment","anim":"cheer","loops":1}"# } }
        XCTAssertEqual(AppSettings.load(from: dir).personality, .boop)
        eventually("today's short-term memory") {
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
            "react": Answer(choice: "grumpy", probabilities: ["grumpy": 0.6]),
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
        eventually("the brain") { runtime.home.sync { statuses.last?.brain == "scripted" } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":"#) } }
        eventually("grumpy") { runtime.home.sync { runtime.mood.current == "grumpy" } }
        eventually("the device hears it") { transport.sent.contains { $0.hasPrefix(#"{"t":"state""#) && $0.contains(#""mood":"grumpy""#) } }
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(MoodStore.fileName), encoding: .utf8), "grumpy\n")
        eventually("the log line") { lines.lock.withLock { lines.log.contains { $0.hasPrefix("brain turn_start ") && $0.hasSuffix("→ mood, react") } } }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        func passes() -> [Substring] {
            ((try? String(contentsOf: debugLog, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains("\"pass\":") }
        }
        eventually("the second pass") { passes().count == 2 }
        XCTAssertTrue(passes()[0].contains("Happy. Boop is in good spirits"), "the first pass read happy")
        XCTAssertTrue(passes()[1].contains("Grumpy. Boop is fed up"), "the next reads the new mood's file")
        XCTAssertTrue(passes()[1].contains(#"Boop made a grumpy face, held once, and mumbled \"…again!\""#), "HISTORY shows what the actions did")
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
        let fresh = try String(contentsOf: debugLog, encoding: .utf8)
        XCTAssertTrue(fresh.hasPrefix(#"{"questions":"#) && !fresh.contains(#"{"seq":1}"#),
                      "each launch starts afresh, with the questions first (DASHBOARD.md §3)")
        XCTAssertEqual(file(), lastLaunch, "in place, so a boopdev watch on it sees it start again")

        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("PreToolUse", tool: "Bash"), to: socketPath))
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the pass in debug.jsonl") { self.debugLines().contains { $0["action"] != nil } }
        let log = lines.lock.withLock { lines.log }
        let printed = lines.lock.withLock { lines.printed }
        XCTAssertTrue(log.contains("hook: claude SessionStart s1 → session_start jetpack"), "\(log)")
        XCTAssertTrue(log.contains("hook: claude PreToolUse s1 → activity jetpack · tool Bash"), "\(log)")
        XCTAssertTrue(log.contains { $0.hasPrefix("link rules → ") })
        XCTAssertFalse(log.contains { $0.contains("How to read HISTORY") }, "the state stays out of boop.log")
        XCTAssertTrue(printed.contains { $0.hasPrefix("core: event turn_start") }, "\(printed)")
        XCTAssertTrue(printed.contains { $0.hasPrefix("▸ 1 turn_start: claude started turn 1") }, "\(printed)")
        let pass = try XCTUnwrap(printed.first { $0.hasPrefix("  pass scripted") })
        XCTAssertTrue(pass.contains("react excited 1.00"), pass)
        XCTAssertTrue(pass.contains("    │ You are the mind of Boop"), "the first state in full")
        XCTAssertTrue(printed.contains("  … react: Boop made an excited face, held once, and mumbled \"…yay!\""), "started: \(printed)")
        XCTAssertTrue(printed.contains { $0.hasPrefix("  ✗ react (") && $0.hasSuffix(") didn't happen: no device connected") },
                      "the fake device never connected: \(printed)")
        let p = try XCTUnwrap(debugLines().compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue((p["state"] as? String)?.hasPrefix("You are the mind of Boop") == true)
        XCTAssertEqual(p["questions"] as? [String], ["mood", "react", "react.loops", "word.feeling", "word.about"])
    }

    /// The lines of this runtime's debug.jsonl, as JSON objects.
    func debugLines() -> [[String: Any]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    var socketPath: String { dir.appendingPathComponent("boop.sock").path }

    func dev(_ json: String) {
        XCTAssertTrue(HookSocket.send(Data((json + "\n").utf8), to: socketPath))
    }

    /// harness/HARNESS.md §9, DASHBOARD.md §3: debug mode also writes the
    /// dashboard's lines, with no `seq`: every action's questions once at
    /// launch, every line sent to the device verbatim (with no transport
    /// too), and a status line whenever the mood, personality, brain,
    /// sessions or connection change.
    func testDebugModeWritesTheDashboardsLines() throws {
        var options = try options(nil)
        options.debug = true
        let runtime = try Runtime(options)
        runtime.link.sentLines = []
        try runtime.start()
        defer { runtime.stop() }
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { runtime.home.sync { runtime.link.sentLines!.contains { $0.contains(#""say":"#) } } }
        runtime.home.sync {}

        let text = try String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)
        let raw = text.split(separator: "\n").map(String.init)
        let lines = debugLines()
        let questions = try XCTUnwrap(lines.first?["questions"] as? [[String: Any]], "the questions come first")
        XCTAssertEqual(lines.filter { $0["questions"] != nil }.count, 1, "once")
        XCTAssertEqual(questions.map { $0["key"] as? String }, ["mood", "react", "react.loops", "word.feeling", "word.about"])
        XCTAssertEqual(questions.map { $0["action"] as? String }, ["mood", "react", "react", "react", "react"])
        XCTAssertEqual(questions[1]["text"] as? String, "How should Boop react to NOW, if at all? It makes this face for a moment, with a mumble.")
        let none = try XCTUnwrap((questions[1]["options"] as? [[String: Any]])?.first)
        XCTAssertEqual(none["name"] as? String, "none")
        XCTAssertEqual(none["what"] as? String, "Stay quiet: nothing in NOW is worth a face and a mumble.")
        XCTAssertEqual(none["not_for"] as? String, "Anything PERSONALITY's Examples react to.")
        XCTAssertTrue((questions[0]["options"] as? [[String: Any]])?.first?["not_for"] is NSNull)

        // Sent: every line the link sent, verbatim and in order.
        let sent = raw.filter { $0.hasPrefix(#"{"sent":"#) }.map { line in
            String(line.dropFirst(#"{"sent":"#.count)).replacingOccurrences(
                of: #",\"received_at_ms\":\d+\}$"#, with: "", options: .regularExpression)
        }
        XCTAssertEqual(sent, runtime.home.sync { runtime.link.sentLines! })
        XCTAssertTrue(sent.contains { $0.hasPrefix(#"{"t":"state""#) } && sent.contains { $0.hasPrefix(#"{"t":"moment""#) })

        // Status: only the facts the device lines don't carry, and only changes.
        let statuses = lines.compactMap { $0["status"] as? [String: Any] }
        XCTAssertFalse(statuses.isEmpty)
        XCTAssertEqual(Set(statuses[0].keys), ["personality", "brain", "sessions", "connected"], "a state carries the mood")
        XCTAssertEqual(statuses.last?["brain"] as? String, "scripted")
        XCTAssertEqual(statuses.last?["connected"] as? Bool, false)
        let sessions = try XCTUnwrap(statuses.last?["sessions"] as? [[String: String]])
        XCTAssertEqual(sessions, [["agent": "claude", "project": "jetpack", "status": "working"]])
        for (a, b) in zip(statuses, statuses.dropFirst()) { XCTAssertFalse(NSDictionary(dictionary: a).isEqual(to: b), "only changes") }
        for line in lines where line["seq"] == nil {
            XCTAssertEqual(Set(line.keys).subtracting(["received_at_ms"]).count, 1, "one kind, and no seq: \(line)")
            XCTAssertNotNil(line["received_at_ms"] as? Int64)
        }
    }

    /// PROTOCOL.md §3's `state` carries no idle count, so a second idle
    /// session sends the device nothing; debug.jsonl's `status`, which the
    /// dashboard counts idle sessions from, and the popover still hear of it.
    func testASecondIdleSessionReachesTheStatusNotTheDevice() throws {
        var options = try options(nil)
        options.debug = true
        let runtime = try Runtime(options)
        runtime.link.sentLines = []
        try runtime.start()
        defer { runtime.stop() }
        func sessions() -> [[String: String]] {
            debugLines().compactMap { $0["status"] as? [String: Any] }.last?["sessions"] as? [[String: String]] ?? []
        }
        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        eventually("the first session") { sessions().count == 1 }
        let sent = runtime.home.sync { runtime.link.sentLines! }
        XCTAssertTrue(sent.last?.contains(#""base":"idle""#) == true, "\(sent)")
        let second = HookLine(agent: "claude", hook: "SessionStart", session: "s2", cwd: "/tmp/notes",
                              ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded()
        XCTAssertTrue(HookSocket.send(second, to: socketPath))
        eventually("the second session") { sessions().count == 2 }
        XCTAssertEqual(sessions().map { $0["status"] }, ["idle", "idle"])
        XCTAssertEqual(runtime.home.sync { runtime.link.sentLines! }, sent, "no new state")
    }

    /// DASHBOARD.md §4: the dashboard's dev lines. A forced pass needs no
    /// brain and mumbles as Jev's would; a forced mood changes as Jev's
    /// does, device included; each is recorded for no event, by the
    /// dashboard. A moment goes
    /// through the schedule, and one with no known animation is ignored.
    func testTheDashboardsDevLines() throws {
        let transport = FakeTransport()
        var options = try options(transport, readJevKey: { nil })
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        eventually("no brain") { runtime.home.sync { !runtime.readingJevKey && runtime.jevKey != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))

        dev(#"{"dev":"answer","answers":{"react":"grumpy","word.feeling":"again"}}"#)
        eventually("a mumble with no brain") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":"#) && $0.contains(#""word":"again""#) } }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        eventually("grumpy") { runtime.home.sync { runtime.mood.current == "grumpy" } }
        dev(#"{"dev":"mood","mood":"happy"}"#)
        eventually("happy again") { runtime.home.sync { runtime.mood.current == "happy" } }
        dev(#"{"dev":"moment","anim":"cheer"}"#)
        eventually("the cheer") { transport.sent.contains(#"{"t":"moment","anim":"cheer","loops":1}"#) }
        dev(#"{"dev":"moment","anim":"dance"}"#)
        dev(#"{"dev":"moment"}"#)
        dev(#"{"dev":"moment","anim":"wiggle"}"#)
        eventually("the wiggle after them") { transport.sent.contains(#"{"t":"moment","anim":"wiggle"}"#) }
        XCTAssertFalse(transport.sent.contains { $0.contains("dance") || $0 == #"{"t":"moment"}"# })

        let lines = debugLines()
        let pass = try XCTUnwrap(lines.compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue(pass["for"] is NSNull)
        XCTAssertEqual(pass["by"] as? String, "dashboard")
        XCTAssertEqual(pass["questions"] as? [String], ["react", "word.feeling"])
        XCTAssertEqual((pass["answers"] as? [String: [String: Any]])?["react"]?["p"] as? [String: Double], ["grumpy": 1])
        let actions = lines.compactMap { $0["action"] as? [String: Any] }
        XCTAssertEqual(actions.map { $0["message"] as? String }, [#"Boop made a grumpy face, held once, and mumbled "…again!""#,
                                                                "Boop's mood changed: happy → grumpy.",
                                                                "Boop's mood changed: grumpy → happy."])
        XCTAssertEqual(actions.map { $0["name"] as? String }, ["react", "mood", "mood"])
        for action in actions {
            XCTAssertTrue(action["for"] is NSNull)
            XCTAssertEqual(action["by"] as? String, "dashboard")
        }
        let moods = lines.compactMap { ($0["sent"] as? [String: Any])?["mood"] as? String }
        XCTAssertEqual(moods.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, ["happy", "grumpy", "happy"],
                       "the device hears each change in a state")
    }

    /// DASHBOARD.md §4: a forced react keeps its own rules, so it's refused
    /// while something needs you, and the refusal is recorded.
    func testAForcedReactStillRefusesWhileSomethingNeedsYou() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        XCTAssertTrue(HookSocket.send(hook("PermissionRequest", tool: "Bash"), to: socketPath))
        eventually("needs you") { transport.sent.contains { $0.contains(#""attn":"#) } }
        dev(#"{"dev":"answer","answers":{"react":"happy"}}"#)
        eventually("the refusal") {
            self.debugLines().contains { ($0["action"] as? [String: Any])?["message"] as? String == "something needs you" }
        }
        let action = try XCTUnwrap(debugLines().compactMap { $0["action"] as? [String: Any] }.last)
        XCTAssertEqual(action["ok"] as? Bool, false)
        XCTAssertFalse(transport.sent.contains { $0.contains(#""say":"#) })
    }

    /// Without `--debug` or `--headless` the socket takes no dev lines, so
    /// plain `make run` can't be driven.
    func testDevLinesAreIgnoredWithoutThem() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        options.devLines = false
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        dev(#"{"dev":"moment","anim":"cheer"}"#)
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the hook after them") { transport.sent.contains { $0.contains(#""base":"working""#) } }
        runtime.home.sync {}
        XCTAssertEqual(runtime.home.sync { runtime.mood.current }, "happy")
        XCTAssertFalse(transport.sent.contains { $0.contains("cheer\"") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(MoodStore.fileName).path))
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
        let arm = dir.appendingPathComponent(Runtime.doctorArm)
        func logged(_ session: String) -> Bool { lines.lock.withLock { lines.log.contains("hook: claude Stop \(session)") } }
        func send(_ session: String) {
            XCTAssertTrue(HookSocket.send(HookLine(agent: "claude", hook: "Stop", session: session, cwd: "/tmp/jetpack",
                                                   ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded(), to: socketPath))
            runtime.home.sync {}
        }

        try Data("0\n".utf8).write(to: arm)
        send("armed")
        eventually("an armed app logs hooks") { logged("armed") }

        XCTAssertEqual(Runtime.doctorArmSeconds, 600)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 60 - 50)], ofItemAtPath: arm.path)
        send("nine-fifty")
        eventually("still armed just under 10 minutes") { logged("nine-fifty") }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 60 - 1)], ofItemAtPath: arm.path)
        send("expired")
        send("after")
        eventually("an expired arm is removed") { !FileManager.default.fileExists(atPath: arm.path) }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(logged("expired"))
        XCTAssertFalse(logged("after"))
    }

    func testStopRemovesTheSocketAndReleasesTheLock() throws {
        let runtime = try makeRuntime(FakeTransport())
        try runtime.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        try XCTAssertThrowsError(try Runtime(runtime.options)) // one app per state directory
        runtime.stop()
        runtime.home.sync {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertFalse(HookSocket.send(hook("Stop"), to: socketPath))
    }

    func testNotSetUpIsAnError() throws {
        let options = Runtime.Options(stateDir: dir, socketPath: socketPath, link: nil, steering: Self.steering)
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
        XCTAssertEqual(Self.steering.personality(.boop).rules, Personality.Rules(chatterMs: 120_000...240_000, toolUses: .notable))
        XCTAssertEqual(Self.steering.personality(.chatter).rules, Personality.Rules(chatterMs: 30_000...60_000, toolUses: .all))
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
        eventually("started as boop") { runtime.home.sync { statuses.last?.personality == .boop } }
        runtime.setPersonality(.chatter)
        eventually("chatter now") { runtime.home.sync { statuses.last?.personality == .chatter } }
        XCTAssertEqual(runtime.home.sync { runtime.core.config.rules.toolUses }, .all)
        XCTAssertEqual(AppSettings.load(from: dir).personality, .chatter)
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// the rules cheer at once, and the brain's mumble plays over the cheer
    /// with its expression, without an animation that would cut it off
    /// (ARCHITECTURE.md §3.2).
    func testTheBrainMumblesOverTheRulesCheer() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let skew = VirtualClock(0)
        options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.now }
        options.advance = { skew.now += $0 }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)

        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("working") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        eventually("the start's mumble has played", timeout: 5) {
            transport.sent.contains { $0.contains("\"say\"") } && runtime.home.sync { runtime.moments.schedule.idle(now: runtime.options.clock()) }
        }
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":30000}"#.utf8), to: socketPath))
        eventually("clock moved") { skew.now == 30_000 }
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        let before = moments().count
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the cheer, then the brain's mumble", timeout: 4) { moments().count >= before + 2 }
        XCTAssertEqual(moments()[before], #"{"t":"moment","anim":"cheer","loops":1}"#, "the rules' reaction first")
        let mumble = moments()[before + 1]
        XCTAssertTrue(mumble.hasPrefix(#"{"t":"moment","say":"#), "a mumble has no anim: \(mumble)")
        XCTAssertTrue(mumble.contains(#""mood":""#), "the brain's mumble has its expression: \(mumble)")
        XCTAssertFalse(moments().contains { $0.contains("\"anim\"") && $0.contains("\"mood\"") },
                       "the rules' cheer has no expression")
    }

    /// ARCHITECTURE.md §3.2: the brain's moments play one at a time, each
    /// after any line and face playing, so none cuts off a line or another
    /// of the brain's; a mumble plays over an animation, which doesn't cut
    /// it; a newer line pushes them back and an animation stops the line;
    /// one that waited over 5 s is dropped.
    func testBrainMomentsTakeTurns() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let mumble = DeviceMoment(say: line, mood: "proud")  // its line is 1920 ms
        let chatter = DeviceMoment(say: line)  // a rule's line, 1920 ms
        var schedule = MomentSchedule()
        schedule.rule(DeviceMoment(anim: "cheer"), now: 0)
        schedule.brain(mumble, now: 100)
        schedule.brain(mumble, now: 200)
        var due = schedule.due(now: 500)
        XCTAssertEqual(due.play, mumble, "over the cheer, which a mumble doesn't cut")
        let first = 500 + max(1920, FaceLoops.ms(mood: "proud", state: "task_complete"))
        XCTAssertEqual(due.next, first, "the second waits for the first's line and face")
        XCTAssertFalse(schedule.idle(now: 2000), "chatter waits for both")
        XCTAssertNil(schedule.due(now: 2000).play)
        due = schedule.due(now: first)
        XCTAssertEqual(due.play, mumble, "then the second")
        XCTAssertNil(due.next, "nothing left")

        var afterLine = MomentSchedule()
        afterLine.rule(chatter, now: 0)
        afterLine.brain(mumble, now: 100)
        XCTAssertNil(afterLine.due(now: 500).play, "a line is playing")
        XCTAssertEqual(afterLine.due(now: 500).next, 1920)
        XCTAssertEqual(afterLine.due(now: 1920).play, mumble)

        var cut = MomentSchedule()
        cut.rule(chatter, now: 0)
        cut.brain(mumble, now: 1000)
        cut.rule(DeviceMoment(anim: "cheer"), now: 1500)  // a finish stops the line
        XCTAssertEqual(cut.due(now: 1500).play, mumble)

        var late = MomentSchedule()
        late.rule(chatter, now: 0)
        late.brain(mumble, now: 0)
        late.rule(chatter, now: 1900)
        late.rule(chatter, now: 3800)
        due = late.due(now: 5800)
        XCTAssertNil(due.play)
        XCTAssertEqual(MomentSchedule.maxWaitMs, 5000)
        XCTAssertEqual(due.dropped, [mumble], "5.8 s is past 5 s")
        XCTAssertNil(due.next)
    }

    /// harness/DECISIONS.md §5: a brain moment's handle goes through the
    /// schedule with it. One dropped for waiting over 5 s ends there as
    /// failed, `waited too long`; one whose turn comes is handed on with
    /// its handle, for whoever plays it to end.
    func testADroppedMomentDidntHappen() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let mumble = DeviceMoment(say: line, mood: "proud")
        let chatter = DeviceMoment(say: line)  // 1920 ms
        var ends: [String: Pending.End] = [:]
        func handle(_ name: String) -> Pending {
            let pending = Pending()
            pending.bind { ends[name] = $0 }
            return pending
        }
        let late = handle("late"), onTime = handle("on time")
        var schedule = MomentSchedule()
        schedule.rule(chatter, now: 0)
        schedule.brain(mumble, late, now: 0)
        schedule.brain(mumble, onTime, now: 1000)
        schedule.rule(chatter, now: 1900)
        schedule.rule(chatter, now: 3800)
        let due = schedule.due(now: 5800)
        XCTAssertEqual(due.dropped, [mumble], "5.8 s is past 5 s")
        XCTAssertEqual(ends, ["late": .failed("waited too long")])
        XCTAssertEqual(due.play, mumble, "4.8 s isn't")
        XCTAssertTrue(due.pending === onTime, "handed on, still open")
    }

    /// harness/DECISIONS.md §5, PROTOCOL.md §4: a reaction is in progress
    /// until the device says how its moment ended: its moment goes out with
    /// the next id, and the device's `ended` for that id ends it, done,
    /// cut short (and by what) or skipped. With no device it didn't happen;
    /// nor did one the device never reported by its length plus
    /// `endGraceMs`, or one playing when the device dropped. An `ended` for
    /// an id the app isn't waiting on changes nothing. The device connects,
    /// answers and drops through the transport, as it does in the app.
    func testAReactionEndsWhenTheDeviceSaysSo() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        /// The transport says the device connected or dropped; `home` hears it.
        func connection(_ up: Bool) {
            transport.onConnection?(up)
            runtime.home.sync {}
        }
        /// The device sends a line; `home` hears it.
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        /// A forced reaction once the last one's line has played: its
        /// `action` entry's seq, and the moment sent for it.
        func react() throws -> (seq: Int, moment: String) {
            clock.now = max(clock.now, runtime.home.sync { runtime.moments.schedule.lineUntil })
            return try runtime.home.sync {
                XCTAssertEqual(runtime.harness.force(["react": "happy"]).map(\.name), ["react"])
                let seq = try XCTUnwrap(runtime.harness.transcript.entries.last {
                    if case .action = $0.body { true } else { false }
                }?.seq)
                return (seq, try XCTUnwrap(transport.sent.last { $0.hasPrefix(#"{"t":"moment""#) }))
            }
        }
        func end(of seq: Int) -> Pending.End? {
            runtime.home.sync {
                runtime.harness.transcript.entries.lazy.compactMap { entry -> Pending.End? in
                    if case .settle(let settle) = entry.body, settle.forSeq == seq { settle.end } else { nil }
                }.first
            }
        }

        let alone = try react()
        XCTAssertEqual(end(of: alone.seq), .failed("no device connected"))
        XCTAssertFalse(alone.moment.contains(#""id""#), "sent all the same, and dropped, with nothing to wait on")
        XCTAssertEqual(runtime.home.sync { runtime.moments.schedule.look }, "asleep",
                       "the look of the last state, which times the face: no sessions")

        clock.now += 10_000
        connection(true)
        let played = try react()
        XCTAssertTrue(played.moment.hasSuffix(#","mood":"happy","loops":1,"id":1}"#), played.moment)
        clock.now = runtime.home.sync { runtime.moments.schedule.lineUntil }
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: played.seq), "played by the app's reckoning, but the device hasn't said so")
        device(#"{"t":"ended","id":1,"how":"done"}"#)
        XCTAssertEqual(end(of: played.seq), .done)
        XCTAssertTrue(runtime.home.sync { runtime.moments.playing.isEmpty })

        let tapped = try react()
        XCTAssertTrue(tapped.moment.hasSuffix(#","id":2}"#))
        device(#"{"t":"ended","id":99,"how":"done"}"#)
        XCTAssertNil(end(of: tapped.seq), "another id: ignored")
        device(#"{"t":"ended","id":2,"how":"cut","why":"tap"}"#)
        XCTAssertEqual(end(of: tapped.seq), .failed("cut short: you tapped Boop"))
        device(#"{"t":"ended","id":2,"how":"done"}"#)
        XCTAssertEqual(end(of: tapped.seq), .failed("cut short: you tapped Boop"), "only the first end counts")

        let skipped = try react()
        device(#"{"t":"ended","id":3,"how":"skipped"}"#)
        XCTAssertEqual(end(of: skipped.seq), .failed("something needed you"))

        let silent = try react()
        let deadline = try XCTUnwrap(runtime.home.sync { runtime.moments.playing.first?.deadline })
        XCTAssertEqual(deadline, runtime.home.sync { runtime.moments.schedule.lineUntil } + Runtime.Moments.endGraceMs,
                       "sent, plus its length, plus the grace")
        clock.now = deadline - 1
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: silent.seq), "still waiting")
        clock.now = deadline
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(end(of: silent.seq), .failed("the device never said it ended"))
        device(#"{"t":"ended","id":4,"how":"done"}"#)
        XCTAssertEqual(end(of: silent.seq), .failed("the device never said it ended"), "too late: ignored")

        let dropped = try react()
        XCTAssertNil(end(of: dropped.seq), "playing")
        connection(false)
        XCTAssertEqual(end(of: dropped.seq), .failed("the device disconnected"))
        XCTAssertTrue(runtime.home.sync { runtime.moments.playing.isEmpty })
    }

    /// PROTOCOL.md §4, harness/DECISIONS.md §5: how each `ended` reads in
    /// HISTORY; and PROTOCOL.md §6: the grace the app gives a moment past
    /// its length.
    func testWhatTheDevicesEndedMeans() {
        XCTAssertEqual(Runtime.Moments.endGraceMs, 3000)
        let end = { (how: MomentEnded.How, why: String?) in Runtime.Moments.end(MomentEnded(id: 1, how: how, why: why)) }
        XCTAssertEqual(end(.done, nil), .done)
        XCTAssertEqual(end(.cut, "tap"), .failed("cut short: you tapped Boop"))
        XCTAssertEqual(end(.cut, "moment"), .failed("cut short: something newer played"))
        XCTAssertEqual(end(.cut, "needs_you"), .failed("cut short: something needed you"))
        XCTAssertEqual(end(.cut, "reset"), .failed("cut short"))
        XCTAssertEqual(end(.cut, nil), .failed("cut short"))
        XCTAssertEqual(end(.skipped, nil), .failed("something needed you"))
    }

    /// harness/DECISIONS.md §5, HARNESS.md §5.1: a reaction held longest,
    /// in the design with the longest loop and with the slowest line, ends
    /// by the app's own reckoning (its wait for a turn, its length and the
    /// grace for the device's `ended`) before the harness's ceiling would
    /// end it. The loops are the designs' (`FaceLoops`), so a new design
    /// with a long loop fails here rather than in HISTORY.
    func testAReactionEndsBeforeTheHarnessCeiling() {
        let slow = VoiceLine(groups: [Array(repeating: "zzz", count: 8)], word: "finally", at: 8, tune: .bounce, ms: 400)
        let held = ReactAction.holds.count
        let longest = MoodAction.moods.map(\.name).flatMap { mood in
            FaceLoops.states.map { DeviceMoment(say: slow, mood: mood, loops: held).playMs(look: $0, mood: mood) }
        }.max() ?? 0
        XCTAssertGreaterThanOrEqual(longest, Int64(held) * FaceLoops.ms.values.flatMap { $0 }.max()!)
        XCTAssertLessThan(MomentSchedule.maxWaitMs + longest + Runtime.Moments.endGraceMs, Harness.pendingMaxMs)
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
        XCTAssertFalse(transport.sent.contains { $0.contains("\"say\"") && $0.contains("\"mood\"") },
                       "chatter is a rule's line, with no expression (PROTOCOL.md §3)")
    }

    /// ARCHITECTURE.md §3.2, PROTOCOL.md §3: the app knows how long each
    /// moment plays on the device at most, as firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play` time it: the cheer its loops (1–6) of its
    /// design, a wiggle 0.7 s, a face its loops of the look's design in its
    /// own mood (the device ends it on a loop boundary, so no later), and a
    /// mumble its beats and bubble when that's longer. The loops are
    /// `FaceLoops`, the numbers faces.h gives the device.
    func testMomentLengthsFollowTheFirmware() {
        let cheer = FaceLoops.ms(mood: "happy", state: "task_complete")
        let idle = { (m: DeviceMoment) in m.playMs(look: "idle", mood: "happy") }
        XCTAssertEqual(idle(DeviceMoment(anim: "cheer")), cheer, "once when it doesn't say")
        XCTAssertEqual(idle(DeviceMoment(anim: "cheer", loops: 3)), 3 * cheer)
        XCTAssertEqual(idle(DeviceMoment(anim: "cheer", loops: 9)), 6 * cheer, "at most 6")
        XCTAssertEqual(idle(DeviceMoment(anim: "cheer", loops: 0)), cheer, "at least 1")
        XCTAssertEqual(DeviceMoment(anim: "cheer").playMs(look: "idle", mood: "proud"),
                       FaceLoops.ms(mood: "proud", state: "task_complete"), "in the mood's design")
        XCTAssertEqual(idle(DeviceMoment(anim: "wiggle", loops: 3)), 700)

        // A mumble lasts its syllables plus two beats for a word, at 60–400
        // ms a beat, then 1.2 s of bubble, when that's longer than the face.
        let working = { (m: DeviceMoment) in m.playMs(look: "working", mood: "happy") }
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(working(DeviceMoment(say: line)), 1920)
        XCTAssertEqual(working(DeviceMoment(anim: "wiggle", say: line)), 1920)
        var plain = line
        plain.word = nil
        XCTAssertEqual(working(DeviceMoment(say: plain)), 1680)
        var slow = line
        slow.ms = 500
        XCTAssertEqual(working(DeviceMoment(say: slow)), 3600)
        var quick = line
        quick.ms = 20
        XCTAssertEqual(working(DeviceMoment(say: quick)), 1560, "6 × 60 + 1200")
        XCTAssertEqual(working(DeviceMoment(anim: "cheer", say: quick)), cheer, "the cheer is longer")

        // A face holds its loops of the design showing, in its own mood.
        let grumpy = FaceLoops.ms(mood: "grumpy", state: "working")
        XCTAssertEqual(working(DeviceMoment(say: quick, mood: "grumpy")), grumpy)
        XCTAssertEqual(working(DeviceMoment(say: quick, mood: "grumpy", loops: 2)), 2 * grumpy)
        XCTAssertEqual(DeviceMoment(say: quick, mood: "grumpy").playMs(look: "task_complete", mood: "happy"),
                       FaceLoops.ms(mood: "grumpy", state: "task_complete"), "over the cheer, the cheer's design")
        XCTAssertLessThan(FaceLoops.ms(mood: "excited", state: "working"), 3600)
        XCTAssertEqual(working(DeviceMoment(say: slow, mood: "excited")), 3600, "a longer line holds it longer")
    }

    /// ARCHITECTURE.md §3.2: the schedule times a moment by the design
    /// showing: the look and mood of the last `state`, or the cheer's while
    /// one plays. A reaction's face holds the brain's next one back.
    func testTheScheduleTimesAMomentByTheDesignShowing() {
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)
        let face = DeviceMoment(say: line, mood: "proud", loops: 2)
        var schedule = MomentSchedule()
        schedule.look = "working"
        XCTAssertEqual(schedule.playMs(face, now: 0), 2 * FaceLoops.ms(mood: "proud", state: "working"))
        schedule.rule(DeviceMoment(anim: "cheer", loops: 1), now: 0)
        XCTAssertEqual(schedule.cheerUntil, FaceLoops.ms(mood: "happy", state: "task_complete"))
        let overCheer = 2 * FaceLoops.ms(mood: "proud", state: "task_complete")
        XCTAssertEqual(schedule.playMs(face, now: 100), overCheer)
        schedule.brain(face, now: 100)
        schedule.brain(face, now: 100)
        let due = schedule.due(now: 100)
        XCTAssertEqual(due.play, face, "it plays over the cheer")
        XCTAssertEqual(schedule.lineUntil, 100 + overCheer, "the next waits for its face")
        XCTAssertEqual(due.next, 100 + overCheer)
        schedule.rule(DeviceMoment(anim: "wiggle"), now: 200)
        XCTAssertEqual(schedule.cheerUntil, 200, "a wiggle ends the cheer")
        XCTAssertEqual(schedule.lineUntil, 200, "and the face")
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

/// Waits up to `timeout` for `condition`, checking every 20 ms, then checks
/// it: how every test waits on another thread.
func eventually(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    XCTAssertTrue(condition(), what)
}
