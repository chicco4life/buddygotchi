import BoopKit
import Foundation
import HookWire

// Developer CLI (VERIFICATION.md §2): replay, memory, voice, brain, talk and
// hooks, as `usage` describes.

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
           boopdev brain [--brain apple|rules] [--triggers DIR] [--memory DIR] [--steering FILE] [--out FILE] [--gap-min N] [--history N] [--print]
               Runs the real harness and brain on recorded triggers, each with a fresh copy of the sample
               memory, N minutes apart (default 3) under one history of the harness's limits, and reports
               refusals, valid shapes, dropped calls, speech, silence and latency (VERIFICATION.md L5).
           boopdev hooks status|install|remove [claude|codex] --home DIR [--hook PATH]
               The installer, against any HOME (tests use a temporary one). --hook defaults to the boop-hook
               next to boopdev.
           boopdev talk "<words>" --socket PATH
               Hands a push-to-talk transcript to a running headless app, as if heard on the Mac's mic.
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
    // A busy stretch: triggers in file order, `--gap-min` apart, sharing one
    // history of the harness's limits (HARNESS.md §5) and one conversation (§4).
    let gapMs = Int64((Double(option(args, "--gap-min") ?? "3") ?? 3) * 60_000)
    for i in triggers.indices { triggers[i].ts = Int64(i) * gapMs }
    let limits = ToolLimits()
    // `--history N`: at most N earlier exchanges (0 sends none, like v1's one-shot calls).
    let conversation = Conversation(maxExchanges: Int(option(args, "--history") ?? "") ?? 4)
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
                           home: home, debugLog: out, limits: limits, conversation: conversation, log: { logs.append($0) })
        }
        let r = await harness.respond(to: trigger)
        records.append(r)
        if args.contains("--print") {
            let said = trigger.words.map { " \"\($0)\"" } ?? ""
            let answer = r.dropped.map { "DROPPED \($0)" }
                ?? (r.ran.isEmpty ? "(quiet)" : r.ran.map { "\($0.call)" + ($0.outcome.isDone ? "" : " ✗") }.joined(separator: ", "))
            let limited = r.prompt.user.contains("\nsay limit: ") ? " [say limit]" : ""
            print("\(i + 1)\t\(r.latencyMs) ms\t\(trigger.line)\(said)\(limited) (history \(r.prompt.history.count))\n\t→ \(answer)")
        }
    }

    func percentile(_ values: [Int], _ p: Double) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
    }
    // Refusals (a guardrail declining to answer) are counted apart: Boop
    // keeps the rule reaction, as for any dropped answer (VERIFICATION.md L5).
    let answered = records.filter { !$0.refused }
    let valid = records.filter(\.validShape)
    func limited(_ c: (call: ToolCall, outcome: ActionOutcome)) -> Bool {
        if case .dropped(let why) = c.outcome { return why.hasPrefix(c.call.name + " limit: ") }
        return false
    }
    let calls = records.flatMap(\.ran).filter { !limited($0) }
    let dropped = calls.filter { !$0.outcome.isDone }
    print("brain \(brain.id), \(records.count) triggers \(gapMs / 60_000) min apart, log \(out.path)")
    print("refused: \(records.count - answered.count)/\(records.count)")
    for r in records where r.refused { print("  refused (\(r.trigger.kind.rawValue)): \(r.dropped ?? "")") }
    print("valid shape: \(valid.count)/\(answered.count) answers given")
    for r in answered where !r.validShape { print("  dropped answer (\(r.trigger.kind.rawValue)): \(r.dropped ?? "")") }
    print("silence: \(valid.filter(\.silent).count)/\(valid.count)")
    for kind in [Trigger.Kind.event, .tap, .talk] {
        let rs = valid.filter { $0.trigger.kind == kind }
        let spoke = rs.filter { $0.ran.contains { $0.call.name == "say" && $0.outcome.isDone } }
        let allowed = rs.filter { !$0.prompt.user.contains("\nsay limit: ") }
        print("spoke on \(kind.rawValue): \(spoke.count)/\(rs.count) (say allowed \(allowed.count))")
    }
    print("tool calls: \(calls.count), dropped by actions: \(dropped.count), past a limit: \(records.flatMap(\.ran).filter(limited).count)")
    let histories = records.filter(\.trigger.kind.converses).map(\.prompt.history.count)
    print("conversation: up to \(histories.max() ?? 0) earlier exchanges, \(conversation.restarts) restarts")
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
    let pass = valid.count == answered.count && dropRate < 0.05 && latencyOK
    print(pass ? "PASS (the sample review is separate)" : "FAIL")
    exit(pass ? 0 : 1)
}

func talk(_ args: [String]) {
    guard let socket = option(args, "--socket") else { fail(usage) }
    let words = args.enumerated().filter { i, a in !a.hasPrefix("--") && (i == 0 || args[i - 1] != "--socket") }
        .map(\.element).joined(separator: " ")
    guard !words.isEmpty else { fail(usage) }
    var data = (try? JSONSerialization.data(withJSONObject: ["dev": "talk", "words": words])) ?? Data()
    data.append(0x0A)
    guard HookSocket.send(data, to: socket, timeoutMs: 500) else { fail("no app answering on \(socket)") }
    print("sent talk \"\(words)\"")
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
case "memory":
    memory(Array(args.dropFirst()))
case "voice":
    voice(Array(args.dropFirst()))
case "brain":
    await brain(Array(args.dropFirst()))
case "talk":
    talk(Array(args.dropFirst()))
case "hooks":
    hooks(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
