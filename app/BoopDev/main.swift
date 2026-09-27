import BoopKit
import Foundation
import HookWire

// Developer CLI (VERIFICATION.md §2): eval, watch, replay, voice, talk and
// hooks, as `usage` describes.

/// Each subcommand's usage, in the order `boopdev --help` lists them.
let usages: [(command: String, text: String)] = [
    ("replay", """
    boopdev replay <hooks.jsonl> [--agent claude|codex] [--gap-ms N] [--start MS] [--tz ZONE] [--new-day] [--states]
        Runs recorded hook payloads through boop-hook's field picking, the adapter and the core,
        on a virtual clock, and prints what the core decides. {"wait_ms":N} and {"advance_ms":N} move the clock.
    boopdev replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]
        Sends each payload through the real boop-hook binary to a running app's socket, in real time, and
        prints how long each boop-hook took: {"wait_ms":N} waits, and {"advance_ms":N} jumps a headless
        app's clock.
    """),
    ("voice", """
    boopdev voice <feeling> [word] [--dialect HEX] [--seed N] [--count N] [--json] [--why]
        Prints Minion lines as the react action would build them.
    """),
    ("eval", """
    boopdev eval [--real] [--mode chatty|normal|calm] [--classifier \(Brains.classifiers.joined(separator: "|"))] [--writer \(Brains.writers.joined(separator: "|"))]
         [--runs N] [--only TEXT] [--json FILE] [--scenarios DIR] [--memory DIR] [--steering FILE]
        Runs the harness eval scenarios in each mode: events, taps and talk on a virtual clock through a
        fresh core, the real harness and actions, each step checked against the passes it should lead to
        in that mode (plan/EVALS.md). By default each mode with an if-else table and no writer, which is
        deterministic; --classifier jev decides with Jev and needs BOOP_JEV_KEY. With a model, --runs
        runs each scenario N times, and it passes only if every run does. Every pass goes to the run's
        own file in /tmp/boop-eval, named at the start, each scenario's run under a header (boopdev watch
        FILE prints it). Exits 1 if any fails. The scenarios, sample memory and steering.md default to
        the Boop repo's, found from the working directory or from boopdev's own place in it.
        --real runs every mode with its real brains (VERIFICATION.md L5): Apple's model writes, normal
        decides with Jev alone (with BOOP_JEV_KEY; else its table), 3 runs each; then refusals, the writer's
        slots, calls actions dropped and each input kind's latency against its deadline, which must hold
        too. Steps that script a stage are left out of that.
    """),
    ("watch", """
    boopdev watch [FILE] [--new]
        Follows debug mode's log (Boop --debug writes STATE-DIR/debug.jsonl; the default is the
        everyday app's) and prints each pass and aside readably, as Boop --debug does in its own
        terminal, waiting for FILE if it isn't there yet. --new skips what's already in the file.
    """),
    ("hooks", """
    boopdev hooks status|install|remove [claude|codex] --home DIR [--hook PATH]
        The installer, against any HOME (tests use a temporary one). --hook defaults to the boop-hook
        next to boopdev.
    """),
    ("talk", """
    boopdev talk "<words>" [--yelled] --socket PATH
        Hands a push-to-talk transcript to a running headless app, as if heard on the Mac's mic
        (--yelled: as if you yelled it).
    """),
]

let version = "(boop \(BoopVersion.current))"
/// Indented under "usage:", as each command's own lines are under it.
func indented(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
}
let usage = "usage:\n" + usages.map { indented($0.text) }.joined(separator: "\n") + "\n"
    + "Each command prints its own usage with --help, and stops on a flag it doesn't take.\n" + version

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

/// The `boop-hook` built next to boopdev.
let builtHook = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("boop-hook")

/// Sends one line to a running app's socket, or stops if nobody answers.
func sendDev(_ line: Data, to socket: String) {
    guard HookSocket.send(line + [0x0A], to: socket, timeoutMs: 500) else { fail("no app answering on \(socket)") }
}

/// A subcommand's arguments, checked against what it takes (VERIFICATION.md
/// §2): --help prints its usage and exits, and anything else stops it.
func arguments(_ command: String, _ args: [String], options: Set<String> = [], flags: Set<String> = [],
               words: Int = 0) -> Arguments {
    let text = "usage:\n" + indented(usages.first { $0.command == command }?.text ?? "") + "\n" + version
    return Arguments.parse(args, options: options, flags: flags, words: words, command: "boopdev \(command)", usage: text)
}

