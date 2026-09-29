import BoopDevKit
import BoopKit
import Foundation
import HookWire

// Developer CLI (VERIFICATION.md §2): replay, voice, eval, watch and hooks,
// as `usage` describes.

/// Each subcommand's usage, in the order `boopdev --help` lists them.
let usages: [(command: String, text: String)] = [
    ("replay", """
    boopdev replay <hooks.jsonl> [--agent claude|codex] [--gap-ms N] [--states]
        Runs recorded hook payloads through boop-hook's field picking, the adapter and the pipeline (the
        core and the view) on a virtual clock, and prints each raw event, what the core decides and the
        view events. {"wait_ms":N} and {"advance_ms":N} move the clock. --states prints only what goes to
        the device: each state and each rule moment.
    boopdev replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]
        Sends each payload through the real boop-hook binary to a running app's socket, in real time, and
        prints how long each boop-hook took: {"wait_ms":N} waits, and {"advance_ms":N} jumps a headless
        app's clock.
    """),
    ("voice", """
    boopdev voice <feeling|expression> [word] [--dialect HEX] [--seed N] [--count N] [--json]
        Prints Minion lines as the react action would build them: in a Voice feeling, or in the one a
        mood's face mumbles in (VOICE.md §4), so grumpy sounds annoyed.
    """),
    ("eval", """
    boopdev eval [--runs N] [--only TEXT] [--always] [--budget N | --no-budget] [--timeline] [--scenarios DIR] [--steering DIR]
    boopdev eval --list [--always] [--only TEXT] [--scenarios DIR]
        Runs the harness eval scenarios (plan/EVALS.md): hook-level steps on a virtual clock through a fresh
        pipeline, the real harness and actions, and Jev, each pass checked against what it should come to (the
        reaction, the word, how long the face holds and the mood), and each run against its whole-run
        checks. Needs Jev's key in BOOP_JEV_KEY and fails without it. --runs runs each scenario N times
        (default the scenario's own runs, else 3 for an always scenario and 1 for the rest); it passes only
        if every run does. Before asking Jev anything it counts the requests the runs will send (each run's
        passes with the scripted brain) and stops if that's over --budget (default 100); --no-budget is for
        the final pass (make eval). --always runs only the always scenarios, Boop's character. --timeline
        prints every pass of every run. --list prints each scenario's case, runs and requests, and runs
        nothing. A scenario with a known gap is reported GAP when it
        fails, and doesn't fail the eval. Every event, view event and pass goes to the run's own file in
        /tmp/boop-eval (boopdev watch FILE prints it). Exits 1 if any fails. The scenarios and steering
        default to the Boop repo's, found from the working directory or from boopdev's own place.
    """),
    ("watch", """
    boopdev watch [FILE] [--new]
        Follows debug mode's log (Boop --debug writes STATE-DIR/debug.jsonl; the default is the
        everyday app's) and prints each view event, pass and action readably, as Boop --debug does in its
        own terminal, waiting for FILE if it isn't there yet. The dashboard's lines (questions, sent,
        status) are skipped. --new skips what's already in the file.
    """),
    ("hooks", """
    boopdev hooks status|install|remove [claude|codex] --home DIR [--hook PATH]
        The installer, against any HOME (tests use a temporary one). --hook defaults to the boop-hook
        next to boopdev.
    """),
]

let version = "(boop \(BoopVersion.current))"
/// Indented under "usage:", as each command's own lines are under it.
func indented(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
}
let usage = "usage:\n" + usages.map { indented($0.text) }.joined(separator: "\n") + "\n"
    + "Each command prints its own usage with --help, and stops on a flag it doesn't take.\n" + version

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
    let args = arguments("replay", raw, options: ["--agent", "--gap-ms", "--socket"], flags: ["--states"], words: 1)
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
    let args = arguments("voice", raw, options: ["--dialect", "--seed", "--count"], flags: ["--json"], words: 2)
    let words = args.words
    let isMood = { (name: String) in MoodAction.moods.contains { $0.name == name } }
    guard let feeling = words.first.flatMap({ Feeling(rawValue: $0) ?? (isMood($0) ? Voice.feeling(forMood: $0) : nil) }) else {
        fail("feelings: " + Feeling.allCases.map(\.rawValue).joined(separator: ", ")
             + "; moods: " + MoodAction.moods.map(\.name).joined(separator: ", "))
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
        let line = v.line(feeling, word: word, seed: seed)
        print(args.has("--json") ? line.json : "\(seed)\t\(line.text)\t\(line.tune.rawValue) \(line.ms) ms")
    }
}

/// The Boop repo: the nearest folder with `plan/steering/guide.md` above
/// the working directory, or else above boopdev itself (`.build/debug`).
func findRepo() -> URL? {
    let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                  URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()]
    for start in starts {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("plan/steering/guide.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
    }
    return nil
}

/// How many Jev requests `boopdev eval` may send unless `--budget` or
/// `--no-budget` says (plan/EVALS.md §2): enough for a handful of
/// scenarios while developing, not the whole eval, which is the final pass.
let evalBudget = 100

