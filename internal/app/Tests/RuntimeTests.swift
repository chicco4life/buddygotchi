import AgentHooks
import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The runtime end to end in-process: real hook socket, real core, the
/// harness with a scripted brain, and memory in a temporary state
/// directory; a fake device. Jev's key is never read from the Keychain, and
/// nothing reaches Jev.
final class RuntimeTests: XCTestCase {
    var dir: URL!
    /// What the runtime opened on the Mac, as `open`'s arguments: never for
    /// real in a test.
    let opened = Lines()

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
                 readJevKey: @escaping @Sendable (() -> String?) -> String? = { _ in "k" }) throws -> Runtime.Options {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet)
        var options = Runtime.Options(stateDir: dir, socketPath: socketPath, link: transport, steering: Self.steering)
        options.devLines = true
        options.readJevKey = readJevKey
        options.brain = { key in key.map { _ in brain } }
        let opened = self.opened
        options.open = { opened.add($0.arguments.joined(separator: " ")); return true }
        return options
    }

    func makeRuntime(_ transport: FakeTransport, brain: ScriptedBrain = .pipelineCheck,
                     readJevKey: @escaping @Sendable (() -> String?) -> String? = { _ in "k" }) throws -> Runtime {
        try Runtime(options(transport, brain: brain, readJevKey: readJevKey))
    }

    /// harness/HARNESS.md §7: Jev's key is read off `home`, since a Keychain
    /// prompt would stall every event, and no event wakes the brain until it
    /// arrives; a key Settings saves or clears takes over at once. The read
    /// starts with `start`, once the callbacks are set, so it never races
    /// the app setting them. The status says whether it's been read, so the
    /// popover never asks for a key that's still being read
    /// (ARCHITECTURE.md §8).
    func testJevsKeyIsReadOffHome() throws {
        let prompt = DispatchSemaphore(value: 0)
        let reads = Lines()
        // The first read is the start's, whose `saved` is the Keychain's;
        // Settings' come after, with the key it saved.
        let runtime = try makeRuntime(FakeTransport(), brain: ScriptedBrain(id: "jev-test", always: [:])) { saved in
            reads.add("read")
            guard reads.all.count == 1 else { return saved() }
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
        XCTAssertTrue(runtime.home.sync { statuses.allSatisfy { !$0.keyRead } }, "not read yet, so not missing")
        prompt.signal()
        eventually("the brain once it's read") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
        XCTAssertTrue(runtime.home.sync { statuses.last?.keyRead == true })
        XCTAssertTrue(runtime.home.sync { runtime.pipeline.brain })
        runtime.reloadBrain(jevKey: nil)
        eventually("none when Settings clears it") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertTrue(runtime.home.sync { statuses.last?.keyRead == true }, "read, and there's none")
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

        // A finished turn clears "needs you", and the brain plays its
        // finish (no rule does, BEHAVIORS.md §3.1).
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's finish") {
            transport.sent.contains {
                $0.hasPrefix(#"{"t":"moment","anim":"task_complete","say":"#) && $0.contains(#""mood":"excited""#)
                    && $0.contains(#""outcome":"success""#)
            }
        }
        XCTAssertEqual(AppSettings.load(from: dir).personality, .boop)
    }

    /// ARCHITECTURE.md §8: why the link can't look for the device
    /// (Bluetooth off) reaches the popover's status by the next tick, and
    /// leaves it the same way.
    func testTheLinksTroubleReachesTheStatus() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        transport.lock.withLock { transport.why = "Bluetooth is off." }
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(runtime.home.sync { statuses.last?.linkTrouble }, "Bluetooth is off.")
        transport.lock.withLock { transport.why = nil }
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(runtime.home.sync { statuses.last?.linkTrouble })
    }

    /// harness/HARNESS.md §3–5: an event that wakes the brain gets a pass;
    /// the answers become a reaction on the device, and the mood action's
    /// change reaches the mood file, the status, and the next pass's MOOD.
    func testAPassMumblesAndChangesTheMood() throws {
        let transport = FakeTransport()
        let lines = DebugLines()
        var options = try options(transport, brain: ScriptedBrain(id: "scripted", always: [
            "mood": Answer(choice: "annoyed", probabilities: ["annoyed": 0.7]),
            "react.mood": Answer(choice: "grumpy", probabilities: ["grumpy": 0.6]),
            "say.about": Answer(choice: "work", probabilities: ["work": 0.5]),
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
        eventually("annoyed") { runtime.home.sync { runtime.mood.current == "annoyed" } }
        eventually("the device hears it") { transport.sent.contains { $0.hasPrefix(#"{"t":"state""#) && $0.contains(#""mood":"annoyed""#) } }
        try XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(MoodStore.fileName), encoding: .utf8), "annoyed\n")
        eventually("the log line") { lines.lock.withLock { lines.log.contains { $0.hasPrefix("brain turn start ") && $0.hasSuffix("→ mood, react") } } }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        func logged(_ kind: String) -> [Substring] {
            ((try? String(contentsOf: debugLog, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.hasPrefix("{\"\(kind)\":") }
        }
        func passes() -> [Substring] { logged("pass") }
        eventually("the second pass") { passes().count == 2 }
        // The state's head is logged again only when it changes (§9).
        let heads = logged("head")
        XCTAssertEqual(heads.count, 2)
        XCTAssertTrue(heads[0].contains("Calm. Boop is settled"), "the first pass read calm")
        XCTAssertTrue(heads[1].contains("Annoyed. Boop is mildly put out"), "the next reads the new mood's file")
        XCTAssertTrue(Take.all.contains { $0.meaning == "work" && $0.mood == "grumpy"
                          && passes()[1].contains(#"Boop made a grumpy face, held once, and said \"\#($0.text)\"."#) },
                      "HISTORY shows what the actions did")
        XCTAssertFalse(lines.lock.withLock { lines.log.contains { $0.contains("PERSONALITY") } }, "the state stays out of boop.log")
    }

    /// harness/HARNESS.md §9: a bug report, debug mode or not, holds this
    /// launch's debug lines (the passes' states included), the log's end,
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
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"head":"#) && $0.contains("PERSONALITY") }, "the state's head")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"pass":"#) && $0.contains("HISTORY (") }, "a pass with the rest of its state")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"sent":"#) }, "the lines sent to the device")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"status":"#) }, "the status")
        try XCTAssertEqual(String(contentsOf: report.appendingPathComponent("boop.log"), encoding: .utf8), "an old line\n")
        let about = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: report.appendingPathComponent("about.json"))) as? [String: Any])
        XCTAssertEqual(about["brain"] as? String, "scripted")
        XCTAssertEqual(about["connected"] as? Bool, true)
    }

    /// harness/HARNESS.md §9: the report's lines are capped at
    /// `DebugLog.Recent.maxBytes`, the oldest let go first, and kept as
    /// their bytes alone, with at most an eighth more let go but not yet
    /// dropped. The launch's `questions` line and the latest `head` line
    /// let go still start the report.
    func testRecentLinesAreCapped() throws {
        let recent = DebugLog.Recent()
        XCTAssertEqual(DebugLog.Recent.maxBytes, 8 << 20)
        recent.add(#"{"questions":[],"received_at_ms":1}"#)
        recent.add(DebugLog.head("old", at: 2))
        recent.add(DebugLog.head("new", at: 3))
        for n in 0..<(DebugLog.Recent.maxBytes / 1024 + 5000) { recent.add(String(format: "%07d", n) + String(repeating: "x", count: 1016)) }
        recent.add("last")
        let lines = recent.bytes.split(separator: 0x0A)
        XCTAssertEqual(lines.last.map { String(decoding: $0, as: UTF8.self) }, "last")
        XCTAssertLessThanOrEqual(recent.bytes.count, DebugLog.Recent.maxBytes)
        XCTAssertGreaterThan(lines.count, DebugLog.Recent.maxBytes / 1024 - 2)
        XCTAssertEqual(String(decoding: lines[1].prefix(7), as: UTF8.self), String(format: "%07d", Int(String(decoding: lines[0].prefix(7), as: UTF8.self))! + 1),
                       "whole lines, in order")
        XCTAssertLessThanOrEqual(recent.text.count, DebugLog.Recent.maxBytes / 8 * 9 + 1024)
        XCTAssertLessThanOrEqual(recent.text.capacity, DebugLog.Recent.maxBytes / 8 * 9 + (32 << 10), "its room was never grown")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("recent.jsonl")
        try Runtime.write(recent.pieces, to: url)
        let written = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(Array(written.prefix(2)), [#"{"questions":[],"received_at_ms":1}"#, #"{"head":"new","received_at_ms":3}"#])
        XCTAssertEqual(written.count, lines.count + 2)
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
        let started = try XCTUnwrap(printed.first { $0.hasPrefix("  … react: Boop made an excited face, held once, and said \"") }, "\(printed)")
        let word = String(started.dropFirst("  … react: Boop made an excited face, held once, and said \"".count).dropLast(2))
        XCTAssertTrue(Take.all.contains { $0.text == word && $0.meaning == "start" && $0.mood == "excited" }, "a start take: \(word)")
        XCTAssertTrue(printed.contains { $0.hasPrefix("  ✗ react (") && $0.hasSuffix(") didn't happen: no device connected") },
                      "the fake device never connected: \(printed)")
        let p = try XCTUnwrap(debugLines().compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue((p["state"] as? String)?.hasPrefix("HISTORY (") == true)
        XCTAssertTrue((debugLines().first { $0["head"] != nil }?["head"] as? String)?.hasPrefix("You are the mind of Boop") == true)
        XCTAssertEqual(p["questions"] as? [String], ["mood", "react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])

        // A bug report in debug mode copies the file's lines: none are kept
        // in memory beside it.
        XCTAssertTrue(runtime.home.sync { runtime.recent.bytes.isEmpty })
        let saved = Lines()
        runtime.saveReport { saved.add($0?.path ?? "none") }
        eventually("the report") { !saved.all.isEmpty }
        let copied = try String(contentsOf: URL(fileURLWithPath: saved.all[0]).appendingPathComponent(DebugLog.fileName), encoding: .utf8)
        XCTAssertTrue(copied.hasPrefix(#"{"questions":"#) && copied.contains(#""pass":"#), copied)
        let whole = try String(contentsOf: debugLog, encoding: .utf8)
        XCTAssertTrue(whole.hasPrefix(copied))
        let short = dir.appendingPathComponent("lines.jsonl")
        try Data("one\ntwo\nthree\n".utf8).write(to: short)
        XCTAssertEqual(Runtime.end(of: short, bytes: 8), Data("three\n".utf8), "the end of a longer file starts at a line")
        XCTAssertEqual(Runtime.end(of: short, bytes: 14), Data("one\ntwo\nthree\n".utf8))
        XCTAssertNil(Runtime.end(of: dir.appendingPathComponent("none"), bytes: 8))
        // A longer launch's report starts with its questions line and the
        // head in force where its lines start, as `recent`'s does.
        let big = dir.appendingPathComponent("big.jsonl")
        let questions = #"{"questions":[],"received_at_ms":1}"# + "\n", head = DebugLog.head("new", at: 3) + "\n"
        try Data((questions + DebugLog.head("old", at: 2) + "\n" + head
                  + String(repeating: String(repeating: "x", count: 1023) + "\n", count: DebugLog.Recent.maxBytes / 1024 + 10)).utf8).write(to: big)
        let pieces = Runtime.debugLines(big)
        XCTAssertEqual(pieces.map { String(decoding: $0.prefix(40), as: UTF8.self) }, [questions, head, String(repeating: "x", count: 40)])
        XCTAssertEqual(pieces[2].count, DebugLog.Recent.maxBytes / 1024 * 1024)
        XCTAssertEqual(Runtime.debugLines(short).count, 1, "all of a short file, as it is")
    }

    /// harness/HARNESS.md §9: the questions line is debug.jsonl's first
    /// even when the launch ends a reaction the last one left in progress,
    /// so `boopctl day` doesn't count those ends as a launch of their own.
    func testTheQuestionsComeFirstWhenALaunchEndsWhatTheLastLeftOpen() throws {
        var options = try options(FakeTransport())
        options.debug = true
        let now = options.clock()
        let last = Pipeline(core: Core(config: .init()), transcript: Transcript(folder: dir.appendingPathComponent(Transcript.folderName)),
                            view: TranscriptView())
        let line = HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack", ts: now - 1000)
        let prompt = try XCTUnwrap(last.agent(XCTUnwrap(Adapter.event(from: line, receivedAt: now - 1000))).recorded.first)
        last.record(Event(ts: now - 900, source: .boop, type: .action, phase: .start, specificType: "react",
                          data: ["for": .int(Int64(prompt.seq)), "by": "brain", "ok": true, "message": "Boop smiled."]))
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        let lines = debugLines()
        XCTAssertNotNil(lines.first?["questions"], "\(lines.first ?? [:])")
        let end = try XCTUnwrap(lines.compactMap { ($0["event"] as? [String: Any]).flatMap(Event.init(json:)) }.first)
        XCTAssertEqual(end.data["why"], "Boop restarted")
    }

    /// harness/HARNESS.md §5.1: transcript files older than 14 days go at
    /// each new day, not only at launch, for an app left running for weeks.
    /// The day the app opened isn't a new day: its launch pruned already.
    func testANewDayDeletesTranscriptFilesPastFourteenDays() throws {
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        let runtime = try Runtime(options)
        let folder = dir.appendingPathComponent(Transcript.folderName)
        let time = LocalTime()
        func file(_ daysAgo: Int64) -> URL { folder.appendingPathComponent(time.day(clock.now - daysAgo * 86_400_000) + ".jsonl") }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func hook() {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack", ts: clock.now),
                             received: clock.now)
            }
        }
        let old = file(14), kept = file(12)
        try Data("{}\n".utf8).write(to: old)
        try Data("{}\n".utf8).write(to: kept)
        XCTAssertEqual(Transcript.keptDays, 14)
        hook()
        XCTAssertTrue(exists(old), "the day the app opened isn't a new day")
        clock.now += 86_400_000
        hook()
        XCTAssertFalse(exists(old), "past 14 days, today included")
        XCTAssertTrue(exists(kept))
    }

    /// harness/HARNESS.md §9: the 10 s keepalive's `state`, the same as the
    /// last one sent, is in debug.jsonl (the dashboard's sign that the app
    /// is running) but not in boop.log, which names each change once.
    func testTheKeepaliveStaysOutOfBoopLog() throws {
        let lines = DebugLines()
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        func states() -> (sent: Int, logged: Int) {
            (debugLines().filter { ($0["sent"] as? [String: Any])?["t"] as? String == "state" }.count,
             lines.lock.withLock { lines.log.filter { $0.hasPrefix(#"link rules → {"t":"state""#) }.count })
        }
        eventually("the first state") { runtime.home.sync { states().sent == 1 } }
        for _ in 0..<2 {
            clock.now += DeviceLink.keepaliveMs
            runtime.home.sync { runtime.tick() }
        }
        XCTAssertEqual(runtime.home.sync { states().sent }, 3)
        XCTAssertEqual(runtime.home.sync { states().logged }, 1)
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

    /// Every line `runtime`'s link sends from now on, with no transport
    /// too, beside the runtime's own `onSend`.
    func collectSent(_ runtime: Runtime) -> Lines {
        let lines = Lines()
        let emit = runtime.link.onSend
        runtime.link.onSend = { lines.add($0); emit?($0, $1) }
        return lines
    }

    /// Every event this runtime's transcript recorded, from its files: it
    /// keeps none in memory.
    func recorded() -> [Event] {
        let folder = dir.appendingPathComponent(Transcript.folderName)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().flatMap { name in
            ((try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "")
                .split(separator: "\n").compactMap { Event(jsonLine: $0) }
        }
    }

    /// The actions this runtime's debug.jsonl recorded, as events.
    func debugActions() -> [Event] {
        debugLines().compactMap { ($0["event"] as? [String: Any]).flatMap(Event.init(json:)) }.filter { $0.type == .action }
    }

    var socketPath: String { dir.appendingPathComponent("boop.sock").path }

    func dev(_ json: String) {
        XCTAssertTrue(HookSocket.send(Data((json + "\n").utf8), to: socketPath))
    }

    /// BEHAVIORS.md §3.2: a tap on the board while something needs you
    /// opens the waiting thread on the Mac, in its app; a click on a
    /// session in the popover opens that one. `{"dev":"tap"}` stands in for
    /// the board.
    func testATapOrAClickOpensTheThread() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        var ask = HookLine(agent: "claude", hook: "PermissionRequest", session: "s1", cwd: "/tmp/jetpack", tool: "Bash",
                           app: HostApp.claude, appSession: "local_7db5", ts: 1)
        XCTAssertTrue(HookSocket.send(ask.encoded(), to: socketPath))
        ask.agent = "codex"
        ask.session = "01a0e6fd-587d"
        ask.app = nil
        ask.appSession = nil
        XCTAssertTrue(HookSocket.send(ask.encoded(), to: socketPath))
        eventually("needs you") { runtime.home.sync { runtime.core.needsYouShowing } }
        transport.onLine?(#"{"t":"input","k":"tap"}"#)
        eventually("the oldest opened") { opened.all == ["claude://code/continue?session=local_7db5"] }
        dev(#"{"dev":"tap"}"#)
        eventually("the dev line taps too") { opened.all.count == 2 }
        let codex = try XCTUnwrap(runtime.home.sync { runtime.core.sessionList(at: runtime.options.clock()) }
            .first { $0.agent == "codex" }?.thread)
        runtime.openThread(codex)
        eventually("a click opens its own") { opened.all.last == "codex://threads/01a0e6fd-587d" }
    }

    /// harness/HARNESS.md §9: debug mode also writes the
    /// dashboard's lines, with no `seq`: every action's questions first at
    /// launch, and again only when they change (not here: the scripted
    /// brain keeps the mood, whose options would change with it), every
    /// line sent to the device verbatim (with no transport too) with who
    /// sent it (`brain` for the brain's moments, `rule` for the rest), and a
    /// status line whenever the mood, personality, brain, sessions or
    /// connection change.
    func testDebugModeWritesTheDashboardsLines() throws {
        var options = try options(nil)
        options.debug = true
        let runtime = try Runtime(options)
        let sentLines = collectSent(runtime)
        try runtime.start()
        defer { runtime.stop() }
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { runtime.home.sync { sentLines.all.contains { $0.contains(#""say":"#) } } }
        runtime.home.sync {}

        let text = try String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)
        let raw = text.split(separator: "\n").map(String.init)
        let lines = debugLines()
        let questions = try XCTUnwrap(lines.first?["questions"] as? [[String: Any]], "the questions come first")
        XCTAssertEqual(lines.filter { $0["questions"] != nil }.count, 1, "once: nothing changed them")
        XCTAssertEqual((questions[0]["options"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["calm"] + MoodGraph.neighbours(of: "calm"), "staying calm, then calm's moves")
        XCTAssertEqual(questions.map { $0["key"] as? String }, ["mood", "react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])
        XCTAssertEqual(questions.map { $0["action"] as? String }, ["mood", "react", "react", "react", "react", "react", "react"])
        XCTAssertEqual(questions[1]["text"] as? String, "How should Boop react to NOW, if at all? It makes this mood's face for a moment, and may say something.")
        let none = try XCTUnwrap((questions[1]["options"] as? [[String: Any]])?.first)
        XCTAssertEqual(none["name"] as? String, "none")
        XCTAssertEqual(none["what"] as? String, "Stay quiet: nothing in NOW is worth a face, "
                       + "or HISTORY shows Boop still making the one it calls for (in progress).")
        XCTAssertEqual(none["not_for"] as? String, "Anything PERSONALITY's Examples react to that Boop isn't already doing.")
        XCTAssertTrue((questions[0]["options"] as? [[String: Any]])?.first?["not_for"] is NSNull)

        // Sent: every line the link sent, verbatim and in order, and by whom.
        let sentBy = raw.filter { $0.hasPrefix(#"{"sent":"#) }.map { line in
            let by = line.range(of: #",\"by\":\"(brain|rule)\",\"received_at_ms\":\d+\}$"#, options: .regularExpression)
            return (line: String(line[line.index(line.startIndex, offsetBy: #"{"sent":"#.count)..<(by?.lowerBound ?? line.endIndex)]),
                    by: by.map { String(line[$0]).contains(#""brain""#) ? "brain" : "rule" })
        }
        let sent = sentBy.map(\.line)
        XCTAssertEqual(sent, runtime.home.sync { sentLines.all })
        XCTAssertTrue(sent.contains { $0.hasPrefix(#"{"t":"state""#) } && sent.contains { $0.hasPrefix(#"{"t":"moment""#) })
        // The scripted brain's reactions carry a mood; the rules' lines don't.
        for (line, by) in sentBy {
            XCTAssertEqual(by, line.hasPrefix(#"{"t":"moment""#) && line.contains(#""mood":"#) ? "brain" : "rule", line)
        }
        XCTAssertTrue(sentBy.contains { $0.by == "brain" }, "the brain's reaction")

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
            let extra: Set<String> = line["sent"] != nil ? ["received_at_ms", "by"] : ["received_at_ms"]
            XCTAssertEqual(Set(line.keys).subtracting(extra).count, 1, "one kind, and no seq: \(line)")
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
        let sentLines = collectSent(runtime)
        try runtime.start()
        defer { runtime.stop() }
        func sessions() -> [[String: String]] {
            debugLines().compactMap { $0["status"] as? [String: Any] }.last?["sessions"] as? [[String: String]] ?? []
        }
        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        eventually("the first session") { sessions().count == 1 }
        func states(_ lines: [String]) -> [String] { lines.filter { $0.hasPrefix(#"{"t":"state""#) } }
        let sent = runtime.home.sync { sentLines.all }
        XCTAssertTrue(states(sent).last?.contains(#""base":"idle""#) == true, "\(sent)")
        let second = HookLine(agent: "claude", hook: "SessionStart", session: "s2", cwd: "/tmp/notes",
                              ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded()
        XCTAssertTrue(HookSocket.send(second, to: socketPath))
        eventually("the second session") { sessions().count == 2 }
        XCTAssertEqual(sessions().map { $0["status"] }, ["idle", "idle"])
        XCTAssertEqual(states(runtime.home.sync { sentLines.all }), states(sent), "no new state")
    }

    /// The dashboard's dev lines. A forced pass needs no
    /// brain and reacts as Jev's would; a forced mood changes as Jev's
    /// does, device included; each is recorded for no event, by the
    /// dashboard.
    func testTheDashboardsDevLines() throws {
        let transport = FakeTransport()
        var options = try options(transport, readJevKey: { _ in nil })
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        eventually("no brain") { runtime.home.sync { runtime.jevKey != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))

        dev(#"{"dev":"answer","answers":{"react.mood":"grumpy","say.about":"work"}}"#)
        eventually("a take with no brain") { transport.sent.contains { $0.hasPrefix(#"{"t":"moment","say":{"take":"#) && $0.contains(#""mood":"grumpy""#) } }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        eventually("grumpy") { runtime.home.sync { runtime.mood.current == "grumpy" } }
        dev(#"{"dev":"mood","mood":"happy"}"#)
        eventually("happy, off the graph") { runtime.home.sync { runtime.mood.current == "happy" } }
        dev(#"{"dev":"answer","answers":{"mood":"excited"}}"#)
        eventually("excited, a move from happy") { runtime.home.sync { runtime.mood.current == "excited" } }

        let lines = debugLines()
        let pass = try XCTUnwrap(lines.compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue(pass["for"] is NSNull)
        XCTAssertEqual(pass["by"] as? String, "dashboard")
        XCTAssertEqual(pass["questions"] as? [String], ["react.mood", "say.about"])
        XCTAssertEqual((pass["answers"] as? [String: [String: Any]])?["react.mood"]?["p"] as? [String: Double], ["grumpy": 1])
        let actions = debugActions().filter { $0.phase != .end && $0["by"] == "dashboard" }
        let worked = try XCTUnwrap(actions.first?["message"]?.string)
        XCTAssertTrue(Take.all.contains { worked == "Boop made a grumpy face, held once, and said \"\($0.text)\"." && $0.meaning == "work"
            && $0.mood == "grumpy" }, worked)
        XCTAssertEqual(actions.dropFirst().map { $0["message"]?.string }, ["Boop's mood changed: calm → grumpy.",
                                                              "Boop's mood changed: grumpy → happy.",
                                                              "Boop's mood changed: happy → excited."])
        XCTAssertEqual(actions.map(\.specificType), ["react", "mood", "mood", "mood"])
        for action in actions { XCTAssertEqual(action["for"], .null) }
        let moods = lines.compactMap { ($0["sent"] as? [String: Any])?["mood"] as? String }
        XCTAssertEqual(moods.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, ["calm", "grumpy", "happy", "excited"],
                       "the device hears each change in a state")
        // One `questions` line, the launch's; a pass whose options differ
        // from it names the ones it asked, such as the mood's moves once it
        // has moved (harness/HARNESS.md §9).
        XCTAssertEqual(lines.filter { $0["questions"] is [[String: Any]] }.count, 1, "once a launch")
        let passes = lines.compactMap { $0["pass"] as? [String: Any] }
        XCTAssertNil(passes[0]["options"], "the launch's options, calm's")
        let moved = try XCTUnwrap(passes.last?["options"] as? [String: [String]])
        XCTAssertEqual(moved, ["mood": ["happy"] + MoodGraph.neighbours(of: "happy")])
    }

    /// BEHAVIORS.md §3.3: BOOT held and let go turns the mic on and off; with
    /// no mic (headless) it hears nothing, so `listening` ends at once with
    /// the empty moment. What the mic heard is recorded and wakes the brain:
    /// a reaction is the reply, and a pass that reacts with none ends
    /// `listening` too. The app's button tells the device to show it.
    func testWhatYouSayGetsAReplyOrEndsListening() throws {
        for (brain, replies) in [(ScriptedBrain.pipelineCheck, true), (ScriptedBrain(always: [:]), false)] {
            try? FileManager.default.removeItem(at: dir)
            let transport = FakeTransport()
            var options = try options(transport, brain: brain)
            options.debug = true
            let runtime = try Runtime(options)
            try runtime.start()
            transport.onConnection?(true)
            eventually("the brain") { runtime.home.sync { runtime.pipeline.brain } }
            let empty = #"{"t":"moment"}"#
            transport.onLine?(#"{"t":"input","k":"talk_on"}"#)
            eventually("listening") { runtime.home.sync { runtime.core.listening?.by == .device } }
            transport.onLine?(#"{"t":"input","k":"talk_off"}"#)
            eventually("heard nothing") { transport.sent.contains(empty) }
            XCTAssertEqual(runtime.home.sync { self.recorded().filter { $0.type == .talk }.count }, 0)

            let before = transport.sent.count
            dev(#"{"dev":"said","words":"are the tests passing?","by":"device"}"#)
            eventually("the pass") { self.debugLines().contains { ($0["pass"] as? [String: Any]) != nil } }
            runtime.home.sync {}
            let after = Array(transport.sent.dropFirst(before)).filter { $0.hasPrefix(#"{"t":"moment""#) }
            if replies {
                XCTAssertEqual(after.count, 1, "\(after)")
                XCTAssertTrue(after.first?.contains(#""say":"#) == true, "the reaction is the reply")
            } else {
                XCTAssertEqual(after, [empty], "no reply: listening ends")
            }
            let talk = try XCTUnwrap(runtime.home.sync { self.recorded().last { $0.type == .talk } })
            XCTAssertEqual(talk["words"], "are the tests passing?")

            dev(#"{"dev":"listen","on":true}"#)
            eventually("the app's button") { transport.sent.contains(#"{"t":"moment","anim":"listening"}"#) }
            XCTAssertTrue(runtime.home.sync { runtime.core.listening?.by == .app })
            runtime.stop()
        }
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
        dev(#"{"dev":"answer","answers":{"react.mood":"grumpy","react.animation":"success"}}"#)
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the hook after them") { transport.sent.contains { $0.contains(#""base":"working""#) } }
        runtime.home.sync {}
        XCTAssertEqual(runtime.home.sync { runtime.mood.current }, "calm")
        XCTAssertFalse(transport.sent.contains { $0.contains("task_complete\"") })
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

    /// plan/steering/ has the guide, a file per mood and the two
    /// personalities (harness/DECISIONS.md §2). harness/HARNESS.md §6.2: the
    /// static parts stay within their budgets, and the personalities'
    /// settings are BEHAVIORS.md §6's.
    func testTheSteeringFitsItsBudgetsAndSettings() throws {
        let files = try XCTUnwrap(FileManager.default.subpaths(atPath: Self.steeringDir.path)).filter { $0.hasSuffix(".md") }.sorted()
        XCTAssertEqual(files, ["guide.md"] + MoodGraph.moods.sorted().map { "mood/\($0).md" }
                               + ["personality/boop.md", "personality/chatter.md"])
        XCTAssertEqual(Self.steering.overBudget(), [])
        XCTAssertEqual(Self.steering.personality(.boop).rules, Personality.Rules(workBeatMs: 90_000...180_000, toolUses: .notable))
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
        XCTAssertEqual(runtime.home.sync { runtime.view.rules.toolUses }, .all)
        XCTAssertEqual(AppSettings.load(from: dir).personality, .chatter)
    }

    /// A long turn, finished after moving the clock with `{"dev":"advance"}`:
    /// no rule plays its finish; the brain's reaction does, as one moment
    /// with the finish, its outcome, its face and what it says (BEHAVIORS.md
    /// §3.1, §5). A tap on it opens that thread, and isn't a poke that
    /// wakes the brain (§3.3).
    func testTheBrainJudgesAFinish() throws {
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
        let prompt = HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack",
                              app: HostApp.claude, appSession: "local_7db5", ts: Int64(Date().timeIntervalSince1970 * 1000))
        XCTAssertTrue(HookSocket.send(prompt.encoded(), to: socketPath))
        eventually("working") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        eventually("the start's reaction") { transport.sent.contains { $0.contains("\"say\"") } }
        let moments = { transport.sent.filter { $0.contains("\"t\":\"moment\"") } }
        XCTAssertFalse(moments().contains { $0.contains(#""anim":"task_complete""#) || $0.contains(#""anim":"reply_ready""#) },
                       "a start gets no finish")
        XCTAssertEqual(moments().filter { $0.contains("\"anim\"") }.count, 1, "only the rule's one-shot")
        XCTAssertTrue(moments()[0].hasPrefix(#"{"t":"moment","anim":"starting","variant":"#), moments()[0])
        transport.endMoments()  // the device says it has played
        eventually("the start's reaction has played") {
            runtime.home.sync {
                let schedule = runtime.schedule
                return schedule.holder == nil && schedule.waiting.isEmpty
            }
        }
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":30000}"#.utf8), to: socketPath))
        eventually("clock moved") { skew.now == 30_000 }
        let before = moments().count
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's finish", timeout: 4) { moments().count >= before + 1 }
        let finish = moments()[before]
        XCTAssertTrue(finish.hasPrefix(#"{"t":"moment","anim":"task_complete","say":"#), "one moment: \(finish)")
        XCTAssertTrue(finish.contains(#""mood":"excited","loops":1,"variant":"#) && finish.contains(#""id":"#), "in its face, held once, a variation, waited on: \(finish)")
        XCTAssertTrue(finish.contains(#""who":{"agent":"claude","thread":"jetpack"},"outcome":"success","id":"#),
                      "names whose turn, and its outcome: \(finish)")
        XCTAssertEqual(moments().count, before + 1, "no rule finish besides")

        let id = try XCTUnwrap(finish.range(of: #"(?<="id":)\d+"#, options: .regularExpression).map { finish[$0] })
        transport.onLine?(#"{"t":"input","k":"tap","id":\#(id)}"#)
        eventually("the finished thread opened") { opened.all == ["claude://code/continue?session=local_7db5"] }
        let action = try XCTUnwrap(recorded().last { $0.specificType == Core.openThread })
        XCTAssertEqual(action["message"]?.string, Core.openedFinished)
        let poke = try XCTUnwrap(runtime.home.sync { runtime.view.events.last })
        XCTAssertEqual(poke.type, .poke)
        XCTAssertFalse(poke.wakesBrain, "it doesn't wake the brain")
        transport.onLine?(#"{"t":"input","k":"tap","id":1}"#)  // a moment the app isn't waiting on: a poke
        eventually("a poke") { recorded().contains { $0.specificType == Core.wiggle } }
        XCTAssertEqual(opened.all.count, 1)
    }

    /// ARCHITECTURE.md §3.2: the brain's moments play one at a time, each
    /// after any line playing, so none cuts off a line or another of the
    /// brain's mumbles. One sent to the device holds the line until the
    /// device says it ended, and for the brain's next until its mumble has
    /// played, or its `ended` if sooner.
    func testBrainMomentsTakeTurns() {
        let line = DeviceMoment.Say.test(ms: 720)
        let mumble = DeviceMoment(say: line, mood: "proud")  // its line is 1920 ms
        var schedule = MomentSchedule(lastId: 0)
        schedule.brain(mumble, Pending(), now: 100)
        schedule.brain(mumble, Pending(), now: 200)
        var due = schedule.due(now: 500, connected: true)
        XCTAssertEqual(due.play.queued, mumble)
        XCTAssertEqual(schedule.next, 500 + 1920 + MomentSchedule.linkSlackMs, "the second waits for the first's mumble")
        XCTAssertNil(schedule.due(now: 2000, connected: true).play, "the line is busy")
        schedule.ended(.done(2), now: 2200)
        XCTAssertNil(schedule.due(now: 2200, connected: true).play, "another moment's end")
        schedule.ended(.done(1), now: 2300)
        due = schedule.due(now: 2300, connected: true)
        XCTAssertEqual(due.play.queued, mumble, "then the second, once the device says the first is over")
        XCTAssertNil(schedule.next, "nothing left")
    }

    /// harness/DECISIONS.md §5: a brain moment's handle goes through the
    /// schedule with it. One dropped for waiting over 5 s ends there as
    /// failed, `waited too long`; one whose turn comes is handed on with
    /// its handle, for whoever plays it to end.
    func testADroppedMomentDidntHappen() throws {
        let line = DeviceMoment.Say.test(ms: 720)
        let mumble = DeviceMoment(say: line, mood: "proud")
        let cheer = DeviceMoment(anim: "task_complete", say: line, mood: "proud", outcome: "success")
        var ends: [String: Pending.End] = [:]
        func handle(_ name: String) -> Pending {
            let pending = Pending()
            pending.bind { ends[name] = $0 }
            return pending
        }
        let late = handle("late"), onTime = handle("on time")
        var schedule = MomentSchedule(lastId: 0)
        schedule.brain(cheer, Pending(), now: 0)
        XCTAssertEqual(schedule.due(now: 0, connected: true).play.queued, cheer)
        let cheerEnds = try XCTUnwrap(schedule.holder?.until)  // a cheer holds the line until its end
        schedule.brain(mumble, late, now: 0)
        schedule.brain(mumble, onTime, now: cheerEnds - 4800)
        let due = schedule.due(now: cheerEnds, connected: true)
        XCTAssertEqual(MomentSchedule.maxWaitMs, 5000)
        XCTAssertGreaterThan(cheerEnds, 5000)
        XCTAssertEqual(due.dropped, [mumble], "past 5 s")
        XCTAssertEqual(ends, ["late": .failed("waited too long")])
        XCTAssertEqual(due.play.queued, mumble, "4.8 s isn't")
        XCTAssertTrue(schedule.playing.last?.pending === onTime, "handed on, still open")
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
            clock.now = max(clock.now, runtime.home.sync { runtime.schedule.lineUntil })
            return try runtime.home.sync {
                XCTAssertEqual(runtime.harness.force(["react.mood": "happy"]).map(\.name), ["react"])
                let seq = try XCTUnwrap(self.recorded().last { $0.type == .action && $0.specificType == "react" && $0.phase != .end }?.seq)
                return (seq, try XCTUnwrap(transport.sent.last { $0.hasPrefix(#"{"t":"moment""#) }))
            }
        }
        func end(of seq: Int) -> Pending.End? {
            runtime.home.sync {
                self.recorded().first { $0.phase == .end && $0["for"] == .int(Int64(seq)) }.map(Self.end)
            }
        }

        let alone = try react()
        XCTAssertEqual(end(of: alone.seq), .failed("no device connected"))
        XCTAssertFalse(alone.moment.contains(#""id""#), "sent all the same, and dropped, with nothing to wait on")
        XCTAssertEqual(runtime.home.sync { runtime.schedule.look }, "asleep",
                       "the look of the last state, which times the face: no sessions")

        clock.now += 10_000
        connection(true)
        let id = runtime.home.sync { runtime.schedule.lastId }  // this launch's ids count up from here
        let played = try react()
        XCTAssertTrue(played.moment.hasSuffix(#","mood":"happy","loops":1,"id":\#(id + 1)}"#), played.moment)
        clock.now = runtime.home.sync { runtime.schedule.lineUntil }
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: played.seq), "played by the app's reckoning, but the device hasn't said so")
        device(#"{"t":"ended","id":\#(id + 1),"how":"done"}"#)
        XCTAssertEqual(end(of: played.seq), .done)
        XCTAssertTrue(runtime.home.sync { runtime.schedule.playing.isEmpty })

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
        let deadline = try XCTUnwrap(runtime.home.sync { runtime.schedule.playing.first?.deadline })
        XCTAssertEqual(deadline, runtime.home.sync { runtime.schedule.lineUntil } + MomentSchedule.endGraceMs,
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
        XCTAssertTrue(runtime.home.sync { runtime.schedule.playing.isEmpty })
    }

    /// PROTOCOL.md §4, harness/DECISIONS.md §5: how each `ended` reads in
    /// HISTORY; and PROTOCOL.md §6: the grace the app gives a moment past
    /// its length.
    func testWhatTheDevicesEndedMeans() {
        XCTAssertEqual(MomentSchedule.endGraceMs, 3000)
        let end = { (how: MomentEnded.How, why: String?) in MomentSchedule.end(MomentEnded(id: 1, how: how, why: why)) }
        XCTAssertEqual(end(.done, nil), .done)
        XCTAssertEqual(end(.cut, "tap"), .failed("cut short: you tapped Boop"))
        XCTAssertEqual(end(.cut, "moment"), .failed("cut short: something newer played"))
        XCTAssertEqual(end(.cut, "needs_you"), .failed("cut short: something needed you"))
        XCTAssertEqual(end(.cut, "reset"), .failed("cut short"))
        XCTAssertEqual(end(.cut, nil), .failed("cut short"))
        XCTAssertEqual(end(.skipped, nil), .failed("something needed you"))
    }

    /// harness/DECISIONS.md §5, HARNESS.md §5.1: a reaction held longest,
    /// in the design with the longest loop of any of the 13 moods and any
    /// look, and with the slowest line, ends by the app's own reckoning
    /// (its wait for a turn, a pump running late, its length and the grace
    /// for the device's `ended`) before the harness's ceiling would end
    /// it. The loops are the designs' (`FaceLoops`), so a new design with a
    /// long loop fails here rather than in HISTORY: wounded's 13 s idle,
    /// held four times, is 52 s, past the 60 s ceiling there was once the
    /// wait and grace are added.
    func testAReactionEndsBeforeTheHarnessCeiling() {
        XCTAssertEqual(MoodAction.moods.count, 13)
        let slow = DeviceMoment.Say(takes: [Take.all.max { $0.ms < $1.ms }!])
        let held = ReactAction.holds.count
        let longest = MoodAction.moods.map(\.name).flatMap { mood in
            FaceLoops.states.map { look in
                DeviceMoment(say: slow, mood: mood, loops: held).playMs(look: look, mood: mood)
            }
        }.max() ?? 0
        let longestLoop = MoodAction.moods.map(\.name).flatMap { mood in
            FaceLoops.states.flatMap { state in (1...FaceLoops.count(mood: mood, state: state)).map { FaceLoops.ms(mood: mood, state: state, variant: $0) } }
        }.max() ?? 0
        XCTAssertGreaterThanOrEqual(longest, Int64(held) * longestLoop)
        XCTAssertLessThan(MomentSchedule.maxWaitMs + MomentSchedule.lateMs + longest + MomentSchedule.endGraceMs,
                          Harness.pendingMaxMs)
    }

    /// PROTOCOL.md §3, VOICE.md §10: the Mac and the device time the
    /// designs alike. Every design's loop and voice window in `FaceLoops`
    /// is the one firmware/assets/faces.h (`kScenes`' `loopMs`, through
    /// `kDesigns`) and sfx.h (`kScore`'s `voiceMs`) give the device, in the
    /// same order: facegen and sfxgen write them from one manifest.
    func testTheMacTimesTheDesignsAsTheDeviceDoes() throws {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../firmware/assets").standardizedFileURL
        func block(_ text: String, _ start: String) -> String {
            let from = text.range(of: start)!.upperBound
            return String(text[from..<text.range(of: "};", range: from..<text.endIndex)!.lowerBound])
        }
        func rows(_ text: String, _ pattern: String) -> [[String]] {
            let re = try! NSRegularExpression(pattern: pattern)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                (1..<m.numberOfRanges).map { String(text[Range(m.range(at: $0), in: text)!]) }
            }
        }
        let faces = try String(contentsOf: assets.appendingPathComponent("faces.h"), encoding: .utf8)
        let loops = rows(block(faces, "static const Scene kScenes["), #"\{\d+, \d+, (\d+), -?\d+, -?\d+, \d+, \d+\}"#)
            .map { Int64($0[0])! }
        let scenes = rows(block(faces, "static const Design kDesigns["), #"\{(\d+), \d+, \d+\}"#).map { Int($0[0])! }
        let sfx = try String(contentsOf: assets.appendingPathComponent("sfx.h"), encoding: .utf8)
        let windows = rows(block(sfx, "static const Score kScore[] = {"), #"\{k\w+, \d+, \w+, \d+, \d+, (\d+)\},\s*// (\S+)"#)
        var n = 0
        for mood in FaceLoops.moods {
            for state in FaceLoops.states {
                for v in 1...FaceLoops.count(mood: mood, state: state) {
                    XCTAssertEqual(FaceLoops.ms(mood: mood, state: state, variant: v), loops[scenes[n]], "\(mood) \(state) \(v)")
                    XCTAssertEqual(windows[n][1], "\(mood).\(state).\(String(format: "%02d", v))")
                    XCTAssertEqual(FaceLoops.voiceMs(mood: mood, state: state, variant: v), Int64(windows[n][0])!,
                                   "\(mood) \(state) \(v)")
                    n += 1
                }
            }
        }
        XCTAssertEqual(n, 770)
        XCTAssertEqual(scenes.count, n)
        XCTAssertEqual(windows.count, n)
    }

    /// ARCHITECTURE.md §3.2, PROTOCOL.md §3: the app knows how long each
    /// moment plays on the device at most, as firmware/src/app/behaviour.cpp's
    /// `onMoment` and `play` time it: an animation its loops (1–6) of its
    /// design, the longest of the variations the device may play for the
    /// moment's facts; a face its loops of the look's design in its own mood
    /// (the device ends it on a loop boundary, so no later); and a mumble
    /// its beats and bubble when that's longer, from its design's voice
    /// window when it comes with an animation (VOICE.md §10). The loops and
    /// windows are `FaceLoops`, the numbers faces.h and sfx.h give the
    /// device.
    func testMomentLengthsFollowTheFirmware() {
        let cheer = FaceLoops.ms(mood: "happy", state: "task_complete")
        let idle = { (m: DeviceMoment) in m.playMs(look: "idle", mood: "happy") }
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", variant: 1, outcome: "success")), cheer, "once when it doesn't say")
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", loops: 3, variant: 1, outcome: "success")), 3 * cheer)
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", loops: 9, variant: 1, outcome: "success")), 6 * cheer, "at most 6")
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", loops: 0, variant: 1, outcome: "success")), cheer, "at least 1")
        XCTAssertEqual(DeviceMoment(anim: "task_complete", variant: 1, outcome: "success").playMs(look: "idle", mood: "proud"),
                       FaceLoops.ms(mood: "proud", state: "task_complete"), "in the mood's design")
        // With no variation, or one that isn't for its facts, the device
        // picks one of those that are: the longest of them.
        let wins = FaceLoops.variants(mood: "happy", state: "task_complete", outcome: "success")
        XCTAssertEqual(wins, [1, 2, 3, 4])
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", outcome: "success")), 7200)
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", variant: 5, outcome: "success")), 7200, "happy's fifth is a failure")
        XCTAssertEqual(idle(DeviceMoment(anim: "task_complete", variant: 1, outcome: "failure")), 5200)
        XCTAssertEqual(idle(DeviceMoment(anim: "starting", ctx: "session")),
                       FaceLoops.ms(mood: "happy", state: "starting", variant: 2))
        // A poke: its loops of poked's design.
        XCTAssertEqual(idle(DeviceMoment(anim: "poked", loops: 3)), 3 * FaceLoops.ms(mood: "happy", state: "poked"))

        // A take lasts its length, then 1.2 s of bubble, when that's longer
        // than the face; a reaction that says nothing, only its face.
        let working = { (m: DeviceMoment) in m.playMs(look: "working", mood: "happy") }
        let line = DeviceMoment.Say.test(ms: 720)
        XCTAssertEqual(working(DeviceMoment(say: line)), 1920)
        XCTAssertEqual(DeviceMoment(say: line).lineStartMs(mood: "happy"), 0, "at once on its own")
        XCTAssertEqual(working(DeviceMoment(say: .init(takes: []))), 0)
        XCTAssertEqual(DeviceMoment(say: .init(takes: [])).sayMs, 0)
        let quick = DeviceMoment.Say.test(ms: 360)
        XCTAssertEqual(working(DeviceMoment(anim: "task_complete", say: quick, variant: 1, outcome: "success")), cheer, "the finish is longer")

        // With an animation the line starts at the design's voice window,
        // and the animation holds on until the line and its bubble end.
        let grumpyFail = DeviceMoment(anim: "task_complete", say: line, mood: "grumpy", variant: 5, outcome: "failure")
        XCTAssertEqual(FaceLoops.voiceMs(mood: "grumpy", state: "task_complete", variant: 5), 5040)
        XCTAssertEqual(grumpyFail.lineStartMs(mood: "happy"), 5040, "in its own mood")
        XCTAssertEqual(working(grumpyFail), 5040 + 1920, "longer than its 5.2 s loop")
        XCTAssertEqual(working(DeviceMoment(anim: "reply_ready", say: line, variant: 1)),
                       FaceLoops.ms(mood: "happy", state: "reply_ready"), "450 + 1920 fits its loop")
        XCTAssertEqual(DeviceMoment(anim: "reply_ready", say: line).lineStartMs(mood: "happy"), 450)
        let lateWin = FaceLoops.variants(mood: "happy", state: "task_complete", outcome: "success")
            .map { FaceLoops.voiceMs(mood: "happy", state: "task_complete", variant: $0) }.max()!
        XCTAssertEqual(DeviceMoment(anim: "task_complete", say: line, outcome: "success").lineStartMs(mood: "happy"), lateWin,
                       "with no variation named, the latest window of those it may play")

        // A face holds its loops of the design showing, in its own mood,
        // timed by the look's longest variation, since they take turns on
        // the device (BEHAVIORS.md §2).
        let grumpy = (1...5).map { FaceLoops.ms(mood: "grumpy", state: "working", variant: $0) }.max()!
        XCTAssertEqual(grumpy, 4400)
        XCTAssertEqual(working(DeviceMoment(say: quick, mood: "grumpy")), grumpy)
        XCTAssertEqual(working(DeviceMoment(say: quick, mood: "grumpy", loops: 2)), 2 * grumpy)
        XCTAssertEqual(DeviceMoment(say: quick, mood: "grumpy").playMs(look: "task_complete", mood: "happy"),
                       7200, "over the cheer, the cheer's design, its longest")
        XCTAssertEqual(working(DeviceMoment(say: .test(ms: 3200), mood: "excited")), 4400, "a longer take holds it longer")
    }

    /// ARCHITECTURE.md §3.2: the schedule times a moment by the design
    /// showing: the look and mood of the last `state`. A reaction's face
    /// holds the brain's next one back.
    func testTheScheduleTimesAMomentByTheDesignShowing() {
        let line = DeviceMoment.Say.test(ms: 100)
        let proud = DeviceMoment(say: line, mood: "proud", loops: 2)
        // Two loops of a design's longest variation.
        let loop = { (mood: String, state: String) in
            2 * (1...FaceLoops.count(mood: mood, state: state)).map { FaceLoops.ms(mood: mood, state: state, variant: $0) }.max()!
        }
        XCTAssertNotEqual(loop("proud", "idle"), loop("proud", "working"))
        var schedule = MomentSchedule()
        schedule.look = "idle"
        var working = MomentSchedule()
        working.look = "working"
        XCTAssertEqual(schedule.playMs(proud), loop("proud", "idle"))
        XCTAssertEqual(working.playMs(proud), loop("proud", "working"))
        schedule.brain(proud, Pending(), now: 100)
        schedule.brain(proud, Pending(), now: 100)
        let due = schedule.due(now: 100, connected: true)
        XCTAssertEqual(due.play.queued, proud)
        XCTAssertEqual(schedule.lineUntil, 100 + loop("proud", "idle"), "its line waits for its face")
        XCTAssertEqual(schedule.next, 100 + proud.faceFirstMs + MomentSchedule.linkSlackMs, "the next, for its take")
    }

    /// ARCHITECTURE.md §3.2: a rule's one-shot plays at once, and a brain
    /// moment plays over it without waiting. None goes while a brain
    /// moment's line plays, which it would cut, nor while something needs
    /// you; a face held on after its line may be replaced.
    func testARuleOneShotPlaysAtOnceAndNeverCutsABrainLine() {
        var schedule = MomentSchedule()
        schedule.look = "working"
        XCTAssertTrue(schedule.rulePlays(now: 100))
        let line = DeviceMoment.Say.test(ms: 240)
        let face = DeviceMoment(say: line, mood: "grumpy")
        schedule.brain(face, Pending(), now: 200)
        let due = schedule.due(now: 200, connected: true)
        XCTAssertEqual(due.play.queued, face, "the brain's mumble plays over it")
        XCTAssertFalse(schedule.rulePlays(now: 300), "its line plays")
        let spoken = 200 + face.sayMs + MomentSchedule.linkSlackMs
        XCTAssertFalse(schedule.rulePlays(now: spoken - 1))
        XCTAssertTrue(schedule.rulePlays(now: spoken), "its face held on after the line may go")
        schedule.show(look: "working", mood: "happy", attn: true, now: spoken)
        XCTAssertFalse(schedule.rulePlays(now: spoken + 1), "something needs you")
    }

    /// BEHAVIORS.md §3.1: the rules' one-shot goes to the device right
    /// after the `state` of the same hook, with no `id`, and nothing waits
    /// on it.
    func testARuleOneShotFollowsItsState() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport, brain: ScriptedBrain(id: "jev-test", always: [:]))
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        eventually("first state") { transport.types().contains("state") }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the start") { transport.sent.contains { $0.contains(#""anim":"starting""#) } }
        let sent = transport.sent
        let start = try XCTUnwrap(sent.firstIndex { $0.contains(#""anim":"starting""#) })
        XCTAssertTrue(sent[start - 1].hasPrefix(#"{"t":"state""#) && sent[start - 1].contains(#""base":"working""#),
                      "\(sent)")
        XCTAssertTrue(sent[start].hasPrefix(#"{"t":"moment","anim":"starting","variant":"#)
                      && sent[start].hasSuffix(#","ctx":"new_task"}"#), sent[start])
        XCTAssertTrue(runtime.home.sync { runtime.schedule.playing.isEmpty }, "no brain waits on it")
    }

    /// PROTOCOL.md §3–4, ARCHITECTURE.md §3.2: a brain moment sent to the
    /// device holds the line until the device's `ended` for it, or until
    /// the app stops waiting for that (its length and `endGraceMs`); then
    /// the next one's turn comes. "Needs you" starting stops everything.
    func testTheDeviceSaysWhenTheLineIsFree() {
        let line = DeviceMoment.Say.test(ms: 720)
        let face = DeviceMoment(say: line, mood: "proud")
        func sent(_ schedule: inout MomentSchedule, at now: Int64) -> Int64 {
            XCTAssertEqual(schedule.due(now: now, connected: true).play.queued, face)
            return now + schedule.playMs(face) + MomentSchedule.endGraceMs
        }
        var schedule = MomentSchedule(lastId: 6)
        schedule.brain(face, Pending(), now: 0)
        let until = sent(&schedule, at: 0)
        XCTAssertEqual(schedule.holder?.until, until, "until its ended, at the latest when the app gives up on it")
        schedule.brain(face, Pending(), now: 1000)
        schedule.ended(.done(7), now: 1500)
        XCTAssertNil(schedule.holder)
        XCTAssertEqual(schedule.brainFree, 1500)
        XCTAssertEqual(schedule.due(now: 1500, connected: true).play.queued, face, "its turn")

        // No `ended`: the line is free once the app stops waiting for it.
        var silent = MomentSchedule()
        silent.brain(face, Pending(), now: 0)
        let deadline = sent(&silent, at: 0)
        XCTAssertEqual(silent.holder?.until, deadline)
        XCTAssertNil(silent.due(now: deadline, connected: true).play)
        XCTAssertNil(silent.holder)
        XCTAssertEqual(silent.brainFree, deadline)

        // Its `ended` frees it, and so does "needs you" starting.
        for free in ["ended", "needs you"] {
            var cut = MomentSchedule(lastId: 0)
            cut.brain(face, Pending(), now: 0)
            _ = sent(&cut, at: 0)
            cut.brain(face, Pending(), now: 500)
            XCTAssertNil(cut.due(now: 1000, connected: true).play)
            switch free {
            case "ended": cut.ended(.done(1), now: 1000)
            default: cut.show(look: "idle", mood: "happy", attn: true, now: 1000)
            }
            XCTAssertEqual(cut.brainFree, 1000, free)
            XCTAssertEqual(cut.due(now: 1000, connected: true).play.queued, face, free)
        }

        // Nothing plays with no device: `stop` frees everything.
        var gone = MomentSchedule()
        gone.brain(face, Pending(), now: 0)
        _ = sent(&gone, at: 0)
        gone.stop(now: 10)
        XCTAssertNil(gone.holder)
        XCTAssertEqual(gone.brainFree, 10)
    }

    /// harness/DECISIONS.md §5, ARCHITECTURE.md §3.2 (the owner's call,
    /// 2026-09-28): a reaction's face held on for its loops holds up the
    /// brain's next reaction only until its mumble has played (and
    /// `linkSlackMs`). The next is sent then, not dropped at 5 s, and
    /// replaces the face; the device says the first was done, and it
    /// settles done. The line itself waits for the face's `ended`.
    func testTheNextReactionReplacesAHeldFace() {
        let line = DeviceMoment.Say.test(ms: 720)
        let held = DeviceMoment(say: line, mood: "proud", loops: 4)  // its line is 1920 ms
        let next = DeviceMoment(say: line, mood: "grumpy")
        XCTAssertEqual(MomentSchedule.linkSlackMs, 500)
        XCTAssertEqual(held.sayMs, 1920)
        var moments = MomentSchedule()
        var ends: [String: Pending.End] = [:]
        let first = Pending(), second = Pending()
        first.bind { ends["first"] = $0 }
        second.bind { ends["second"] = $0 }
        moments.brain(held, first, now: 0)
        var play = moments.due(now: 0, connected: true)
        XCTAssertEqual(play.play.queued, held, "the first plays at once")
        guard let sent = play.play else { return }
        let faceEnds = 4 * FaceLoops.ms(mood: "proud", state: "idle", variant: 2)
        XCTAssertGreaterThanOrEqual(faceEnds, 16_000, "a face held four times over the idle look")
        XCTAssertEqual(moments.holder?.until, faceEnds + MomentSchedule.endGraceMs)

        moments.brain(next, second, now: 1000)
        XCTAssertEqual(moments.next, 1920 + 500, "asked back once the first's mumble has played")
        XCTAssertNil(moments.due(now: 2419, connected: true).play)
        play = moments.due(now: 2420, connected: true)
        XCTAssertEqual(play.play.queued, next, "sent then, over the held face")
        XCTAssertEqual(play.dropped, [])
        guard let replacing = play.play else { return }
        XCTAssertGreaterThan(moments.holder?.until ?? 0, 2420 + 1920, "the line waits for the second's ended")

        // The device ends the first at once, done: its line had played.
        moments.ended(MomentEnded(id: sent.id!, how: .done, why: nil), now: 2450)
        XCTAssertEqual(ends, ["first": .done])
        XCTAssertEqual(moments.holder?.id, replacing.id, "the second holds the line")
    }

    /// ARCHITECTURE.md §3.2: a brain moment's wait is counted to when its
    /// turn came, so a pump that runs a little late (up to `lateMs`) doesn't
    /// drop it; one that runs later counts to now. One still waiting past
    /// 5 s is dropped at once, not when the line frees, and the pump is
    /// asked back for that.
    func testAWaitIsCountedToItsTurn() {
        let line = DeviceMoment.Say.test(ms: 720)
        let face = DeviceMoment(say: line, mood: "proud")
        let cheer = DeviceMoment(anim: "task_complete", say: line, mood: "proud", outcome: "success")
        XCTAssertEqual(MomentSchedule.lateMs, 1000)
        let freed = cheer.playMs(look: "idle", mood: MoodAction.initial) + MomentSchedule.endGraceMs
        func schedule() -> MomentSchedule {
            var s = MomentSchedule()
            s.brain(cheer, Pending(), now: 0)
            _ = s.due(now: 0, connected: true)  // it holds the line until `freed`
            s.brain(face, Pending(), now: freed - 4840)
            return s
        }
        var late = schedule()
        XCTAssertEqual(late.next, freed)
        XCTAssertEqual(late.due(now: freed + 320, connected: true).play.queued, face, "its turn came after 4.84 s: the pump ran 0.32 s late")
        var later = schedule()
        XCTAssertEqual(later.due(now: freed + MomentSchedule.lateMs + 1, connected: true).dropped, [face], "too late to count from its turn")

        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        var stuck = MomentSchedule()
        let long = DeviceMoment(anim: "task_complete", say: line, mood: "proud", loops: 4, outcome: "success")
        stuck.brain(long, Pending(), now: 0)
        XCTAssertNotNil(stuck.due(now: 0, connected: true).play)
        XCTAssertGreaterThan(stuck.brainFree, 6001, "a long finish holds the line")
        stuck.brain(face, pending, now: 1000)
        XCTAssertEqual(stuck.next, 1000 + MomentSchedule.maxWaitMs + 1, "asked back when it's too old")
        XCTAssertNil(stuck.due(now: 6000, connected: true).play)
        XCTAssertEqual(ends, [], "5 s isn't over 5 s")
        let due = stuck.due(now: 6001, connected: true)
        XCTAssertEqual(due.dropped, [face], "dropped while the line is still busy")
        XCTAssertEqual(ends, [.failed("waited too long")])
        XCTAssertNil(stuck.next)
    }

    /// harness/DECISIONS.md §5: the schedule hands the pump a brain moment
    /// ready to send. With no device connected its handle ends at once and
    /// nothing holds the line; with one it goes with the next id, and it
    /// and its handle wait for the device's `ended`.
    func testTheScheduleSendsOrFailsTheMomentDue() {
        let face = DeviceMoment(say: .test(ms: 240), mood: "grumpy")
        var alone = MomentSchedule(lastId: 7)
        let lost = Pending()
        var ends: [Pending.End] = []
        lost.bind { ends.append($0) }
        alone.brain(face, lost, now: 0)
        let unsent = alone.due(now: 0, connected: false)
        XCTAssertEqual(unsent.play, face, "sent all the same, with no id")
        XCTAssertEqual(ends, [.failed("no device connected")])
        XCTAssertNil(alone.holder, "nothing holds the line")
        XCTAssertEqual(alone.brainFree, 0)
        XCTAssertEqual(alone.lastId, 7)

        var linked = MomentSchedule(lastId: 7)
        let open = Pending()
        open.bind { ends.append($0) }
        linked.brain(face, open, now: 0)
        let sent = linked.due(now: 0, connected: true)
        XCTAssertEqual(sent.play?.id, 8)
        XCTAssertEqual(linked.playing.map(\.id), [8])
        XCTAssertEqual(ends.count, 1, "its handle waits for the device")
        XCTAssertNotNil(linked.holder)
    }

    /// ARCHITECTURE.md §3.2, PROTOCOL.md §4: whatever frees the line sends
    /// the brain's next moment at once, rather than when the app's own
    /// reckoning of the last one runs out: the device's `ended` for the one
    /// playing, or "needs you" starting, which
    /// stops everything there. With no device connected a reaction doesn't
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
                self.recorded().filter { $0.phase == .end && $0.specificType == "react" }.map(Self.end)
            }
        }

        react("proud")
        XCTAssertEqual(moments(), 1, "plays at once")
        clock.now += 1000
        react("happy")
        XCTAssertEqual(moments(), 1, "waits for the first's face")
        device(#"{"t":"ended","id":\#(transport.momentIds[0]),"how":"done"}"#)
        XCTAssertEqual(moments(), 2, "the device says the first is over: the second goes at once")

        clock.now += 300
        react("excited")
        XCTAssertEqual(moments(), 2, "waits for the second")
        device(#"{"t":"input","k":"tap"}"#)
        XCTAssertEqual(moments(), 2, "the tap's poke may have come before the second arrived")
        device(#"{"t":"ended","id":\#(transport.momentIds[1]),"how":"cut","why":"tap"}"#)
        XCTAssertEqual(moments(), 3, "the device says the tap stopped the second")
        XCTAssertEqual(ends(), [.done, .failed("cut short: you tapped Boop")])

        clock.now += 300
        react("sad")
        XCTAssertEqual(moments(), 3, "waits for the third")
        let calm = runtime.home.sync { runtime.core.snapshot(at: clock.now) }
        var needsYou = calm
        needsYou.attn = .init(agent: "claude", project: "jetpack", more: 0)
        runtime.home.sync { runtime.show(needsYou) }
        XCTAssertEqual(moments(), 4, "\"needs you\" stops the third on the device: the fourth goes at once, for it to skip")
        runtime.home.sync { runtime.show(calm) }

        transport.onConnection?(false)
        runtime.home.sync {}
        XCTAssertEqual(ends().count, 4, "the two it was waiting on didn't happen")
        // The fourth may play on the device, and holds the line until the
        // app gives up on it; after that nothing is playing.
        clock.now = try XCTUnwrap(runtime.home.sync { runtime.schedule.holder?.until })
        runtime.home.sync { runtime.tick() }
        react("happy")
        react("sad")
        XCTAssertEqual(Array(ends().suffix(2)), [.failed("no device connected"), .failed("no device connected")],
                       "nothing played the first, so the second didn't wait for it")
    }

    /// ARCHITECTURE.md §3.2: "needs you" stops any line on the device and
    /// plays nothing while it shows (BEHAVIORS.md §1), so the schedule
    /// stops timing it: a reaction after it doesn't wait for a line that
    /// was cut, and is timed on the new look's design.
    func testNeedsYouEndsWhatTheScheduleThoughtWasPlaying() {
        let line = DeviceMoment.Say.test(ms: 100)
        let face = DeviceMoment(say: line, mood: "proud", loops: 2)
        var schedule = MomentSchedule()
        schedule.brain(face, Pending(), now: 0)
        XCTAssertEqual(schedule.due(now: 0, connected: true).play.queued, face)
        schedule.show(look: "working", mood: schedule.mood, attn: true, now: 300)
        XCTAssertEqual(schedule.lineUntil, 300)
        XCTAssertEqual(schedule.brainFree, 300)
        XCTAssertEqual(schedule.playMs(face), face.playMs(look: "working", mood: schedule.mood))
    }

    /// ARCHITECTURE.md §3.2: a brain moment that can no longer play in
    /// time is dropped once it has waited 5 s, even while a face holds the
    /// turn, and the schedule asks again when the first waiting one's 5 s
    /// run out.
    func testAWaitingMomentIsDroppedAtFiveSecondsWhateverPlays() {
        let line = DeviceMoment.Say.test(ms: 100)
        let long = DeviceMoment(anim: "task_complete", say: line, mood: "proud", loops: 4, outcome: "success")
        let next = DeviceMoment(say: line, mood: "happy")
        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        var schedule = MomentSchedule()
        schedule.brain(long, Pending(), now: 0)
        XCTAssertEqual(schedule.due(now: 0, connected: true).play.queued, long)
        XCTAssertGreaterThan(schedule.brainFree, 5501, "four loops of a finish")
        schedule.brain(next, pending, now: 500)
        let early = schedule.due(now: 1000, connected: true)
        XCTAssertNil(early.play)
        XCTAssertEqual(schedule.next, 500 + MomentSchedule.maxWaitMs + 1, "when it has waited too long")
        let due = schedule.due(now: 5501, connected: true)
        XCTAssertEqual(due.dropped, [next])
        XCTAssertEqual(ends, [.failed("waited too long")])
        XCTAssertNil(schedule.next, "nothing waits")
    }

    /// ARCHITECTURE.md §3.2: each tick drops a reaction that has waited
    /// 5 s, before the harness's ceiling could end it, whatever the pump's
    /// timer does (a clock jump, or the Mac asleep).
    func testTheScheduleFollowsTicks() throws {
        let transport = FakeTransport()
        var options = try options(transport, brain: ScriptedBrain(always: [:]))
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        runtime.home.sync {}
        let line = DeviceMoment.Say.test(ms: 100)
        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        runtime.home.sync {
            runtime.schedule.brain(DeviceMoment(say: line, mood: "sad"), pending, now: clock.now)
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
        let line = DeviceMoment.Say.test(ms: 100)
        let moments = { transport.sent.filter { $0.hasPrefix(#"{"t":"moment""#) } }
        runtime.home.sync {
            runtime.schedule.brain(DeviceMoment(say: line, mood: "proud", loops: 4), Pending(), now: clock.now)
            runtime.schedule.brain(DeviceMoment(say: line, mood: "happy"), Pending(), now: clock.now)
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
                self.recorded().filter { $0.phase == .end && $0.specificType == "react" }.map(Self.end)
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
    /// `ended` for it frees the line when it ends. Before, the tap freed the line, and the next reaction
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
        XCTAssertGreaterThan(runtime.home.sync { runtime.schedule.holder?.until ?? 0 }, clock.now)
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
        let pumpAt = { runtime.home.sync { runtime.pumpAt } }

        react("proud")
        clock.now += 1000
        react("happy")
        let free = { runtime.home.sync { runtime.schedule.brainFree } }
        XCTAssertEqual(pumpAt(), free(), "the second waits for the first's mumble")
        XCTAssertGreaterThan(free(), clock.now)
        clock.now += 60_000  // the Mac slept, and the timer with it
        react("grumpy")  // the second is dropped, and this one plays
        XCTAssertEqual(runtime.home.sync { runtime.schedule.waiting.count }, 0)
        clock.now += 1000
        react("excited")
        XCTAssertEqual(pumpAt(), free(), "a timer of its own, not the late one")
        XCTAssertGreaterThan(free(), clock.now)
    }

    /// PROTOCOL.md §3: moment ids start somewhere random at every launch
    /// and count up, so an earlier launch's moment still on the device
    /// can't share one; they stay within 1...Int32.max for the device.
    func testMomentIdsDifferEachLaunch() {
        let firsts = Set((0..<8).map { _ in MomentSchedule().lastId })
        XCTAssertGreaterThan(firsts.count, 1, "random")
        XCTAssertTrue(firsts.allSatisfy { (0..<Int(Int32.max)).contains($0) })
        XCTAssertEqual(MomentSchedule.nextId(after: 41), 42)
        XCTAssertEqual(MomentSchedule.nextId(after: Int(Int32.max)), 1, "back to 1, never 0")
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
    /// other than calm, the resting mood (DECISIONS.md §4), and nothing
    /// else; the harness only places it.
    func testHistoryClosesWithTheMoodsTime() throws {
        let clock = VirtualClock(1_790_000_000_000)
        let dir = tempDir("boop-since")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (harness, moodAction) = Runtime.harness(
            brain: nil, pipeline: Pipeline(core: Core(config: .init()), view: TranscriptView()),
            mood: MoodStore(stateDir: dir), steering: Self.steering,
            personality: { .boop }, time: LocalTime(timeZone: TimeZone(identifier: "UTC")!),
            clock: { clock.now }, wall: { clock.now }, queue: { _, _ in }, home: DispatchQueue(label: "boop.test"))
        func closing() -> String? { harness.parts().closing }
        XCTAssertNil(closing(), "calm says nothing")
        _ = moodAction.change(to: "grumpy")
        clock.now += 30_000
        XCTAssertEqual(closing(), "Boop has been grumpy for under a minute.")
        clock.now += 2 * 60_000
        XCTAssertEqual(moodAction.sinceLine(at: clock.now), "Boop has been grumpy for 2 min.", "whole minutes, as HISTORY's")
        XCTAssertNil(MoodAction(store: MoodStore(stateDir: dir)).sinceLine(at: clock.now),
                     "grumpy on disk, but nothing before a change since launch")
        _ = moodAction.change(to: "happy")
        XCTAssertEqual(moodAction.sinceLine(at: clock.now), "Boop has been happy for under a minute.", "happy is a mood like any other")
        _ = moodAction.change(to: "calm")
        XCTAssertNil(moodAction.sinceLine(at: clock.now), "back to calm")
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

extension Optional where Wrapped == DeviceMoment {
    /// The moment as it was queued, without the id `due` sent it with.
    var queued: DeviceMoment? { map { var m = $0; m.id = nil; return m } }
}

extension MomentEnded {
    /// The device's `ended` for `id`, played to the end.
    static func done(_ id: Int) -> MomentEnded { MomentEnded(id: id, how: .done) }
}
