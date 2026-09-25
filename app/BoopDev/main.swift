import BoopKit
import Foundation

// Developer CLI (VERIFICATION.md §2). Subcommands arrive with the milestones
// that need them: replay (A1), memory (A2), brain (A3), talk (A4).

let usage = """
    usage: boopdev replay <hooks.jsonl> [--agent claude|codex] [--gap-ms N] [--start MS] [--tz ZONE] [--new-day] [--states]
               Runs recorded hook payloads through boop-hook's field picking, the adapter and the core,
               on a virtual clock, and prints what the core decides. A line {"wait_ms":N} moves the clock.
           boopdev replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]
               Sends each payload through the real boop-hook binary to a running app's socket, in real time.
           boopdev memory --state-dir DIR
               Prints long-term.md and short-term.md as the memory store reads them, and the history snapshots.
           boopdev voice <feeling> [word] [--dialect HEX] [--seed N] [--count N] [--json] [--why]
               Prints Minion lines as the say action would build them.
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
/// when each was sent so the caller can measure latency.
func replayLive(_ steps: [Replay.Step], agent: String, gapMs: Int64, socket: String) {
    let hook = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("boop-hook")
    guard FileManager.default.isExecutableFile(atPath: hook.path) else { fail("no boop-hook next to boopdev; run make build") }
    var environment = ProcessInfo.processInfo.environment
    environment["BOOP_SOCKET"] = socket
    for step in steps {
        switch step {
        case .wait(let ms):
            usleep(useconds_t(ms * 1000))
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

func memory(_ args: [String]) {
    guard let dir = option(args, "--state-dir") else { fail(usage) }
    let store: MemoryStore
    do {
        store = try MemoryStore(directory: URL(fileURLWithPath: dir), steering: "", log: { print("# \($0)") })
    } catch {
        fail("can't open \(dir): \(error)")
    }
    print("=== long-term.md ===")
    print(store.isSetUp ? store.longTermText : "(not set up)")
    print("=== short-term.md ===")
    print(store.shortTerm == nil ? "(none yet)" : store.shortTermText)
    let history = URL(fileURLWithPath: dir).appendingPathComponent(MemoryStore.historyDir)
    let days = ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []).sorted()
    print("=== history ===")
    print(days.isEmpty ? "(none)" : days.joined(separator: "\n"))
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

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "replay":
    replay(Array(args.dropFirst()))
case "memory":
    memory(Array(args.dropFirst()))
case "voice":
    voice(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