func replay(_ raw: [String]) {
    let args = arguments("replay", raw, options: ["--agent", "--gap-ms", "--start", "--tz", "--socket"],
                         flags: ["--new-day", "--states"], words: 1)
    guard let path = args.words.first else { fail("boopdev replay: which hooks.jsonl?") }
    let agent = args["--agent"] ?? (path.contains("/codex/") ? "codex" : "claude")
    guard let gap = Int64(args["--gap-ms"] ?? "1000") else { fail("--gap-ms is a number of milliseconds") }
    let steps: [Replay.Step]
    do { steps = try Replay.steps(fromFile: path) } catch { fail("can't read \(path): \(error)") }

    if let socket = args["--socket"] {
        replayLive(steps, agent: agent, gapMs: gap, socket: socket)
        return
    }
    var replay = Replay(agent: agent)
    replay.gapMs = gap
    if let start = args["--start"] {
        guard let ms = Int64(start) else { fail("--start is milliseconds since 1970") }
        replay.start = ms
    }
    if let tz = args["--tz"] {
        guard let zone = TimeZone(identifier: tz) else { fail("--tz is a time zone such as Europe/London") }
        replay.time = LocalTime(timeZone: zone)
    }
    replay.newDay = args.has("--new-day")
    for line in replay.run(steps, statesOnly: args.has("--states")) { print(line) }
}

/// Sends payloads through the real `boop-hook`, as agents would, and prints
/// when each was sent and how long `boop-hook` took, from launch to exit.
/// `boop-hook` fails open, so the app is asked first: with nobody
/// listening, every hook would still exit 0.
func replayLive(_ steps: [Replay.Step], agent: String, gapMs: Int64, socket: String) {
    guard FileManager.default.isExecutableFile(atPath: builtHook.path) else { fail("no boop-hook next to boopdev; run make build") }
    sendDev(Data(#"{"dev":"probe"}"#.utf8), to: socket)
    var environment = ProcessInfo.processInfo.environment
    environment["BOOP_SOCKET"] = socket
    for step in steps {
        switch step {
        case .wait(let ms):
            usleep(useconds_t(ms * 1000))
        case .advance(let ms):
            // A headless app jumps its clock; the menu-bar app ignores this.
            sendDev(Data(#"{"dev":"advance","ms":\#(ms)}"#.utf8), to: socket)
            print("advanced the app's clock \(ms) ms")
        case .payload(let data):
            let sent = Date()
            guard let (ms, status) = spawn(builtHook.path, [agent], stdin: data, environment: environment) else {
                fail("can't run \(builtHook.path): \(String(cString: strerror(errno)))")
            }
            let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hook_event_name"] as? String
            print("sent \(name ?? "?") at \(Int64(sent.timeIntervalSince1970 * 1000)) hook \(String(format: "%.1f", ms)) ms exit \(status)")
            usleep(useconds_t(gapMs * 1000))
        }
    }
}

/// Runs `path` with `stdin`, and returns how long it took from launch to
/// exit, in ms, and its exit status. Foundation's `Process` adds about
/// 60 ms of its own waiting, which would swamp `boop-hook`'s few.
func spawn(_ path: String, _ args: [String], stdin: Data, environment: [String: String]) -> (Double, Int32)? {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return nil }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, fds[0], 0)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    let argv = ([path] + args).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { (argv + envp).forEach { free($0) } }
    var pid: pid_t = 0
    let start = DispatchTime.now().uptimeNanoseconds
    let spawned = posix_spawn(&pid, path, &actions, nil, argv, envp)
    close(fds[0])
    guard spawned == 0 else {
        close(fds[1])
        errno = spawned
        return nil
    }
    stdin.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let n = write(fds[1], bytes.baseAddress! + offset, bytes.count - offset)
            if n <= 0 { break }
            offset += n
        }
    }
    close(fds[1])
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    // WIFEXITED and WEXITSTATUS, which Swift doesn't import.
    return (ms, status & 0x7f == 0 ? (status >> 8) & 0xff : -1)
}

