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
        XCTAssertTrue(runtime.home.sync { runtime.pipeline.brain })
        runtime.reloadBrain(jevKey: nil)
        eventually("none when Settings clears it") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertFalse(runtime.home.sync { runtime.pipeline.brain }, "so no event wakes it")
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

        // A finished turn clears "needs you", and the brain cheers it (no
        // rule does, BEHAVIORS.md §3.1).
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's cheer") {
            transport.sent.contains { $0.hasPrefix(#"{"t":"moment","anim":"cheer","say":"#) && $0.contains(#""mood":"excited""#) }
        }
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
            "react.mood": Answer(choice: "grumpy", probabilities: ["grumpy": 0.6]),
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
        eventually("the log line") { lines.lock.withLock { lines.log.contains { $0.hasPrefix("brain turn start ") && $0.hasSuffix("→ mood, react") } } }
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

    /// harness/HARNESS.md §9: a bug report, debug mode or not, holds this
    /// launch's debug lines (a pass's whole state included), the log's end,
    /// the settings and mood files, and the status in `about.json`.
    func testABugReportKeepsEverythingOutsideDebugMode() throws {
        let transport = FakeTransport()
        let runtime = try Runtime(options(transport, brain: ScriptedBrain(id: "scripted", always: [
            "react.mood": Answer(choice: "grumpy", probabilities: ["grumpy": 1]),
        ])))
        try Data("an old line\n".utf8).write(to: dir.appendingPathComponent("boop.log"))
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        eventually("the brain") { runtime.home.sync { statuses.last?.brain == "scripted" } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":"#) } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(DebugLog.fileName).path),
                       "no debug.jsonl outside debug mode")
        let saved = Lines()
        runtime.saveReport { saved.add($0?.path ?? "none") }
        eventually("the report") { !saved.all.isEmpty }
        let report = URL(fileURLWithPath: saved.all[0])
        XCTAssertEqual(report.deletingLastPathComponent().lastPathComponent, Runtime.reportsDir)
        let lines = try String(contentsOf: report.appendingPathComponent(DebugLog.fileName), encoding: .utf8).split(separator: "\n")
        XCTAssertTrue(lines[0].hasPrefix(#"{"questions":"#), "the questions first")
        XCTAssertTrue(lines.contains { $0.contains(#""pass":"#) && $0.contains("PERSONALITY") }, "a pass with its whole state")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"sent":"#) }, "the lines sent to the device")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"status":"#) }, "the status")
        try XCTAssertEqual(String(contentsOf: report.appendingPathComponent("boop.log"), encoding: .utf8), "an old line\n")
        let about = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: report.appendingPathComponent("about.json"))) as? [String: Any])
        XCTAssertEqual(about["brain"] as? String, "scripted")
        XCTAssertEqual(about["connected"] as? Bool, true)
    }

    /// harness/HARNESS.md §9: the report's lines are capped at
    /// `DebugLog.Recent.maxBytes`, the oldest let go first.
    func testRecentLinesAreCapped() {
        let recent = DebugLog.Recent()
        let line = String(repeating: "x", count: 1023)
        for _ in 0..<(DebugLog.Recent.maxBytes / 1024 + 5000) { recent.add(line) }
        recent.add("last")
        XCTAssertEqual(recent.kept.last, "last")
        XCTAssertLessThanOrEqual(recent.kept.reduce(0) { $0 + $1.utf8.count + 1 }, DebugLog.Recent.maxBytes)
        XCTAssertGreaterThan(recent.kept.count, DebugLog.Recent.maxBytes / 1024 - 2)
    }

    /// harness/HARNESS.md §9: debug mode logs every hook with what it became
    /// and every line to the device, starts debug.jsonl afresh with every
    /// entry (keeping the last launch's as debug.1.jsonl), and prints them
    /// readably, but Jev's state stays out of boop.log.
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
                      "each launch starts afresh, with the questions first")
        XCTAssertEqual(file(), lastLaunch, "in place, so a boopdev watch on it sees it start again")
        try XCTAssertEqual(String(contentsOf: DebugLog.kept(1, of: debugLog), encoding: .utf8), "{\"seq\":1}\n",
                       "the last launch's lines are kept as debug.1.jsonl")

        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("PreToolUse", tool: "Bash"), to: socketPath))
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the pass in debug.jsonl") { self.debugLines().contains { ($0["event"] as? [String: Any])?["type"] as? String == "action" } }
        let log = lines.lock.withLock { lines.log }
        let printed = lines.lock.withLock { lines.printed }
        XCTAssertTrue(log.contains("hook: claude SessionStart s1 → session start SessionStart claude s1"), "\(log)")
        XCTAssertTrue(log.contains("hook: claude PreToolUse s1 → tool start PreToolUse claude s1 · tool Bash"), "\(log)")
        XCTAssertTrue(log.contains { $0.hasPrefix("link rules → ") })
        XCTAssertFalse(log.contains { $0.contains("How to read HISTORY") }, "the state stays out of boop.log")
        XCTAssertTrue(printed.contains { $0.hasPrefix("▸ 1 turn start: claude started turn 1") }, "\(printed)")
        let pass = try XCTUnwrap(printed.first { $0.hasPrefix("  pass scripted") })
        XCTAssertTrue(pass.contains("react.mood excited 1.00"), pass)
        XCTAssertTrue(pass.contains("    │ You are the mind of Boop"), "the first state in full")
        XCTAssertTrue(printed.contains("  … react: Boop made an excited face, held once, and mumbled \"…yay!\""), "started: \(printed)")
        XCTAssertTrue(printed.contains { $0.hasPrefix("  ✗ react (") && $0.hasSuffix(") didn't happen: no device connected") },
                      "the fake device never connected: \(printed)")
        let p = try XCTUnwrap(debugLines().compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue((p["state"] as? String)?.hasPrefix("You are the mind of Boop") == true)
        XCTAssertEqual(p["questions"] as? [String], ["mood", "react.mood", "react.animation", "react.loops", "word.feeling", "word.about"])
    }

    /// harness/HARNESS.md §9: each launch keeps the last one's lines as
    /// debug.1.jsonl and moves the older ones up, keeping 10 launches in
    /// all; an empty file (a launch that wrote nothing) isn't kept.
    func testDebugModeKeepsTheLastTenLaunches() throws {
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        XCTAssertEqual(DebugLog.keptLaunches, 10)
        XCTAssertEqual(DebugLog.kept(3, of: debugLog).lastPathComponent, "debug.3.jsonl")
        func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for launch in 1...12 {
            try Data("launch \(launch)\n".utf8).write(to: debugLog)
            DebugLog.start(debugLog)
            XCTAssertEqual(text(debugLog), "", "launch \(launch) starts afresh")
        }
        for n in 1...10 { XCTAssertEqual(text(DebugLog.kept(n, of: debugLog)), "launch \(13 - n)\n", "debug.\(n).jsonl") }
        XCTAssertNil(text(DebugLog.kept(11, of: debugLog)), "the oldest is let go")
        DebugLog.start(debugLog)
        XCTAssertEqual(text(DebugLog.kept(1, of: debugLog)), "launch 12\n", "an empty file isn't kept")
    }

    /// The lines of this runtime's debug.jsonl, as JSON objects.
    func debugLines() -> [[String: Any]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    /// The actions this runtime's debug.jsonl recorded, as events.
    func debugActions() -> [Event] {
        debugLines().compactMap { ($0["event"] as? [String: Any]).flatMap(Event.init(json:)) }.filter { $0.type == .action }
    }

    var socketPath: String { dir.appendingPathComponent("boop.sock").path }

    func dev(_ json: String) {
        XCTAssertTrue(HookSocket.send(Data((json + "\n").utf8), to: socketPath))
    }

    /// harness/HARNESS.md §9: debug mode also writes the
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
        XCTAssertEqual(questions.map { $0["key"] as? String }, ["mood", "react.mood", "react.animation", "react.loops", "word.feeling", "word.about"])
        XCTAssertEqual(questions.map { $0["action"] as? String }, ["mood", "react", "react", "react", "react", "react"])
        XCTAssertEqual(questions[1]["text"] as? String, "How should Boop react to NOW, if at all? It makes this mood's face for a moment, with a mumble.")
        let none = try XCTUnwrap((questions[1]["options"] as? [[String: Any]])?.first)
        XCTAssertEqual(none["name"] as? String, "none")
        XCTAssertEqual(none["what"] as? String, "Stay quiet: nothing in NOW is worth a face and a mumble, "
                       + "or HISTORY shows Boop still making the one it calls for (in progress).")
        XCTAssertEqual(none["not_for"] as? String, "Anything PERSONALITY's Examples react to that Boop isn't already doing.")
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

    /// The dashboard's dev lines. A forced pass needs no
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

        dev(#"{"dev":"answer","answers":{"react.mood":"grumpy","word.feeling":"again"}}"#)
        eventually("a mumble with no brain") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":"#) && $0.contains(#""word":"again""#) } }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        eventually("grumpy") { runtime.home.sync { runtime.mood.current == "grumpy" } }
        dev(#"{"dev":"mood","mood":"happy"}"#)
        eventually("happy again") { runtime.home.sync { runtime.mood.current == "happy" } }
        dev(#"{"dev":"moment","anim":"cheer"}"#)
        eventually("the cheer") { transport.sent.contains(#"{"t":"moment","anim":"cheer"}"#) }
        dev(#"{"dev":"moment","anim":"dance"}"#)
        dev(#"{"dev":"moment"}"#)
        dev(#"{"dev":"moment","anim":"wiggle"}"#)
        eventually("the wiggle after them") { transport.sent.contains(#"{"t":"moment","anim":"wiggle"}"#) }
        XCTAssertFalse(transport.sent.contains { $0.contains("dance") || $0 == #"{"t":"moment"}"# })

        let lines = debugLines()
        let pass = try XCTUnwrap(lines.compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue(pass["for"] is NSNull)
        XCTAssertEqual(pass["by"] as? String, "dashboard")
        XCTAssertEqual(pass["questions"] as? [String], ["react.mood", "word.feeling"])
        XCTAssertEqual((pass["answers"] as? [String: [String: Any]])?["react.mood"]?["p"] as? [String: Double], ["grumpy": 1])
        let actions = debugActions().filter { $0.phase != .end && $0["by"] == "dashboard" }
        XCTAssertEqual(actions.map { $0["message"]?.string }, [#"Boop made a grumpy face, held once, and mumbled "…again!""#,
                                                              "Boop's mood changed: happy → grumpy.",
                                                              "Boop's mood changed: grumpy → happy."])
        XCTAssertEqual(actions.map(\.specificType), ["react", "mood", "mood"])
        for action in actions { XCTAssertEqual(action["for"], .null) }
        let moods = lines.compactMap { ($0["sent"] as? [String: Any])?["mood"] as? String }
        XCTAssertEqual(moods.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, ["happy", "grumpy", "happy"],
                       "the device hears each change in a state")
    }

    /// A forced react keeps its own rules, so it's refused
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
        dev(#"{"dev":"answer","answers":{"react.mood":"happy"}}"#)
        eventually("the refusal") { self.debugActions().contains { $0["message"] == "something needs you" } }
        let action = try XCTUnwrap(debugActions().last { $0.specificType == "react" })
        XCTAssertEqual(action["ok"], false)
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
        XCTAssertEqual(files, ["guide.md", "mood/determined.md", "mood/excited.md", "mood/grumpy.md",
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
        XCTAssertEqual(Self.steering.personality(.boop).rules, Personality.Rules(workBeatMs: 120_000...240_000, toolUses: .notable))
        XCTAssertEqual(Self.steering.personality(.chatter).rules, Personality.Rules(workBeatMs: 30_000...60_000, toolUses: .all))
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
        XCTAssertEqual(runtime.home.sync { runtime.view.config.rules.toolUses }, .all)
        XCTAssertEqual(AppSettings.load(from: dir).personality, .chatter)
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// no rule cheers; the brain's reaction does, as one moment with the
    /// cheer, its face and its mumble (BEHAVIORS.md §3.1, §5).
    func testTheBrainCheersAFinish() throws {
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
        eventually("the start's mumble") { transport.sent.contains { $0.contains("\"say\"") } }
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        XCTAssertFalse(moments().contains { $0.contains("\"anim\"") }, "a start gets no cheer")
        transport.endMoments()  // the device says it has played
        eventually("the start's mumble has played") { runtime.home.sync { runtime.moments.schedule.idle(now: runtime.options.clock()) } }
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":30000}"#.utf8), to: socketPath))
        eventually("clock moved") { skew.now == 30_000 }
        let before = moments().count
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's cheer", timeout: 4) { moments().count >= before + 1 }
        let cheer = moments()[before]
        XCTAssertTrue(cheer.hasPrefix(#"{"t":"moment","anim":"cheer","say":"#), "one moment: \(cheer)")
        XCTAssertTrue(cheer.contains(#""mood":"excited","loops":1,"variant":"#) && cheer.contains(#""id":"#), "in its face, held once, a variation, waited on: \(cheer)")
        XCTAssertEqual(moments().count, before + 1, "no rule cheer besides")
    }

    /// ARCHITECTURE.md §3.2: the brain's moments play one at a time, each
    /// after any line playing, so none cuts off a line or another of the
    /// brain's mumbles; a mumble plays over an animation, which doesn't cut
    /// it; a newer line pushes them back and an animation stops the line;
    /// one that waited over 5 s is dropped. One sent to the device holds
    /// the line for chatter until the device says it ended, and for the
    /// brain's next until its mumble has played, or its `ended` if sooner.
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
        schedule.hold(id: 1, mumble, now: 500, until: 500 + schedule.playMs(mumble, now: 500) + Runtime.Moments.endGraceMs)
        XCTAssertEqual(schedule.next, 500 + 1920 + MomentSchedule.linkSlackMs, "the second waits for the first's mumble")
        XCTAssertFalse(schedule.idle(now: 2000), "chatter waits for both")
        XCTAssertNil(schedule.due(now: 2000).play)
        schedule.ended(id: 2, now: 2200)
        XCTAssertNil(schedule.due(now: 2200).play, "another moment's end")
        schedule.ended(id: 1, now: 2300)
        due = schedule.due(now: 2300)
        XCTAssertEqual(due.play, mumble, "then the second, once the device says the first is over")
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
                XCTAssertEqual(runtime.harness.force(["react.mood": "happy"]).map(\.name), ["react"])
                let seq = try XCTUnwrap(runtime.pipeline.transcript.events.last { $0.type == .action && $0.specificType == "react" && $0.phase != .end }?.seq)
                return (seq, try XCTUnwrap(transport.sent.last { $0.hasPrefix(#"{"t":"moment""#) }))
            }
        }
        func end(of seq: Int) -> Pending.End? {
            runtime.home.sync {
                runtime.pipeline.transcript.events.first { $0.phase == .end && $0["for"] == .int(Int64(seq)) }.map(Self.end)
            }
        }

        let alone = try react()
        XCTAssertEqual(end(of: alone.seq), .failed("no device connected"))
        XCTAssertFalse(alone.moment.contains(#""id""#), "sent all the same, and dropped, with nothing to wait on")
        XCTAssertEqual(runtime.home.sync { runtime.moments.schedule.look }, "asleep",
                       "the look of the last state, which times the face: no sessions")

        clock.now += 10_000
        connection(true)
        let id = runtime.home.sync { runtime.moments.lastId }  // this launch's ids count up from here
        let played = try react()
        XCTAssertTrue(played.moment.hasSuffix(#","mood":"happy","loops":1,"id":\#(id + 1)}"#), played.moment)
        clock.now = runtime.home.sync { runtime.moments.schedule.lineUntil }
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: played.seq), "played by the app's reckoning, but the device hasn't said so")
        device(#"{"t":"ended","id":\#(id + 1),"how":"done"}"#)
        XCTAssertEqual(end(of: played.seq), .done)
        XCTAssertTrue(runtime.home.sync { runtime.moments.playing.isEmpty })

        let tapped = try react()
        XCTAssertTrue(tapped.moment.hasSuffix(#","id":\#(id + 2)}"#))
        device(#"{"t":"ended","id":\#(id + 99),"how":"done"}"#)
        XCTAssertNil(end(of: tapped.seq), "another id: ignored")
        device(#"{"t":"ended","id":\#(id + 2),"how":"cut","why":"tap"}"#)
        XCTAssertEqual(end(of: tapped.seq), .failed("cut short: you tapped Boop"))
        device(#"{"t":"ended","id":\#(id + 2),"how":"done"}"#)
        XCTAssertEqual(end(of: tapped.seq), .failed("cut short: you tapped Boop"), "only the first end counts")

        let skipped = try react()
        device(#"{"t":"ended","id":\#(id + 3),"how":"skipped"}"#)
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
        device(#"{"t":"ended","id":\#(id + 4),"how":"done"}"#)
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
    /// by the app's own reckoning (its wait for a turn, a pump running
    /// late, its length and the grace for the device's `ended`) before the
    /// harness's ceiling would end it. The loops are the designs' (`FaceLoops`), so a new design
    /// with a long loop fails here rather than in HISTORY.
    func testAReactionEndsBeforeTheHarnessCeiling() {
        let slow = VoiceLine(groups: [Array(repeating: "zzz", count: 8)], word: "finally", at: 8, tune: .bounce, ms: 400)
        let held = ReactAction.holds.count
        let longest = MoodAction.moods.map(\.name).flatMap { mood in
            FaceLoops.states.flatMap { look in
                (1...FaceLoops.count(state: look)).map {
                    DeviceMoment(say: slow, mood: mood, loops: held).playMs(look: look, mood: mood, lookVariant: $0)
                }
            }
        }.max() ?? 0
        XCTAssertGreaterThanOrEqual(longest, Int64(held) * FaceLoops.longest)
        XCTAssertLessThan(MomentSchedule.maxWaitMs + MomentSchedule.lateMs + longest + Runtime.Moments.endGraceMs,
                          Harness.pendingMaxMs)
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
    /// showing: the look and mood of the last `state`, or, while a cheer
    /// may be playing (until its end and `linkSlackMs` more), the longer of
    /// the look's and the cheer's, since the device may time it by either.
    /// A reaction's face holds the brain's next one back. A wiggle, the
    /// rules' or a tap's, ends the cheer, the line and the face.
    func testTheScheduleTimesAMomentByTheDesignShowing() {
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)
        let proud = DeviceMoment(say: line, mood: "proud", loops: 2)
        let excited = DeviceMoment(say: line, mood: "excited", loops: 2)
        let loop = { (mood: String, state: String, variant: Int) in 2 * FaceLoops.ms(mood: mood, state: state, variant: variant) }
        // Idle's second variation loops longer than the cheer, its first shorter.
        XCTAssertGreaterThan(loop("proud", "idle", 2), loop("proud", "task_complete", 1))
        XCTAssertLessThan(loop("excited", "idle", 1), loop("excited", "task_complete", 1))
        var schedule = MomentSchedule()
        schedule.look = "idle"
        schedule.lookVariant = 2
        var short = MomentSchedule()
        short.look = "idle"
        XCTAssertNil(schedule.cheerUntil)
        XCTAssertEqual(schedule.playMs(proud, now: 0), loop("proud", "idle", 2))
        XCTAssertEqual(short.playMs(excited, now: 0), loop("excited", "idle", 1))
        schedule.rule(DeviceMoment(anim: "cheer", loops: 1), now: 0)
        short.rule(DeviceMoment(anim: "cheer", loops: 1), now: 0)
        let cheer = FaceLoops.ms(mood: "happy", state: "task_complete")
        XCTAssertEqual(schedule.cheerUntil, cheer)
        XCTAssertEqual(MomentSchedule.linkSlackMs, 500)
        for now in [100, cheer + MomentSchedule.linkSlackMs - 1] {
            XCTAssertEqual(schedule.playMs(proud, now: now), loop("proud", "idle", 2), "the longer: the look's")
            XCTAssertEqual(short.playMs(excited, now: now), loop("excited", "task_complete", 1), "the longer: the cheer's")
        }
        XCTAssertEqual(short.playMs(excited, now: cheer + MomentSchedule.linkSlackMs), loop("excited", "idle", 1),
                       "the cheer is over on the device too")
        schedule.brain(proud, now: 100)
        schedule.brain(proud, now: 100)
        let due = schedule.due(now: 100)
        XCTAssertEqual(due.play, proud, "it plays over the cheer")
        XCTAssertEqual(schedule.lineUntil, 100 + loop("proud", "idle", 2), "the next waits for its face")
        XCTAssertEqual(due.next, 100 + MomentSchedule.maxWaitMs + 1, "or until the next has waited too long")
        schedule.rule(DeviceMoment(anim: "wiggle"), now: 200)
        XCTAssertEqual(schedule.cheerUntil, 200, "a wiggle ends the cheer")
        XCTAssertEqual(schedule.lineUntil, 200, "and the face")
        XCTAssertEqual(schedule.busyUntil, 200 + DeviceMoment.wiggleMs, "while it plays")

        // A tap's wiggle, which the device plays on its own, does the same.
        var tapped = MomentSchedule()
        tapped.rule(DeviceMoment(anim: "cheer", loops: 1), now: 0)
        tapped.brain(proud, now: 100)
        _ = tapped.due(now: 100)
        tapped.tapped(now: 300)
        XCTAssertEqual(tapped.cheerUntil, 300)
        XCTAssertEqual(tapped.lineUntil, 300)
        XCTAssertEqual(tapped.playMs(excited, now: 300 + MomentSchedule.linkSlackMs), loop("excited", "idle", 1),
                       "timed by the look's design once the tap is heard")
    }

    /// PROTOCOL.md §3–4, ARCHITECTURE.md §3.2: a brain moment sent to the
    /// device holds the line until the device's `ended` for it, or until
    /// the app stops waiting for that (its length and `endGraceMs`); then
    /// the next one's turn comes. A rule's animation or a tap stops it on
    /// the device, and "needs you" starting stops everything; while
    /// something needs you, the device plays none of the rules' moments.
    func testTheDeviceSaysWhenTheLineIsFree() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let face = DeviceMoment(say: line, mood: "proud")
        func sent(_ schedule: inout MomentSchedule, at now: Int64, id: Int) -> Int64 {
            XCTAssertEqual(schedule.due(now: now).play, face)
            let until = now + schedule.playMs(face, now: now) + Runtime.Moments.endGraceMs
            schedule.hold(id: id, face, now: now, until: until)
            return until
        }
        var schedule = MomentSchedule()
        schedule.brain(face, now: 0)
        let until = sent(&schedule, at: 0, id: 7)
        XCTAssertEqual(schedule.lineFree, until, "until its ended, at the latest when the app gives up on it")
        XCTAssertEqual(schedule.busyUntil, until, "chatter waits too")
        schedule.brain(face, now: 1000)
        schedule.ended(id: 7, now: 1500)
        XCTAssertEqual(schedule.lineFree, 1500)
        XCTAssertEqual(schedule.due(now: 1500).play, face, "its turn")

        // No `ended`: the line is free once the app stops waiting for it.
        var silent = MomentSchedule()
        silent.brain(face, now: 0)
        let deadline = sent(&silent, at: 0, id: 1)
        XCTAssertFalse(silent.idle(now: deadline - 1))
        XCTAssertNil(silent.due(now: deadline).play)
        XCTAssertTrue(silent.idle(now: deadline))

        // A rule's animation frees it; so does "needs you". A tap leaves it
        // to the moment's `ended`, which the device sends at once for a
        // moment its tap cut.
        for free in ["cheer", "tap", "needs you"] {
            var cut = MomentSchedule()
            cut.brain(face, now: 0)
            let held = sent(&cut, at: 0, id: 1)
            cut.brain(face, now: 500)
            switch free {
            case "cheer": cut.rule(DeviceMoment(anim: "cheer"), now: 1000)
            case "tap":
                cut.tapped(now: 1000)
                XCTAssertEqual(cut.lineFree, held, "a tap alone")
                XCTAssertNil(cut.due(now: 1000).play)
                cut.ended(id: 1, now: 1000)
            default: cut.show(look: "idle", mood: "happy", attn: true, now: 1000)
            }
            XCTAssertEqual(cut.lineFree, 1000, free)
            XCTAssertEqual(cut.due(now: 1000).play, face, free)
        }

        // While something needs you the device plays no rule moment, and a
        // tap only dips the face: the schedule keeps what it had.
        var held = MomentSchedule()
        held.show(look: "idle", mood: "happy", attn: true, now: 0)
        held.rule(DeviceMoment(anim: "cheer"), now: 100)
        held.tapped(now: 200)
        XCTAssertNil(held.cheerUntil)
        XCTAssertEqual(held.busyUntil, 0)
        held.show(look: "idle", mood: "happy", attn: false, now: 300)
        held.rule(DeviceMoment(anim: "cheer"), now: 400)
        XCTAssertEqual(held.cheerUntil, 400 + FaceLoops.ms(mood: "happy", state: "task_complete"), "answered: it plays")

        // Nothing plays with no device: `stop` frees everything.
        var gone = MomentSchedule()
        gone.brain(face, now: 0)
        _ = sent(&gone, at: 0, id: 1)
        gone.stop(now: 10)
        XCTAssertEqual(gone.busyUntil, 10)
    }

    /// harness/DECISIONS.md §5, ARCHITECTURE.md §3.2 (the owner's call,
    /// 2026-09-28): a reaction's face held on for its loops holds up the
    /// brain's next reaction only until its mumble has played (and
    /// `linkSlackMs`). The next is sent then, not dropped at 5 s, and
    /// replaces the face; the device says the first was done, and it
    /// settles done. Chatter still waits for the face's `ended`.
    func testTheNextReactionReplacesAHeldFace() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let held = DeviceMoment(say: line, mood: "proud", loops: 4)  // its line is 1920 ms
        let next = DeviceMoment(say: line, mood: "grumpy")
        XCTAssertEqual(MomentSchedule.linkSlackMs, 500)
        XCTAssertEqual(held.sayMs, 1920)
        let moments = Runtime.Moments()
        moments.schedule.lookVariant = 2  // idle's second variation, a long loop
        var ends: [String: Pending.End] = [:]
        let first = Pending(), second = Pending()
        first.bind { ends["first"] = $0 }
        second.bind { ends["second"] = $0 }
        moments.schedule.brain(held, first, now: 0)
        var play = moments.schedule.due(now: 0)
        XCTAssertEqual(play.play, held, "the first plays at once")
        guard var sent = play.play else { return }
        moments.send(&sent, first, now: 0)
        let faceEnds = 4 * FaceLoops.ms(mood: "proud", state: "idle", variant: 2)
        XCTAssertGreaterThanOrEqual(faceEnds, 16_000, "a face held four times over the idle look")
        XCTAssertEqual(moments.schedule.lineFree, faceEnds + Runtime.Moments.endGraceMs)

        moments.schedule.brain(next, second, now: 1000)
        XCTAssertEqual(moments.schedule.next, 1920 + 500, "asked back once the first's mumble has played")
        XCTAssertNil(moments.schedule.due(now: 2419).play)
        play = moments.schedule.due(now: 2420)
        XCTAssertEqual(play.play, next, "sent then, over the held face")
        XCTAssertEqual(play.dropped, [])
        guard var replacing = play.play else { return }
        moments.send(&replacing, second, now: 2420)
        XCTAssertFalse(moments.schedule.idle(now: 2420 + 1920), "chatter waits for the second's ended")

        // The device ends the first at once, done: its line had played.
        moments.ended(MomentEnded(id: sent.id!, how: .done, why: nil), now: 2450)
        XCTAssertEqual(ends, ["first": .done])
        XCTAssertEqual(moments.schedule.holder?.id, replacing.id, "the second holds the line")
    }

    /// ARCHITECTURE.md §3.2: a brain moment's wait is counted to when its
    /// turn came, so a pump that runs a little late (up to `lateMs`) doesn't
    /// drop it; one that runs later counts to now. One still waiting past
    /// 5 s is dropped at once, not when the line frees, and the pump is
    /// asked back for that.
    func testAWaitIsCountedToItsTurn() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        let face = DeviceMoment(say: line, mood: "proud")
        let chatter = DeviceMoment(say: line)  // 1920 ms
        XCTAssertEqual(MomentSchedule.lateMs, 1000)
        func schedule() -> MomentSchedule {
            var s = MomentSchedule()
            s.rule(chatter, now: 2920)  // its line ends at 4840
            s.brain(face, now: 0)
            return s
        }
        var late = schedule()
        XCTAssertEqual(late.next, 4840)
        XCTAssertEqual(late.due(now: 5160).play, face, "its turn came at 4.84 s: the pump ran 0.32 s late")
        var later = schedule()
        XCTAssertEqual(later.due(now: 4840 + MomentSchedule.lateMs + 1).dropped, [face], "too late to count from its turn")

        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        var stuck = MomentSchedule()
        stuck.lookVariant = 2  // idle's second variation, a long loop
        stuck.brain(DeviceMoment(say: line, mood: "proud", loops: 4), now: 0)
        XCTAssertNotNil(stuck.due(now: 0).play)
        XCTAssertEqual(stuck.lineUntil, 4 * FaceLoops.ms(mood: "proud", state: "idle", variant: 2), "a long face")
        stuck.brain(face, pending, now: 1000)
        XCTAssertEqual(stuck.next, 1000 + MomentSchedule.maxWaitMs + 1, "asked back when it's too old")
        XCTAssertNil(stuck.due(now: 6000).play)
        XCTAssertEqual(ends, [], "5 s isn't over 5 s")
        let due = stuck.due(now: 6001)
        XCTAssertEqual(due.dropped, [face], "dropped while the line is still busy")
        XCTAssertEqual(ends, [.failed("waited too long")])
        XCTAssertNil(due.next)
    }

    /// ARCHITECTURE.md §3.2, PROTOCOL.md §4: whatever frees the line sends
    /// the brain's next moment at once, rather than when the app's own
    /// reckoning of the last one runs out: the device's `ended` for the one
    /// playing, a rule's animation, a tap, whose wiggle the device plays on
    /// its own, or "needs you" starting, which stops everything there.
    /// After a tap stops the cheer, a face is timed by the look's design, as
    /// the device times it. With no device connected a reaction doesn't
    /// happen and leaves the line free for the next.
    func testWhatFreesTheLineSendsTheNextAtOnce() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) }.count }
        func react(_ mood: String) {
            runtime.home.sync { _ = runtime.harness.force(["react.mood": mood, "react.loops": "twice"]) }
        }
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        func ends() -> [Pending.End] {
            runtime.home.sync {
                runtime.pipeline.transcript.events.filter { $0.phase == .end && $0.specificType == "react" }.map(Self.end)
            }
        }

        react("proud")
        XCTAssertEqual(moments(), 1, "plays at once")
        clock.now += 1000
        react("happy")
        XCTAssertEqual(moments(), 1, "waits for the first's face")
        device(#"{"t":"ended","id":\#(transport.momentIds[0]),"how":"done"}"#)
        XCTAssertEqual(moments(), 2, "the device says the first is over: the second goes at once")

        clock.now += 1000
        react("grumpy")
        XCTAssertEqual(moments(), 2, "waits for the second")
        runtime.home.sync { runtime.playRule(DeviceMoment(anim: "cheer", loops: 1)) }
        XCTAssertEqual(moments(), 4, "a cheer the dashboard played stops the second, and the third plays over the cheer")

        clock.now += 300
        react("excited")
        XCTAssertEqual(moments(), 4, "waits for the third")
        device(#"{"t":"input","k":"tap"}"#)
        XCTAssertEqual(moments(), 4, "the tap's wiggle may have come before the third arrived")
        device(#"{"t":"ended","id":\#(transport.momentIds[2]),"how":"cut","why":"tap"}"#)
        XCTAssertEqual(moments(), 5, "the device says the tap stopped the third")
        let look = runtime.home.sync { runtime.moments.schedule.look }
        let deadline = try XCTUnwrap(runtime.home.sync { runtime.moments.playing.last?.deadline })
        XCTAssertGreaterThanOrEqual(deadline - clock.now - Runtime.Moments.endGraceMs, 2 * FaceLoops.ms(mood: "excited", state: look),
                                    "the look's design, not the cheer's")
        XCTAssertEqual(ends(), [.done, .failed("cut short: you tapped Boop")], "the second still to hear from the device")

        clock.now += 300
        react("sad")
        XCTAssertEqual(moments(), 5, "waits for the fourth")
        let calm = runtime.home.sync { runtime.core.snapshot(at: clock.now) }
        var needsYou = calm
        needsYou.attn = .init(agent: "claude", project: "jetpack", more: 0)
        runtime.home.sync { runtime.show(needsYou) }
        XCTAssertEqual(moments(), 6, "\"needs you\" stops the fourth on the device: the fifth goes at once, for it to skip")
        runtime.home.sync { runtime.show(calm) }

        transport.onConnection?(false)
        runtime.home.sync {}
        XCTAssertEqual(ends().count, 5, "the three it was waiting on didn't happen")
        // The fifth may play on the device, and holds the line until the
        // app gives up on it; after that nothing is playing.
        clock.now = try XCTUnwrap(runtime.home.sync { runtime.moments.schedule.holder?.until })
        runtime.home.sync { runtime.tick() }
        react("happy")
        react("sad")
        XCTAssertEqual(Array(ends().suffix(2)), [.failed("no device connected"), .failed("no device connected")],
                       "nothing played the first, so the second didn't wait for it")
    }

    /// ARCHITECTURE.md §3.2: "needs you" stops the cheer and any line on
    /// the device and plays nothing while it shows (BEHAVIORS.md §1), so
    /// the schedule stops timing them: a reaction after it is timed on the
    /// look's design, not the cheer's, and doesn't wait for a line that
    /// was cut.
    func testNeedsYouEndsWhatTheScheduleThoughtWasPlaying() {
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)
        let face = DeviceMoment(say: line, mood: "proud", loops: 2)
        var schedule = MomentSchedule()
        schedule.rule(DeviceMoment(anim: "cheer", loops: 1), now: 0)
        schedule.brain(face, now: 0)
        XCTAssertEqual(schedule.due(now: 0).play, face)
        schedule.show(look: "idle", mood: schedule.mood, attn: true, now: 300)
        XCTAssertEqual(schedule.cheerUntil, 300)
        XCTAssertEqual(schedule.lineUntil, 300)
        XCTAssertTrue(schedule.idle(now: 300))
        XCTAssertEqual(schedule.playMs(face, now: 300 + MomentSchedule.linkSlackMs),
                       2 * FaceLoops.ms(mood: "proud", state: "idle"), "the look's design: the cheer was cut")
    }

    /// ARCHITECTURE.md §3.2: a brain moment that can no longer play in
    /// time is dropped once it has waited 5 s, even while a face holds the
    /// turn, and the schedule asks again when the first waiting one's 5 s
    /// run out.
    func testAWaitingMomentIsDroppedAtFiveSecondsWhateverPlays() {
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)
        let long = DeviceMoment(say: line, mood: "proud", loops: 4)
        let next = DeviceMoment(say: line, mood: "happy")
        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        var schedule = MomentSchedule()
        schedule.lookVariant = 2  // idle's second variation, a long loop
        schedule.brain(long, now: 0)
        XCTAssertEqual(schedule.due(now: 0).play, long)
        XCTAssertGreaterThan(schedule.lineUntil, 30_000, "four loops of the idle design")
        schedule.brain(next, pending, now: 500)
        let early = schedule.due(now: 1000)
        XCTAssertNil(early.play)
        XCTAssertEqual(early.next, 500 + MomentSchedule.maxWaitMs + 1, "when it has waited too long")
        let due = schedule.due(now: 5501)
        XCTAssertEqual(due.dropped, [next])
        XCTAssertEqual(ends, [.failed("waited too long")])
        XCTAssertNil(due.next, "nothing waits")
    }

    /// ARCHITECTURE.md §3.2: what the device does on its own reaches the
    /// schedule. A tap's wiggle replaces a cheer the dashboard played, and
    /// such a cheer lets a reaction waiting behind a face play at once,
    /// over it;
    /// and each tick drops a reaction that has waited 5 s, before the
    /// harness's ceiling could end it, whatever the pump's timer does
    /// (a clock jump, or the Mac asleep).
    func testTheScheduleFollowsTapsCheersAndTicks() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)

        runtime.home.sync { runtime.playRule(DeviceMoment(anim: "cheer")) }
        clock.now += 300
        transport.onLine?(#"{"t":"input","k":"tap"}"#)
        runtime.home.sync {}
        XCTAssertEqual(runtime.home.sync { runtime.moments.schedule.cheerUntil }, clock.now, "the wiggle replaced it")
        clock.now += 1000
        runtime.home.sync { runtime.playRule(DeviceMoment(anim: "cheer")) }
        clock.now += 300
        let asking = StateSnapshot(base: "idle", mood: "happy", attn: .init(agent: "claude", project: "x", more: 0, id: 1),
                                   busy: 0, vol: 6)
        runtime.home.sync { runtime.run([.state(asking)]) }
        XCTAssertEqual(runtime.home.sync { runtime.moments.schedule.cheerUntil }, clock.now, "needs you stopped it")
        runtime.home.sync { runtime.run([.state(sampleSnapshot())]) }

        let long = DeviceMoment(say: line, mood: "proud", loops: 2)
        let waiting = DeviceMoment(say: line, mood: "happy")
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) } }
        runtime.home.sync {
            runtime.moments.schedule.brain(long, now: clock.now)
            runtime.moments.schedule.brain(waiting, now: clock.now)
            Runtime.pump(runtime.moments, link: runtime.link, clock: runtime.options.clock, home: runtime.home,
                         log: runtime.options.log)
        }
        XCTAssertTrue(moments().last?.contains(#""mood":"proud""#) == true)
        clock.now += 1000
        let before = moments().count
        runtime.home.sync { runtime.playRule(DeviceMoment(anim: "cheer")) }
        XCTAssertEqual(moments().count, before + 2, "the cheer, then the waiting reaction over it")
        XCTAssertTrue(moments().last?.contains(#""mood":"happy""#) == true)

        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        runtime.home.sync {
            runtime.moments.schedule.brain(DeviceMoment(say: line, mood: "sad"), pending, now: clock.now)
        }
        clock.now += 60_000  // the clock jumps; the pump's timer runs on uptime and hasn't fired
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(ends, [.failed("waited too long")])
    }

    /// ARCHITECTURE.md §3.2: the device ends a face on its design's loop
    /// boundary, up to a loop sooner than the app reckons. Its `ended` for
    /// the moment holding the turn frees the turn then, so the next
    /// reaction plays at once; an `ended` for another id doesn't.
    func testTheDevicesEndedFreesTheTurn() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        let line = VoiceLine(groups: [["bi"]], word: nil, at: 1, tune: .up, ms: 100)
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) } }
        runtime.home.sync {
            runtime.moments.schedule.brain(DeviceMoment(say: line, mood: "proud", loops: 4), Pending(), now: clock.now)
            runtime.moments.schedule.brain(DeviceMoment(say: line, mood: "happy"), Pending(), now: clock.now)
            runtime.pump()
        }
        let first = try XCTUnwrap(transport.momentIds.first)
        XCTAssertEqual(moments().count, 1)
        clock.now += 1000  // before its mumble has played, when the next could replace its face
        transport.onLine?(#"{"t":"ended","id":\#(first + 99),"how":"done"}"#)
        runtime.home.sync {}
        XCTAssertEqual(moments().count, 1, "not the moment holding the turn")
        transport.onLine?(#"{"t":"ended","id":\#(first),"how":"done"}"#)
        runtime.home.sync {}
        XCTAssertEqual(moments().count, 2, "its turn came when the device said the first was over")
        XCTAssertTrue(moments().last?.contains(#""mood":"happy""#) == true)
    }

    /// ARCHITECTURE.md §3.2: a link that drops for a moment (the USB
    /// bridge reconnecting, or a Bluetooth blip) doesn't stop what the
    /// device plays, so the reaction on it keeps the line after the link is
    /// back, until the device's `ended` for it, though HISTORY already says
    /// it didn't happen (§8). Before, the drop freed the line, and the next
    /// reaction cut the one still playing.
    func testALinkBlipKeepsTheLineForTheReactionPlaying() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        func connection(_ up: Bool) {
            transport.onConnection?(up)
            runtime.home.sync {}
        }
        func react(_ mood: String) {
            runtime.home.sync { _ = runtime.harness.force(["react.mood": mood, "react.loops": "twice"]) }
        }
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) }.count }
        func ends() -> [Pending.End] {
            runtime.home.sync {
                runtime.pipeline.transcript.events.filter { $0.phase == .end && $0.specificType == "react" }.map(Self.end)
            }
        }
        connection(true)
        react("proud")
        XCTAssertEqual(moments(), 1)
        let first = try XCTUnwrap(transport.momentIds.first)
        clock.now += 600
        connection(false)
        XCTAssertEqual(ends(), [.failed("the device disconnected")])
        clock.now += 1000
        connection(true)
        clock.now += 50
        react("happy")
        XCTAssertEqual(moments(), 1, "the first still plays on the device")
        transport.onLine?(#"{"t":"ended","id":\#(first),"how":"done"}"#)
        runtime.home.sync {}
        XCTAssertEqual(moments(), 2, "its turn came when the device said the first was over")
    }

    /// ARCHITECTURE.md §3.2: the Mac hears a tap after sending what it
    /// thought was playing then, so a reaction it sent just before may
    /// have reached the device after the tap, and plays on there. A tap
    /// leaves a reaction sent with an id holding the line: the device's
    /// `ended` for it frees the line, sent at once when its tap cut it, or
    /// when it ends. Before, the tap freed the line, and the next reaction
    /// cut the one the device had only just started.
    func testATapLeavesTheLineToTheDevicesEnded() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) }.count }
        runtime.home.sync {
            for mood in ["excited", "proud", "grumpy"] { _ = runtime.harness.force(["react.mood": mood]) }
        }
        XCTAssertEqual(moments(), 1)
        clock.now += 2000
        device(#"{"t":"ended","id":\#(transport.momentIds[0]),"how":"done"}"#)
        XCTAssertEqual(moments(), 2, "the second goes")
        clock.now += 20
        device(#"{"t":"input","k":"tap"}"#)  // on the device before the second arrived
        XCTAssertEqual(moments(), 2, "the second may be playing: the third waits for its ended")
        XCTAssertGreaterThan(runtime.home.sync { runtime.moments.schedule.lineFree }, clock.now)
        clock.now += 1500
        device(#"{"t":"ended","id":\#(transport.momentIds[1]),"how":"done"}"#)
        XCTAssertEqual(moments(), 3)
    }

    /// How an action's `end` event says it went.
    static func end(_ e: Event) -> Pending.End {
        e["outcome"] == "done" ? .done : .failed(e["why"]?.string ?? "")
    }

    /// harness/EVENTS.md §5: a turn's length is the time between its
    /// prompt and its end as the transcript has them, the time the Mac
    /// slept included.
    func testATurnsLengthCountsTheTimeTheMacSlept() throws {
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.advance = { clock.now += $0 }
        let runtime = try Runtime(options)
        func hook(_ name: String) {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: name, session: "s1", cwd: "/tmp/jetpack", ts: clock.now),
                             received: clock.now)
            }
        }
        func lastLine() -> String? { runtime.home.sync { runtime.view.events.last?.line } }
        hook("UserPromptSubmit")
        clock.now += 60_000
        clock.now += 8 * 3_600_000  // the lid closed overnight
        hook("Stop")
        XCTAssertEqual(lastLine(), #"claude finished turn 1 on "jetpack": done, a very long turn, no tool calls."#)
        hook("UserPromptSubmit")
        clock.now += 30_000
        runtime.home.sync { runtime.dev(Data(#"{"dev":"advance","ms":10800000}"#.utf8)) }
        clock.now += 10_000
        hook("Stop")
        XCTAssertEqual(lastLine(), #"claude finished turn 2 on "jetpack": done, a very long turn, no tool calls."#)
    }

    /// harness/EVENTS.md §6: a failing test wakes the brain while the
    /// prompt's pass runs, and waits; a permission request comes before
    /// that pass ends. The waiting pass doesn't start under the amber.
    func testNoWaitingPassStartsWhileSomethingNeedsYou() throws {
        let gate = DispatchSemaphore(value: 0)
        let asked = Lines()
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let brain = ScriptedBrain { state, _ in
            asked.add(String(state.split(separator: "\n").reversed()[1]))
            gate.wait()
            return [:]
        }
        options.brain = { _ in brain }
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        func hook(_ name: String, tool: String? = nil, topic: String? = nil, failed: Bool = false) {
            var line = HookLine(agent: "claude", hook: name, session: "s1", cwd: "/tmp/jetpack", tool: tool, ts: clock.now)
            line.topic = topic
            line.toolError = failed ? "exit_code" : nil
            runtime.home.sync { runtime.hook(line, received: clock.now) }
        }
        hook("UserPromptSubmit")
        hook("PreToolUse", tool: "Bash", topic: "tests")
        hook("PostToolUseFailure", tool: "Bash", topic: "tests", failed: true)
        hook("PreToolUse", tool: "Edit")
        hook("PermissionRequest", tool: "Edit")
        gate.signal()
        eventually("the waiting pass is dropped") {
            runtime.home.sync { runtime.harness.idle }
        }
        XCTAssertEqual(asked.all.count, 1, "\(asked.all)")
        let logged = try String(contentsOf: runtime.debugLogURL, encoding: .utf8)
        let dropped = logged.split(separator: "\n").compactMap { line -> String? in
            let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return (o?["pass"] as? [String: Any])?["dropped"] as? String
        }
        XCTAssertEqual(dropped, ["something needs you"])
        XCTAssertTrue(logged.contains(#""brain":"scripted","dropped":"something needs you""#),
                      "counted with the brain's dropped passes, not the dashboard's")
    }

    /// ARCHITECTURE.md §3.2: the pump's timer counts the Mac's uptime,
    /// which stops while the Mac sleeps, and the moments' clock doesn't. A
    /// timer set for a time the clock has already passed is late, so the
    /// next moment to wait sets a timer of its own rather than wait for it.
    func testATimerTheClockHasPassedIsReplaced() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        func react(_ mood: String) {
            runtime.home.sync { _ = runtime.harness.force(["react.mood": mood, "react.loops": "twice"]) }
        }
        let pumpAt = { runtime.home.sync { runtime.moments.pumpAt } }

        react("proud")
        clock.now += 1000
        react("happy")
        let free = { runtime.home.sync { runtime.moments.schedule.brainFree } }
        XCTAssertEqual(pumpAt(), free(), "the second waits for the first's mumble")
        XCTAssertGreaterThan(free(), clock.now)
        clock.now += 60_000  // the Mac slept, and the timer with it
        react("grumpy")  // the second is dropped, and this one plays
        XCTAssertEqual(runtime.home.sync { runtime.moments.schedule.waiting.count }, 0)
        clock.now += 1000
        react("excited")
        XCTAssertEqual(pumpAt(), free(), "a timer of its own, not the late one")
        XCTAssertGreaterThan(free(), clock.now)
    }

    /// PROTOCOL.md §3: moment ids start somewhere random at every launch
    /// and count up, so an earlier launch's moment still on the device
    /// can't share one; they stay within 1...Int32.max for the device.
    func testMomentIdsDifferEachLaunch() {
        let firsts = Set((0..<8).map { _ in Runtime.Moments.firstId() })
        XCTAssertGreaterThan(firsts.count, 1, "random")
        XCTAssertTrue(firsts.allSatisfy { (0..<Int(Int32.max)).contains($0) })
        XCTAssertEqual(Runtime.Moments.nextId(after: 41), 42)
        XCTAssertEqual(Runtime.Moments.nextId(after: Int(Int32.max)), 1, "back to 1, never 0")
    }

    /// PROTOCOL.md §3: a launch numbers its requests from somewhere random,
    /// as it does its moments, so a relaunched app's first request can't
    /// share `attn.id` with the one the device still shows from the last
    /// launch: with the same agent and project, a new request would carry
    /// on the amber with no chirp (BEHAVIORS.md §3.2). The numbers wrap to
    /// 1, never 0, within the device's 32 bits.
    func testRequestNumbersDifferEachLaunch() throws {
        var firsts: Set<Int> = []
        for _ in 0..<4 {
            dir = URL(fileURLWithPath: "/tmp/boop-rt-\(UUID().uuidString.prefix(8))")
            defer { try? FileManager.default.removeItem(at: dir) }
            let runtime = try makeRuntime(FakeTransport())
            firsts.insert(runtime.core.lastAsk)
        }
        XCTAssertGreaterThan(firsts.count, 1, "random")
        XCTAssertTrue(firsts.allSatisfy { (0..<Int(Int32.max)).contains($0) })
        var config = Core.Config()
        config.firstAsk = Int(Int32.max)
        let core = Core(config: config)
        core.handle(Event(ts: 1000, source: .claude, type: .tool, phase: .wait, specificType: "PermissionRequest",
                          session: "s", cwd: "/w/landing", data: ["tool": "Bash", "for": "permission"]))
        XCTAssertEqual(core.snapshot(at: 1000).attn?.id, 1, "back to 1, never 0")
    }

    /// harness/HARNESS.md §5.3: HISTORY closes with `mood`'s time in a mood
    /// other than happy (DECISIONS.md §4), and nothing else; the harness
    /// only places it.
    func testHistoryClosesWithTheMoodsTime() throws {
        var now: Int64 = 1_790_000_000_000
        let core = Core(config: .init())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-since-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let moodAction = MoodAction(store: MoodStore(stateDir: dir), clock: { now })
        func closing() -> String? {
            Runtime.stateParts(steering: Self.steering, personality: .boop, mood: "happy", view: TranscriptView(),
                               moodAction: moodAction, time: LocalTime(timeZone: TimeZone(identifier: "UTC")!), now: now, wall: now).closing
        }
        XCTAssertNil(closing(), "happy says nothing")
        _ = moodAction.change(to: "grumpy")
        now += 30_000
        XCTAssertEqual(closing(), "Boop has been grumpy for under a minute.")
        now += 2 * 60_000
        XCTAssertEqual(moodAction.sinceLine(at: now), "Boop has been grumpy for 2 min.", "whole minutes, as HISTORY's")
        XCTAssertNil(MoodAction(store: MoodStore(stateDir: dir)).sinceLine(at: now),
                     "grumpy on disk, but nothing before a change since launch")
        _ = moodAction.change(to: "happy")
        XCTAssertNil(moodAction.sinceLine(at: now), "back to happy")
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
