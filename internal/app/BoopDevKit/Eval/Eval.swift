import BoopKit
import Foundation

/// The harness evals (plan/EVALS.md): scenarios of hook-level steps on a
/// virtual clock, run through a fresh core, the real harness and the real
/// actions, each pass checked against what Jev should answer. They ask Jev,
/// so they need its key; `boopdev eval` fails without it. Tests run the same
/// runner with a scripted brain.
public struct Scenario: Sendable {
    /// One step: what happens, and what the pass it wakes should lead to.
    public struct Step: Sendable {
        /// `turn started`, `command`, `turn finished`, `turn failed`,
        /// `pokes` or `wait`.
        public var event: String
        /// Virtual time since the scenario started, in ms.
        public var atMs: Int64
        /// The thread's workspace; it's always Claude's session in `landing`.
        public var workspace: String?
        /// A command: its topic, and whether it failed.
        public var topic: String?
        public var failed: Bool?
        /// A failed turn's error class.
        public var error: String?
        /// What the pass should come to; nil checks nothing. A step with an
        /// expectation must wake the brain.
        public var expect: Expectation?
    }

    /// What a pass should come to: each a set of acceptable values, `none`
    /// included where staying quiet or no word is fine.
    public struct Expectation: Sendable, Equatable {
        /// Jev's `react` pick: `none` or a feeling.
        public var react: Set<String>?
        /// The word the mumble used, or `none`.
        public var word: Set<String>?
        /// The mood after the pass.
        public var mood: Set<String>?

        public init(react: Set<String>? = nil, word: Set<String>? = nil, mood: Set<String>? = nil) {
            self.react = react
            self.word = word
            self.mood = mood
        }
    }

    public var name: String
    public var why: String
    public var personality: Personality
    public var steps: [Step]
    public var file: String

    public static let events = ["turn started", "command", "turn finished", "turn failed", "pokes", "wait"]

    /// Reads one scenario file. Throws with the file and step on a bad one.
    public init(file: URL) throws {
        self.file = file.lastPathComponent
        func bad(_ why: String) -> Error { EvalError("\(file.lastPathComponent): \(why)") }
        guard let o = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else { throw bad("not a JSON object") }
        guard let name = o["name"] as? String, let why = o["why"] as? String, let raw = o["steps"] as? [[String: Any]]
        else { throw bad("needs name, why and steps") }
        self.name = name
        self.why = why
        personality = try (o["personality"] as? String).map {
            guard let p = Personality(rawValue: $0) else { throw bad("unknown personality \($0)") }
            return p
        } ?? .boop
        steps = try raw.enumerated().map { i, s in
            func badStep(_ why: String) -> Error { bad("step \(i + 1): \(why)") }
            guard let event = s["event"] as? String, Scenario.events.contains(event) else {
                throw badStep("event is one of \(Scenario.events.joined(separator: ", "))")
            }
            guard let at = s["at"] as? String, let atMs = Scenario.ms(at) else { throw badStep("at is like 0m, 90s or 2m30s") }
            var step = Step(event: event, atMs: atMs)
            step.workspace = s["workspace"] as? String
            step.topic = s["topic"] as? String
            step.failed = s["failed"] as? Bool
            step.error = s["error"] as? String
            if let e = s["expect"] as? [String: Any] {
                func set(_ key: String) throws -> Set<String>? {
                    guard let v = e[key] else { return nil }
                    guard let text = v as? String else { throw badStep("expect.\(key) is like \"proud|excited\"") }
                    return Set(text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                }
                let unknown = Set(e.keys).subtracting(["react", "word", "mood"])
                guard unknown.isEmpty else { throw badStep("expect has only react, word and mood") }
                step.expect = Expectation(react: try set("react"), word: try set("word"), mood: try set("mood"))
            }
            return step
        }
        guard steps.contains(where: { $0.expect != nil }) else { throw bad("expects nothing") }
    }

    /// `2m30s`, `90s`, `5m`, `1h`.
    static func ms(_ text: String) -> Int64? {
        var total: Int64 = 0
        var number = ""
        for c in text {
            if c.isNumber { number.append(c); continue }
            guard let n = Int64(number) else { return nil }
            switch c {
            case "h": total += n * 3_600_000
            case "m": total += n * 60_000
            case "s": total += n * 1000
            default: return nil
            }
            number = ""
        }
        return number.isEmpty ? total : nil
    }

    public static func load(directory: URL) throws -> [Scenario] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(Scenario.init(file:))
    }
}

public struct EvalError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Runs scenarios (plan/EVALS.md §2).
public struct Eval {
    /// What one checked step came to.
    public struct Check: Sendable {
        public var step: Int
        public var line: String
        public var expected: Scenario.Expectation
        /// What happened: the react pick, the word used, the mood after.
        public var react: String?
        public var word: String?
        public var mood: String
        public var dropped: String?
        public var latencyMs: Int

        public var passed: Bool {
            guard dropped == nil else { return false }
            if let r = expected.react, !r.contains(react ?? "none") { return false }
            if let w = expected.word, !w.contains(word ?? "none") { return false }
            if let m = expected.mood, !m.contains(mood) { return false }
            return true
        }

        public var summary: String {
            let want = [expected.react.map { "react \($0.sorted().joined(separator: "|"))" },
                        expected.word.map { "word \($0.sorted().joined(separator: "|"))" },
                        expected.mood.map { "mood \($0.sorted().joined(separator: "|"))" }].compactMap { $0 }
            let got = dropped.map { "dropped: \($0)" } ?? "react \(react ?? "none"), word \(word ?? "none"), mood \(mood)"
            return "  step \(step): \(line)\n    wanted \(want.joined(separator: ", ")); got \(got)"
        }
    }

