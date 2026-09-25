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
           boopdev brain [--brain apple|rules] [--triggers DIR] [--memory DIR] [--steering FILE] [--out FILE] [--print]
               Runs the real harness and brain on recorded triggers, each with a fresh copy of the sample
               memory, and reports valid shapes, dropped calls, the silence rate and latency (VERIFICATION.md L5).
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

func brain(_ args: [String]) async {
    let fm = FileManager.default
    let setting = option(args, "--brain") ?? "apple"
    let triggersDir = option(args, "--triggers") ?? "app/Tests/Fixtures/triggers"
    let memoryDir = URL(fileURLWithPath: option(args, "--memory") ?? "app/Tests/Fixtures/memory")
    guard let steeringPath = option(args, "--steering") ?? findSteering(),
          let steering = try? String(contentsOfFile: steeringPath, encoding: .utf8)
    else { fail("can't find steering.md; pass --steering") }
    let brain: any Brain
    switch setting {
    case "apple":
        if let why = AppleBrain.unavailableReason { fail("Apple's model can't run here: \(why)") }
        brain = AppleBrain()
    case "rules": brain = RulesBrain()
    default: fail("brains: apple, rules")
    }

    var triggers: [Trigger] = []
    let files = ((try? fm.contentsOfDirectory(atPath: triggersDir)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted()
    for file in files {
        let text = (try? String(contentsOfFile: triggersDir + "/" + file, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let kind = (o["kind"] as? String).flatMap(Trigger.Kind.init(rawValue:)), let text = o["line"] as? String
            else { fail("bad trigger in \(file): \(line)") }
            triggers.append(Trigger(kind: kind, line: text, words: o["words"] as? String, ts: 0))
        }
    }
    guard !triggers.isEmpty else { fail("no triggers in \(triggersDir)") }

    let out = URL(fileURLWithPath: option(args, "--out") ?? "/tmp/boop-brain/\(setting).jsonl")
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.removeItem(at: out)
    let home = DispatchQueue(label: "boopdev.brain")
    var records: [Harness.Record] = []
    var logs: [String] = []
    for (i, trigger) in triggers.enumerated() {
        // A fresh copy of the sample memory for every trigger.
        let dir = fm.temporaryDirectory.appendingPathComponent("boop-brain-\(UUID().uuidString)")
        do { try fm.copyItem(at: memoryDir, to: dir) } catch { fail("can't copy \(memoryDir.path): \(error)") }
        defer { try? fm.removeItem(at: dir) }
        let harness: Harness = home.sync {
            let store = try! MemoryStore(directory: dir, steering: steering, log: { logs.append($0) })
            if trigger.kind == .reflect, let day = store.lastActiveDay {
                let next = LocalTime.day(day, plus: 1)
                store.apply(.newDay(date: next, firstSeen: "08:30", mood: "content"))
            }
            let context = ActionContext(send: { _ in }, today: { store.lastActiveDay ?? "2026-10-15" },
                                        log: { logs.append($0) })
            let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 0x7f3a)), memory: store)
            return Harness(brain: brain, tools: actions.map(Harness.Tool.init), memory: { store.promptMemory(for: $0.kind) },
                           home: home, debugLog: out, log: { logs.append($0) })
        }
        let r = await harness.respond(to: trigger)
        records.append(r)
        if args.contains("--print") {
            let said = trigger.words.map { " \"\($0)\"" } ?? ""
            let answer = r.dropped.map { "DROPPED \($0)" }
                ?? (r.ran.isEmpty ? "(quiet)" : r.ran.map { "\($0.call)" + ($0.outcome.isDone ? "" : " ✗") }.joined(separator: ", "))
            print("\(i + 1)\t\(r.latencyMs) ms\t\(trigger.line)\(said)\n\t→ \(answer)")
        }
    }

    func percentile(_ values: [Int], _ p: Double) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
    }
    let valid = records.filter(\.validShape)
    let calls = records.flatMap(\.ran)
    let dropped = calls.filter { !$0.outcome.isDone }
    print("brain \(brain.id), \(records.count) triggers, log \(out.path)")
    print("valid shape: \(valid.count)/\(records.count)")
    for r in records where !r.validShape { print("  dropped answer (\(r.trigger.kind.rawValue)): \(r.dropped ?? "")") }
    print("silence: \(valid.filter(\.silent).count)/\(valid.count)")
    print("tool calls: \(calls.count), dropped by actions: \(dropped.count)")
    for d in dropped {
        if case .dropped(let why) = d.outcome { print("  \(d.call): \(why)") }
    }
    var latencyOK = true
    for kind in [Trigger.Kind.event, .tap, .talk, .reflect] {
        let ms = records.filter { $0.trigger.kind == kind }.map(\.latencyMs)
        guard !ms.isEmpty else { continue }
        let p95 = percentile(ms, 0.95)
        if p95 >= kind.deadlineMs { latencyOK = false }
        print("latency \(kind.rawValue): n \(ms.count), p50 \(percentile(ms, 0.5)) ms, p95 \(p95) ms (deadline \(kind.deadlineMs) ms)")
    }
    for line in logs where line.contains("over budget") { print("  \(line)") }
    let dropRate = calls.isEmpty ? 0 : Double(dropped.count) / Double(calls.count)
    let pass = valid.count == records.count && dropRate < 0.05 && latencyOK
    print(pass ? "PASS (the sample review is separate)" : "FAIL")
    exit(pass ? 0 : 1)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "replay":
    replay(Array(args.dropFirst()))
case "memory":
    memory(Array(args.dropFirst()))
case "voice":
    voice(Array(args.dropFirst()))
case "brain":
    await brain(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
