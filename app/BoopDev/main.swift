import BoopKit
import Foundation
import HookWire

// Developer CLI (VERIFICATION.md §2): eval, watch, replay, voice, talk and
// hooks, as `usage` describes.

let usage = """
    usage: boopdev replay <hooks.jsonl> [--agent claude|codex] [--gap-ms N] [--start MS] [--tz ZONE] [--new-day] [--states]
               Runs recorded hook payloads through boop-hook's field picking, the adapter and the core,
               on a virtual clock, and prints what the core decides. {"wait_ms":N} and {"advance_ms":N} move the clock.
           boopdev replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]
               Sends each payload through the real boop-hook binary to a running app's socket, in real time:
               {"wait_ms":N} waits, and {"advance_ms":N} jumps a headless app's clock.
           boopdev voice <feeling> [word] [--dialect HEX] [--seed N] [--count N] [--json] [--why]
               Prints Minion lines as the react action would build them.
           boopdev eval [--real] [--mode chatty|normal|calm] [--classifier \(Brains.classifiers.joined(separator: "|"))] [--writer none|apple]
                [--runs N] [--only TEXT] [--json FILE] [--scenarios DIR] [--memory DIR] [--steering FILE]
               Runs the harness eval scenarios in each mode: events, taps and talk on a virtual clock through a
               fresh core, the real harness and actions, each step checked against the passes it should lead to
               in that mode (plan/EVALS.md). By default each mode with an if-else table and no writer, which is
               deterministic; --classifier jev decides with Jev and needs BOOP_JEV_KEY. With a model, --runs
               runs each scenario N times, and it passes only if every run does. Every pass goes to the run's
               own file in /tmp/boop-eval, named at the start (boopdev watch FILE prints it). Exits 1 if any fails.
               --real runs every mode with its real brains (VERIFICATION.md L5): Apple's model writes, normal
               decides with Jev alone (with BOOP_JEV_KEY; else its table), 3 runs each; then refusals, the writer's
               slots, calls actions dropped and each input kind's latency against its deadline, which must hold
               too. Steps that script a stage are left out of that.
           boopdev watch [FILE] [--new]
               Follows debug mode's log (Boop --debug writes STATE-DIR/debug.jsonl; the default is the
               everyday app's) and prints each pass and aside readably, as Boop --debug does in its own
               terminal. --new skips what's already in the file.
           boopdev hooks status|install|remove [claude|codex] --home DIR [--hook PATH]
               The installer, against any HOME (tests use a temporary one). --hook defaults to the boop-hook
               next to boopdev.
           boopdev talk "<words>" [--yelled] --socket PATH
               Hands a push-to-talk transcript to a running headless app, as if heard on the Mac's mic
               (--yelled: as if you yelled it).
    (boop \(BoopVersion.current))
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func option(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func replay(_ args: [String]) {
    var rest: [String] = []
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") {
            i += ["--new-day", "--states"].contains(args[i]) ? 1 : 2
        } else {
            rest.append(args[i])
            i += 1
        }
    }
    guard let path = rest.first else { fail(usage) }
    let agent = option(args, "--agent") ?? (path.contains("/codex/") ? "codex" : "claude")
    let gap = Int64(option(args, "--gap-ms") ?? "1000") ?? 1000
    let steps: [Replay.Step]
    do { steps = try Replay.steps(fromFile: path) } catch { fail("can't read \(path): \(error)") }

    if let socket = option(args, "--socket") {
        replayLive(steps, agent: agent, gapMs: gap, socket: socket)
        return
    }
    var replay = Replay(agent: agent)
    replay.gapMs = gap
    if let start = option(args, "--start").flatMap(Int64.init) { replay.start = start }
    if let zone = option(args, "--tz").flatMap(TimeZone.init(identifier:)) { replay.time = LocalTime(timeZone: zone) }
    replay.newDay = args.contains("--new-day")
    for line in replay.run(steps, statesOnly: args.contains("--states")) { print(line) }
}

/// Sends payloads through the real `boop-hook`, as agents would, and prints
/// when each was sent so the caller can measure latency. `boop-hook` fails
/// open, so the app is asked first: with nobody listening, every hook would
/// still exit 0.
func replayLive(_ steps: [Replay.Step], agent: String, gapMs: Int64, socket: String) {
    let hook = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("boop-hook")
    guard FileManager.default.isExecutableFile(atPath: hook.path) else { fail("no boop-hook next to boopdev; run make build") }
    guard HookSocket.send(Data(#"{"dev":"probe"}"#.utf8) + [0x0A], to: socket, timeoutMs: 500) else {
        fail("no app answering on \(socket)")
    }
    var environment = ProcessInfo.processInfo.environment
    environment["BOOP_SOCKET"] = socket
    for step in steps {
        switch step {
        case .wait(let ms):
            usleep(useconds_t(ms * 1000))
        case .advance(let ms):
            // A headless app jumps its clock; the menu-bar app ignores this.
            let line = Data(#"{"dev":"advance","ms":\#(ms)}"#.utf8) + [0x0A]
            guard HookSocket.send(line, to: socket, timeoutMs: 500) else { fail("no app answering on \(socket)") }
            print("advanced the app's clock \(ms) ms")
        case .payload(let data):
            let process = Process()
            process.executableURL = hook
            process.arguments = [agent]
            process.environment = environment
            let pipe = Pipe()
            process.standardInput = pipe
            let sent = Date()
            do {
                try process.run()
                try pipe.fileHandleForWriting.write(contentsOf: data)
                try pipe.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch {
                fail("boop-hook failed: \(error)")
            }
            let ms = Int(Date().timeIntervalSince(sent) * 1000)
            let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hook_event_name"] as? String
            print("sent \(name ?? "?") at \(Int64(sent.timeIntervalSince1970 * 1000)) hook \(ms) ms exit \(process.terminationStatus)")
            usleep(useconds_t(gapMs * 1000))
        }
    }
}

func voice(_ args: [String]) {
    let words = args.filter { !$0.hasPrefix("--") && !["--dialect", "--seed", "--count"].contains(args[max(0, (args.firstIndex(of: $0) ?? 0) - 1)]) }
    guard let feeling = words.first.flatMap(Feeling.init(rawValue:)) else {
        fail("feelings: " + Feeling.allCases.map(\.rawValue).joined(separator: ", "))
    }
    let word = words.count > 1 ? words[1] : nil
    if let word, !Sounds.vocabulary.contains(word) { fail("words: " + Sounds.vocabulary.joined(separator: ", ")) }
    let dialect = Dialect(seed: option(args, "--dialect").flatMap { UInt64($0, radix: 16) } ?? 0x7f3a)
    let v = Voice(dialect: dialect)
    let first = option(args, "--seed").flatMap(UInt64.init) ?? 1
    let count = option(args, "--count").flatMap(UInt64.init) ?? 1
    if !args.contains("--json") { print("dialect \(String(dialect.seed, radix: 16)): \(dialect.favourites.joined(separator: " "))") }
    for seed in first..<(first + count) {
        let line = v.line(feeling, word: word, seed: seed, rejected: { groups, why in
            if let why, args.contains("--why") { print("  tried \(groups.map { $0.joined(separator: "-") }.joined(separator: " ")): \(why)") }
        })
        print(args.contains("--json") ? line.json : "\(seed)\t\(line.text)\t\(line.tune.rawValue) \(line.ms) ms")
    }
}

/// `plan/steering.md`, found from the working directory upwards.
func findSteering() -> String? {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = dir.appendingPathComponent("plan/steering.md")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        dir = dir.deletingLastPathComponent()
    }
    return nil
}

/// `boopdev watch [FILE]`: follows debug mode's log (HARNESS.md §8) and
/// prints each pass and aside as it lands, as `Boop --debug` does. The app
/// empties the file when it starts, so a shorter file, or a new one at the
/// path, starts it again.
func watch(_ args: [String]) {
    let path = args.first(where: { !$0.hasPrefix("--") })
        ?? AppSettings.defaultStateDir().appendingPathComponent(DebugLog.fileName).path
    let fm = FileManager.default
    func open() -> (FileHandle, Int?) {
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forReadingAtPath: path) else { fail("can't read \(path)") }
        return (handle, (try? fm.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int)
    }
    var (handle, file) = open()
    if args.contains("--new") { handle.seekToEndOfFile() }
    setvbuf(stdout, nil, _IOLBF, 0)
    print("watching \(path) (Ctrl-C to stop)")
    var printer = DebugLog.Printer()
    var pending = ""
    while true {
        let data = handle.availableData
        if data.isEmpty {
            let attributes = try? fm.attributesOfItem(atPath: path)
            let size = attributes?[.size] as? UInt64 ?? 0
            if size < handle.offsetInFile || attributes?[.systemFileNumber] as? Int != file {
                print("— \(path) started again —")
                try? handle.close()
                (handle, file) = open()
                printer = DebugLog.Printer()
                pending = ""
            }
            usleep(250_000)
            continue
        }
        pending += String(decoding: data, as: UTF8.self)
        while let end = pending.firstIndex(of: "\n") {
            let line = String(pending[..<end])
            pending = String(pending[pending.index(after: end)...])
            if !line.isEmpty { print(printer.readable(line)) }
        }
    }
}

func eval(_ args: [String]) async {
    let scenarios = URL(fileURLWithPath: option(args, "--scenarios") ?? "app/Evals/scenarios")
    let memoryDir = URL(fileURLWithPath: option(args, "--memory") ?? "app/Tests/Fixtures/memory")
    guard let steeringPath = option(args, "--steering") ?? findSteering(),
          let steering = try? String(contentsOfFile: steeringPath, encoding: .utf8)
    else { fail("can't find steering.md; pass --steering") }
    // --real: every mode with the brains the app would run (VERIFICATION.md L5).
    let real = args.contains("--real")
    var modes = real ? Mode.allCases : Eval.deterministic
    if let name = option(args, "--mode") {
        guard let mode = Mode(rawValue: name) else { fail("modes: chatty, normal, calm") }
        modes = [mode]
    }
    let override = option(args, "--classifier")
    if let override, !Brains.classifiers.contains(override) { fail("classifiers: " + Brains.classifiers.joined(separator: ", ")) }
    // Jev only when asked for, or for normal in a real run with its key, so
    // a key in the environment doesn't make the default run a live one. A
    // real run asks for Jev by name: Jev alone decides normal, which is what
    // L5 checks. Without the key, normal's table decides it.
    let envKey = ProcessInfo.processInfo.environment[Brains.jevKeyVariable].flatMap { $0.isEmpty ? nil : $0 }
    if envKey == nil, override == "jev" { fail("Jev needs its API key in \(Brains.jevKeyVariable)") }
    let jev: @Sendable (Mode) -> String? = { mode in override ?? (real && mode == .normal && envKey != nil ? "jev" : nil) }
    let key = modes.contains { jev($0) == "jev" } ? envKey : nil
    if real, override == nil, envKey == nil, modes.contains(.normal) {
        print("normal: decided by its table; with Jev's API key in \(Brains.jevKeyVariable), Jev decides it")
    }
    let writerName = option(args, "--writer") ?? (real ? "apple" : "none")
    guard ["none", "apple"].contains(writerName) else { fail("writers: none, apple") }
    if writerName == "apple", let why = AppleWriter.unavailableReason { fail("Apple's model can't run here: \(why)") }
    var list: [Scenario]
    do { list = try Scenario.load(directory: scenarios) } catch { fail("\(error)") }
    if let only = option(args, "--only") {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    guard !list.isEmpty else { fail("no scenarios in \(scenarios.path)") }
    guard let runs = Int(option(args, "--runs") ?? (real ? "3" : "1")), runs >= 1 else { fail("--runs is a count, 1 or more") }
    var runner = Eval(
        classifier: { mode in Brains.classifier(for: mode, override: jev(mode), key: { key }) },
        writer: { mode in writerName == "none" ? NoWriter() : Brains.writer(for: mode) },
        steering: steering, memory: memoryDir)
    let log = evalDebugLog()
    runner.debugLog = log
    DebugLog.start(log)
    print("every pass goes to \(log.path)")
    // One entry per scenario and mode: its runs.
    var results: [[Eval.Result]] = []
    for mode in modes {
        for scenario in list where scenario.modes.contains(mode) {
            var rs: [Eval.Result] = []
            for _ in 0..<runs {
                do { rs.append(try await runner.run(scenario, mode: mode)) } catch { fail("\(scenario.file): \(error)") }
            }
            results.append(rs)
            let passed = rs.filter(\.passed).count
            let tally = runs > 1 ? "  (\(passed)/\(runs) runs)" : ""
            print((passed == runs ? "pass  " : "FAIL  ") + "\(mode.rawValue)  \(scenario.file)  \(scenario.name)\(tally)")
            // Each different failure once, most common first.
            var diffs: [String: Int] = [:]
            for r in rs where !r.passed { diffs[Eval.diff(r), default: 0] += 1 }
            for (diff, n) in diffs.sorted(by: { $0.value > $1.value }) {
                if runs > 1 { print("  in \(n) of \(runs) runs:") }
                print(diff)
            }
        }
    }
    let passed = results.filter { $0.allSatisfy(\.passed) }.count
    let every = runs > 1 ? " in all \(runs) runs" : ""
    let brains = modes.map { mode in
        let r = results.first { $0.first?.mode == mode }?.first
        return "\(mode.rawValue) \(r?.classifier ?? "?") + \(r?.writer ?? "?")"
    }
    print("\(passed)/\(results.count) passed\(every): " + brains.joined(separator: ", "))
    if let out = option(args, "--json") {
        do { try Eval.json(results).write(toFile: out, atomically: true, encoding: .utf8) }
        catch { fail("can't write \(out): \(error)") }
    }
    var summaryHolds = true
    if real {
        let summary = Eval.Summary(results.flatMap { $0.flatMap(\.brainPasses) })
        summary.lines.forEach { print($0) }
        summaryHolds = summary.holds
    }
    print("every pass: boopdev watch \(log.path)")
    exit(passed == results.count && summaryHolds ? 0 : 1)
}

/// A file of the run's own for every pass (HARNESS.md §8), so runs side by
/// side don't write over each other. Runs over a day old are cleared away.
func evalDebugLog() -> URL {
    let dir = URL(fileURLWithPath: "/tmp/boop-eval")
    let fm = FileManager.default
    let dayAgo = Date().addingTimeInterval(-86_400)
    for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    where (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).flatMap { $0 < dayAgo } == true {
        try? fm.removeItem(at: file)
    }
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    return dir.appendingPathComponent("\(stamp.string(from: Date()))-\(getpid()).jsonl")
}

func talk(_ args: [String]) {
    guard let socket = option(args, "--socket") else { fail(usage) }
    let words = args.enumerated().filter { i, a in !a.hasPrefix("--") && (i == 0 || args[i - 1] != "--socket") }
        .map(\.element).joined(separator: " ")
    let yelled = args.contains("--yelled")
    guard !words.isEmpty || yelled else { fail(usage) }
    var data = (try? JSONSerialization.data(withJSONObject: ["dev": "talk", "words": words, "yelled": yelled] as [String: Any]))
        ?? Data()
    data.append(0x0A)
    guard HookSocket.send(data, to: socket, timeoutMs: 500) else { fail("no app answering on \(socket)") }
    print("sent talk \"\(words)\"\(yelled ? " (yelled)" : "")")
}

func hooks(_ args: [String]) {
    guard let action = args.first, let home = option(args, "--home") else { fail(usage) }
    let built = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("boop-hook")
    let installer = HookInstaller(home: URL(fileURLWithPath: home), hookPath: option(args, "--hook") ?? built.path)
    let agents = args.dropFirst().first.flatMap(HookInstaller.Agent.init(rawValue:)).map { [$0] } ?? HookInstaller.Agent.allCases
    for agent in agents {
        do {
            switch action {
            case "install": try installer.install(agent)
            case "remove": try installer.remove(agent)
            case "status": break
            default: fail(usage)
            }
        } catch {
            fail("\(agent.rawValue): \(error)")
        }
        print("\(agent.rawValue): \(installer.health(agent))")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "replay":
    replay(Array(args.dropFirst()))
case "voice":
    voice(Array(args.dropFirst()))
case "eval":
    await eval(Array(args.dropFirst()))
case "watch":
    watch(Array(args.dropFirst()))
case "talk":
    talk(Array(args.dropFirst()))
case "hooks":
    hooks(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