func voice(_ raw: [String]) {
    let args = arguments("voice", raw, options: ["--dialect", "--seed", "--count"], flags: ["--json", "--why"], words: 2)
    let words = args.words
    guard let feeling = words.first.flatMap(Feeling.init(rawValue:)) else {
        fail("feelings: " + Feeling.allCases.map(\.rawValue).joined(separator: ", "))
    }
    let word = words.count > 1 ? words[1] : nil
    if let word, !Sounds.vocabulary.contains(word) { fail("words: " + Sounds.vocabulary.joined(separator: ", ")) }
    guard let dialectSeed = UInt64(args["--dialect"] ?? "7f3a", radix: 16) else { fail("--dialect is a hex seed, such as 7f3a") }
    let dialect = Dialect(seed: dialectSeed)
    let v = Voice(dialect: dialect)
    guard let first = UInt64(args["--seed"] ?? "1"), let count = UInt64(args["--count"] ?? "1") else {
        fail("--seed and --count are whole numbers")
    }
    if !args.has("--json") { print("dialect \(String(dialect.seed, radix: 16)): \(dialect.favourites.joined(separator: " "))") }
    for seed in first..<(first + count) {
        let line = v.line(feeling, word: word, seed: seed, rejected: { groups, why in
            if let why, args.has("--why") { print("  tried \(groups.map { $0.joined(separator: "-") }.joined(separator: " ")): \(why)") }
        })
        print(args.has("--json") ? line.json : "\(seed)\t\(line.text)\t\(line.tune.rawValue) \(line.ms) ms")
    }
}

/// The Boop repo: the nearest folder with `plan/steering.md` above the
/// working directory, or else above boopdev itself (`app/.build/debug`).
func findRepo() -> URL? {
    let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                  URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()]
    for start in starts {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("plan/steering.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
    }
    return nil
}

/// `boopdev watch [FILE]`: follows debug mode's log (HARNESS.md §8) and
/// prints each pass and aside as it lands, as `Boop --debug` does. The app
/// empties the file when it starts, so a shorter file, or a new one at the
/// path, starts it again.
func watch(_ raw: [String]) {
    let args = arguments("watch", raw, flags: ["--new"], words: 1)
    let path = args.words.first ?? AppSettings.defaultStateDir().appendingPathComponent(DebugLog.fileName).path
    let fm = FileManager.default
    setvbuf(stdout, nil, _IOLBF, 0)
    /// Waits for the file rather than making it: a typo, or an app not in
    /// debug mode, says so instead of watching a new empty file forever.
    func open() -> (FileHandle, Int?) {
        if !fm.fileExists(atPath: path) {
            print("waiting for \(path) (is Boop running with --debug?)")
            while !fm.fileExists(atPath: path) { usleep(250_000) }
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { fail("can't read \(path)") }
        return (handle, (try? fm.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int)
    }
    print("watching \(path) (Ctrl-C to stop)")
    var (handle, file) = open()
    if args.has("--new") { handle.seekToEndOfFile() }
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
            if line.isEmpty { continue }
            print(printer.readable(line))
        }
    }
}

