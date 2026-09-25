import BoopKit
import Foundation
import HookWire

// Developer CLI (VERIFICATION.md §2). Subcommands arrive with the milestones
// that need them: replay (A1), memory (A2), brain (A3), talk (A4).

let usage = """
    usage: boopdev replay <hooks.jsonl> [--agent claude|codex] [--gap-ms N] [--start MS] [--tz ZONE] [--new-day] [--states]
               Runs recorded hook payloads through boop-hook's field picking, the adapter and the core,
               with a virtual clock, and prints what the core decides. A line {"wait_ms":N} moves the clock.
           boopdev replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]
               Sends each payload through the real boop-hook binary to a running app's socket.
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

/// Payload lines, and `wait_ms` markers.
enum Step {
    case payload(Data)
    case wait(Int64)
}

func readSteps(_ path: String) -> [Step] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("can't read \(path)") }
    // A .json file is one payload, possibly pretty-printed.
    if path.hasSuffix(".json") { return [.payload(Data(text.utf8))] }
    return text.split(separator: "\n").compactMap { raw in
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
           let wait = object["wait_ms"] as? NSNumber, object["hook_event_name"] == nil {
            return .wait(wait.int64Value)
        }
        return .payload(Data(line.utf8))
    }
}

func describe(_ effect: CoreEffect) -> String {
    switch effect {
    case .state(let s): "state " + s.jsonLine
    case .moment(let anim, let size): "moment \(anim) \(size)"
    case .mumble(let feeling, let word): "mumble \(feeling)" + (word.map { " \($0)" } ?? "")
    case .trigger(let t): "trigger \(t.kind.rawValue): \(t.line)"
    case .happened(let line): "happened \(line)"
    case .growth(let g): "growth xp \(g.xp) level \(g.level) fed \(g.lastFed)"
    case .newDay(let date, let firstSeen, let mood): "new-day \(date) first seen \(firstSeen) mood \(mood)"
    case .listen(let on): "listen \(on)"
    }
}

func replay(_ args: [String]) {
    guard let path = args.first(where: { !$0.hasPrefix("--") }) else { fail(usage) }
    let agent = option(args, "--agent") ?? (path.contains("/codex/") ? "codex" : "claude")
    let gap = Int64(option(args, "--gap-ms") ?? "1000") ?? 1000
    let steps = readSteps(path)

    if let socket = option(args, "--socket") {
        replayLive(steps, agent: agent, gapMs: gap, socket: socket)
        return
    }

    let zone = option(args, "--tz").flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
    // 2026-10-14 14:00 UTC unless told otherwise, so the output is repeatable.
    var now = Int64(option(args, "--start") ?? "1791986400000") ?? 1_791_986_400_000
    let start = now
    let time = LocalTime(timeZone: zone)
    let today = time.day(now)
    let core = Core(config: .init(name: "Pip", time: time), growth: Growth(hatched: today),
                    lastActiveDay: args.contains("--new-day") ? nil : today, now: now)
    let statesOnly = args.contains("--states")
    var projects: [String: String] = [:]

    func emit(_ effects: [CoreEffect], at ms: Int64) {
        for effect in effects {
            if statesOnly, case .state = effect {} else if statesOnly { continue }
            print("+\(String(format: "%6.1f", Double(ms - start) / 1000))s \(describe(effect))")
        }
    }

    for step in steps {
        switch step {
        case .wait(let ms):
            // Run the timers through the wait, a second at a time.
            let end = now + ms
            while now < end {
                now = min(end, now + 1000)
                emit(core.tick(at: now), at: now)
            }
        case .payload(let data):
            guard let line = HookLine.extract(agent: agent, payload: data, ts: now) else {
                print("# skipped: not a hook payload")
                continue
            }
            let key = line.agent + "/" + line.session
            guard let event = Adapter.event(from: line, knownProject: projects[key]) else {
                print("# ignored hook \(line.hook)")
                continue
            }
            projects[key] = event.project
            print("event \(event.jsonLine)")
            emit(core.handle(event), at: now)
            let end = now + gap
            while now < end {
                now = min(end, now + 1000)
                emit(core.tick(at: now), at: now)
            }
        }
    }
}

/// Sends payloads through the real `boop-hook`, as agents would.
func replayLive(_ steps: [Step], agent: String, gapMs: Int64, socket: String) {
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
            let hookName = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hook_event_name"] as? String
            print("sent \(hookName ?? "?") at \(Int64(sent.timeIntervalSince1970 * 1000)) hook \(ms) ms exit \(process.terminationStatus)")
            usleep(useconds_t(gapMs * 1000))
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "replay":
    replay(Array(args.dropFirst()))
case nil, "-h", "--help", "help":
    print(usage)
default:
    fail(usage)
}