    public struct Result: Sendable {
        public var scenario: String
        public var file: String
        public var checks: [Check]
        public var passed: Bool { checks.allSatisfy(\.passed) }
    }

    let brain: any Brain
    let steering: Steering
    /// Every entry of every run, for `boopdev watch`.
    public var debugLog: URL?

    public init(brain: any Brain, steering: Steering) {
        self.brain = brain
        self.steering = steering
    }

    /// One run of a scenario, from a fresh core, transcript and mood.
    public func run(_ scenario: Scenario) async throws -> Result {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-eval-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let start = Replay.defaultStart
        let clock = VirtualClock(start)
        let rules = steering.personality(scenario.personality).rules
        let core = Core(config: .init(rules: rules, time: time, seed: 1), lastActiveDay: time.day(start))
        core.setWallClock(start, at: start)
        let mood = MoodStore(stateDir: dir)
        let home = DispatchQueue(label: "boop.eval")
        // No device: a reaction's moment goes nowhere and counts as played
        // at once, so HISTORY reads as the app's does once it has.
        let actions: [any Action] = [
            MoodAction(store: mood),
            ReactAction(voice: Voice(dialect: Dialect(seed: 1)), queue: { _, pending in pending.finish(.done) },
                        blocked: { core.mumbleBlock }),
        ]
        let steering = self.steering
        let harness = Harness(brain: brain, actions: actions, parts: { entry in
            Runtime.stateParts(for: entry, steering: steering, personality: scenario.personality, mood: mood.current,
                               core: core, time: time, now: clock.now, wall: clock.now)
        }, home: home, clock: { clock.now }, debugLog: debugLog)

        var checks: [Check] = []
        for (i, step) in scenario.steps.enumerated() {
            // Time passes a second at a time, as the app ticks.
            var events: [Event] = []
            while clock.now < start + step.atMs {
                clock.now = min(start + step.atMs, clock.now + 1000)
                events += Eval.events(core.tick(at: clock.now))
            }
            events += Eval.events(Eval.feed(step, core, at: clock.now))
            var last: Harness.Record?
            for event in events {
                if let record = await harness.respond(to: event) { last = record }
            }
            guard let expect = step.expect else { continue }
            guard let record = last else {
                throw EvalError("\(scenario.file) step \(i + 1): expects a pass, but nothing woke the brain")
            }
            let react = record.pass.answers["react"]?.choice
            let ran = record.actions.contains { $0.name == "react" && $0.result.ok }
            checks.append(Check(step: i + 1, line: record.event.line, expected: expect, react: react,
                                word: ran ? ReactAction.word(record.pass.answers) : nil, mood: mood.current,
                                dropped: record.pass.dropped, latencyMs: record.pass.latencyMs))
        }
        return Result(scenario: scenario.name, file: scenario.file, checks: checks)
    }

    static func events(_ fx: [CoreEffect]) -> [Event] {
        fx.compactMap { if case .event(let e) = $0 { return e } else { return nil } }
    }

    /// A step as it reaches the core: the hook events or device input it
    /// stands for, in Claude's session `s1` in `landing`.
    static func feed(_ step: Scenario.Step, _ core: Core, at now: Int64) -> [CoreEffect] {
        func hook(_ kind: BoopEvent.Kind, _ detail: BoopEvent.Detail = .init()) -> [CoreEffect] {
            core.handle(BoopEvent(agent: .claudeCode, session: "s1", project: "landing", workspace: step.workspace,
                                  event: kind, detail: detail, ts: now))
        }
        switch step.event {
        case "turn started": return hook(.turnStart)
        case "turn finished": return hook(.turnEnd)
        case "turn failed": return hook(.turnFailed, .init(error: step.error ?? "api_error"))
        case "command":
            var fx = hook(.activity, .init(tool: "Bash", topic: step.topic))
            var done = BoopEvent.Detail(tool: "Bash", topic: step.topic, failed: step.failed ?? false,
                                        toolError: step.failed == true ? "exit_code" : nil)
            done.done = true
            fx += hook(.activity, done)
            return fx
        case "pokes": return (0..<4).flatMap { _ in core.input(.tap, at: now) }
        default: return []  // wait
        }
    }

    /// One scenario's runs, readably: its verdict, and each failing step
    /// once.
    public static func report(_ runs: [Result]) -> [String] {
        guard let first = runs.first else { return [] }
        let passed = runs.filter(\.passed).count
        let tally = runs.count > 1 ? "  (\(passed)/\(runs.count) runs)" : ""
        var lines = [(passed == runs.count ? "pass  " : "FAIL  ") + "\(first.file)  \(first.scenario)\(tally)"]
        var seen: Set<String> = []
        for r in runs { for c in r.checks where !c.passed && seen.insert(c.summary).inserted { lines.append(c.summary) } }
        return lines
    }

    /// How many scenarios passed in every run: `7/10 passed`.
    public static func summary(_ results: [[Result]]) -> String {
        "\(results.filter { $0.allSatisfy(\.passed) }.count)/\(results.count) passed"
    }
}

/// The eval's clock, moved step by step.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int64
    init(_ ms: Int64) { self.ms = ms }
    var now: Int64 {
        get { lock.withLock { ms } }
        set { lock.withLock { ms = newValue } }
    }
}