func eval(_ raw: [String]) async {
    let args = arguments("eval", raw, options: ["--mode", "--classifier", "--writer", "--runs", "--only", "--json",
                                                 "--scenarios", "--memory", "--steering"], flags: ["--real"])
    // The defaults are the repo's, wherever boopdev runs from.
    let repo = findRepo()
    func path(_ option: String, _ inRepo: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        guard let repo else { fail("boopdev eval: can't find the Boop repo (no plan/steering.md above here); run it inside the repo, or pass --scenarios, --memory and --steering") }
        return repo.appendingPathComponent(inRepo)
    }
    let scenarios = path("--scenarios", "app/Evals/scenarios")
    let memoryDir = path("--memory", "app/Tests/Fixtures/memory")
    let steeringPath = path("--steering", "plan/steering.md")
    guard let steering = try? String(contentsOf: steeringPath, encoding: .utf8) else { fail("can't read \(steeringPath.path)") }
    guard FileManager.default.fileExists(atPath: memoryDir.appendingPathComponent("long-term.md").path) else {
        fail("no sample memory (long-term.md) in \(memoryDir.path)")
    }
    // --real: every mode with the brains the app would run (VERIFICATION.md L5).
    let real = args.has("--real")
    var modes = Mode.allCases
    if let mode = args.choice("--mode", of: modes.map(\.rawValue)).flatMap(Mode.init(rawValue:)) { modes = [mode] }
    let override = args.choice("--classifier", of: Brains.classifiers)
    // Each mode's classifier by name: Jev only when asked for, or for normal
    // in a real run with its key, so a key in the environment doesn't make
    // the default run a live one. A real run asks for Jev by name: Jev alone
    // decides normal, which is what L5 checks. Without the key, normal's
    // table decides it.
    let envKey = Brains.environmentJevKey()
    if envKey == nil, override == "jev" { fail("Jev needs its API key in \(Brains.jevKeyVariable)") }
    let pick: @Sendable (Mode) -> String = { mode in override ?? (real && mode == .normal && envKey != nil ? "jev" : mode.rawValue) }
    if real, override == nil, envKey == nil, modes.contains(.normal) {
        print("normal: decided by its table; with Jev's API key in \(Brains.jevKeyVariable), Jev decides it")
    }
    let writer = args.choice("--writer", of: Brains.writers) ?? (real ? "apple" : "none")
    if writer == "apple", let why = AppleWriter.unavailableReason { fail("Apple's model can't run here: \(why)") }
    var list: [Scenario]
    do { list = try Scenario.load(directory: scenarios) } catch {
        fail("can't read the scenarios in \(scenarios.path): \((error as NSError).localizedDescription)")
    }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    guard !list.isEmpty else { fail("no scenarios in \(scenarios.path)") }
    guard let runs = Int(args["--runs"] ?? (real ? "3" : "1")), runs >= 1 else { fail("--runs is a count, 1 or more") }
    var runner = Eval(
        classifier: { mode in Brains.classifier(for: mode, override: pick(mode), key: { envKey }) },
        writer: { mode in Brains.writer(for: mode, override: writer) },
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
            for run in 1...runs {
                do { rs.append(try await runner.run(scenario, mode: mode, run: run)) } catch { fail("\(scenario.file): \(error)") }
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
    if let out = args["--json"] {
        do { try Eval.json(results).write(toFile: out, atomically: true, encoding: .utf8) }
        catch { fail("can't write \(out): \(error)") }
    }
    var summaryHolds = true
    if real {
        let summary = Eval.Summary(results.flatMap { $0.flatMap(\.brainPasses) })
        summary.lines.forEach { print($0) }
        summaryHolds = summary.holds
        // One verdict for both halves, so a report that held can't read as
        // a pass under failed scenarios.
        var failed: [String] = []
        if passed < results.count { failed.append("\(results.count - passed) of \(results.count) scenarios failed") }
        if !summaryHolds { failed.append("the report didn't hold") }
        print(failed.isEmpty ? "passed: every scenario, and the report; now read a sample of the passes (VERIFICATION.md L5)"
                             : "did NOT pass: " + failed.joined(separator: ", "))
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

func talk(_ raw: [String]) {
    let args = arguments("talk", raw, options: ["--socket"], flags: ["--yelled"], words: .max)
    guard let socket = args["--socket"] else { fail("boopdev talk: which app? pass --socket PATH") }
    let words = args.words.joined(separator: " ")
    let yelled = args.has("--yelled")
    guard !words.isEmpty || yelled else { fail("boopdev talk: what was said? give the words, or --yelled") }
    let line = (try? JSONSerialization.data(withJSONObject: ["dev": "talk", "words": words, "yelled": yelled] as [String: Any]))
        ?? Data()
    sendDev(line, to: socket)
    print("sent talk \"\(words)\"\(yelled ? " (yelled)" : "")")
}

func hooks(_ raw: [String]) {
    let args = arguments("hooks", raw, options: ["--home", "--hook"], words: 2)
    guard let action = args.words.first, ["status", "install", "remove"].contains(action) else {
        fail("boopdev hooks: status, install or remove?")
    }
    // Never the real HOME by default: tests use a temporary one.
    guard let home = args["--home"] else { fail("boopdev hooks: pass --home DIR") }
    let installer = HookInstaller(home: URL(fileURLWithPath: home), hookPath: args["--hook"] ?? builtHook.path)
    var agents = HookInstaller.Agent.allCases
    if args.words.count > 1 {
        guard let agent = HookInstaller.Agent(rawValue: args.words[1]) else { fail("boopdev hooks: the agent is claude or codex") }
        agents = [agent]
    }
    for agent in agents {
        do {
            switch action {
            case "install": try installer.install(agent)
            case "remove": try installer.remove(agent)
            default: break
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
case let command?:
    fail("boopdev: no command \(command)\n\(usage)")
}