func eval(_ raw: [String]) async {
    let args = arguments("eval", raw, options: ["--runs", "--only", "--budget", "--scenarios", "--steering"],
                         flags: ["--always", "--list", "--timeline", "--no-budget"])
    let repo = findRepo()
    func path(_ option: String, _ inRepo: String) -> URL {
        if let given = args[option] { return URL(fileURLWithPath: given) }
        guard let repo else { fail("boopdev eval: can't find the Boop repo; run it inside the repo, or pass --scenarios and --steering") }
        return repo.appendingPathComponent(inRepo)
    }
    var list: [Scenario]
    let scenarios = path("--scenarios", "internal/app/Evals/scenarios")
    do { list = try Scenario.load(directory: scenarios) } catch { fail("can't read the scenarios: \(error)") }
    if let only = args["--only"] {
        list = list.filter { $0.name.localizedCaseInsensitiveContains(only) || $0.file.contains(only) }
    }
    if args.has("--always") { list = list.filter(\.always) }
    guard !list.isEmpty else { fail("no scenarios in \(scenarios.path)") }
    let steering: Steering
    do { steering = try Steering(directory: path("--steering", "plan/steering")) } catch { fail("\(error)") }
    let given = args["--runs"].map { Int($0) }
    if let given, (given ?? 0) < 1 { fail("--runs is a count, 1 or more") }
    let budget = args["--budget"].map { Int($0) }
    if let budget, (budget ?? 0) < 1 { fail("--budget is a count of Jev requests, 1 or more") }
    if budget != nil, args.has("--no-budget") { fail("--budget or --no-budget, not both") }
    // What the eval will cost before it asks Jev anything (EVALS.md §2):
    // each scenario's passes with the scripted brain, times its runs.
    var plan: [(scenario: Scenario, runs: Int, requests: Int)] = []
    for scenario in list {
        let requests: Int
        do { requests = try await Eval.requests(scenario, steering: steering) } catch { fail("\(error)") }
        plan.append((scenario, given.flatMap { $0 } ?? Eval.runs(scenario), requests))
    }
    let total = plan.reduce(0) { $0 + $1.runs * $1.requests }
    if args.has("--list") {
        for p in plan {
            let s = p.scenario
            print("\(s.file)\(s.always ? "  [always]" : s.gap != nil ? "  [gap]" : "")  \(s.name)")
            print("    \(p.runs) run\(p.runs == 1 ? "" : "s") × about \(p.requests) requests")
            print("    \(s.story)")
            if let gap = s.gap { print("    gap: \(gap)") }
        }
        print("\(plan.count) scenario\(plan.count == 1 ? "" : "s"), about \(total) Jev requests")
        exit(0)
    }
    let limit = args.has("--no-budget") ? Int.max : budget.flatMap { $0 } ?? evalBudget
    if total > limit {
        let costliest = plan.sorted { $0.runs * $0.requests > $1.runs * $1.requests }.prefix(5)
            .map { "  \($0.scenario.file): \($0.runs) × \($0.requests)" }
        fail((["boopdev eval: about \(total) Jev requests, over the budget of \(limit); narrow it with --only or --runs 1, "
               + "raise --budget, or pass --no-budget for the final pass. The costliest:"] + costliest).joined(separator: "\n"))
    }
    guard let key = JevKey.environment() else {
        fail("boopdev eval asks Jev, and needs its API key in \(JevKey.variable)")
    }
    let brain = JevBrain(key: key)
    var runner = Eval(brain: brain, steering: steering)
    let log = evalDebugLog()
    DebugLog.start(log)
    runner.debugLog = log
    print("\(plan.count) scenario\(plan.count == 1 ? "" : "s"), about \(total) Jev requests")
    print("every event, view event and pass goes to \(log.path)")
    var results: [[Eval.Result]] = []
    var gapsFailed = 0
    var failed = false
    for (scenario, runs, _) in plan {
        var rs: [Eval.Result] = []
        for _ in 1...runs {
            do { rs.append(try await runner.run(scenario)) } catch { fail("\(error)") }
        }
        results.append(rs)
        if !rs.allSatisfy(\.passed) {
            if scenario.gap != nil { gapsFailed += 1 } else { failed = true }
        }
        for line in Eval.report(rs, story: scenario.story, gap: scenario.gap) { print(line) }
        if args.has("--timeline") {
            for (i, r) in rs.enumerated() {
                print("  run \(i + 1)\(r.passed ? "" : " (failed)"):")
                for line in Eval.timeline(r) { print(line) }
            }
        }
    }
    print(Eval.summary(results, gaps: gapsFailed) + " in every run with \(brain.id)")
    let latencies = results.flatMap { $0.flatMap { $0.checks.map(\.latencyMs) } }.sorted()
    if !latencies.isEmpty {
        print("latency: median \(latencies[latencies.count / 2]) ms, slowest \(latencies.last!) ms (deadline \(Harness.deadlineMs) ms)")
    }
    print("to read them: boopdev watch \(log.path)")
    exit(failed ? 1 : 0)
}

/// A file of the run's own (harness/HARNESS.md §9), so runs side by side
/// don't write over each other. Runs over a day old are cleared away.
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

/// `boopdev watch [FILE]`: follows debug mode's log (harness/HARNESS.md §9)
/// and prints each line as it lands, as `Boop --debug` does. The app
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
            if let text = printer.readable(line) { print(text) }
        }
    }
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
case "hooks":
    hooks(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
case let command?:
    fail("boopdev: no command \(command)\n\(usage)")
}
