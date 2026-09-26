import Foundation

/// The harness eval suite (plan/EVALS.md): scenarios of agent events, taps
/// and talk on a virtual clock, run through a fresh core, the real two-stage
/// harness and the real actions, checked against what the harness should do.
/// Used by `boopdev eval` and by tests.
///
/// A scenario is steps of an event and what it should lead to. A step's
/// `expect` is every harness pass from its event up to the next step's
/// event, so an empty list means no input reached the harness. Only the
/// harness's passes are compared; the core's own rule reactions aren't.
/// Each expected pass lists the values that fit (`Expectation`), so the
/// same scenario holds for real models as for the rules.
public struct Scenario: Sendable {
    /// What happens at a step, as it reaches the core.
    public struct Event: Sendable {
        /// `turn started`, `command`, `turn finished`, `turn failed`, `tap`,
        /// `talk` or `wait`.
        public var event: String
        /// Virtual time since the scenario started, in ms.
        public var atMs: Int64
        public var agent: Agent
        public var project: String
        public var session: String
        public var error: String?
        public var words: String?
        /// Talk: you yelled it.
        public var yelled = false
        /// A command: its topic (`tests`, `build`, `deploy`), and whether it failed.
        public var topic: String?
        public var failed = false
    }

    /// What Stage 1 answers for the step's inputs instead of the classifier
    /// in use: calls with their decided arguments, an error, a refusal or
    /// lateness.
    public enum ScriptedClassifier: Sendable {
        case calls([ToolCall])
        case error(String)
        case refused
        case late
    }

    /// What Stage 2 answers instead of the writer in use: values by slot
    /// (`react.word`), an error, a refusal or lateness.
    public enum ScriptedWriter: Sendable {
        case values([String: String])
        case error(String)
        case refused
        case late
    }

    public struct Step: Sendable {
        public var event: Event
        public var classifier: ScriptedClassifier?
        public var writer: ScriptedWriter?
        public var expect: [Expectation]
    }

    public var name: String
    public var why: String
    public var steps: [Step]
    /// Where it came from, for reports.
    public var file: String

    public static let events = ["turn started", "command", "turn finished", "turn failed", "tap", "talk", "wait"]

    /// Reads one scenario file. Throws with the file and step on a bad one.
    public init(file: URL) throws {
        self.file = file.lastPathComponent
        func bad(_ why: String) -> Error { EvalError("\(file.lastPathComponent): \(why)") }
        guard let o = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              let name = o["name"] as? String, let steps = o["steps"] as? [[String: Any]]
        else { throw bad("needs a name and a steps list") }
        self.name = name
        why = o["why"] as? String ?? ""
        self.steps = []
        var last: Int64 = -1
        for (i, s) in steps.enumerated() {
            let n = "step \(i + 1)"
            guard let input = s["input"] as? [String: Any], let event = input["event"] as? String,
                  Scenario.events.contains(event)
            else { throw bad("\(n): input.event must be one of \(Scenario.events.joined(separator: ", "))") }
            guard let at = (input["at"] as? String).flatMap(Scenario.ms) else { throw bad("\(n): input.at like \"12m\"") }
            guard at > last else { throw bad("\(n): at must be later than the step before") }
            last = at
            guard let lines = s["expect"] as? [String] else { throw bad("\(n): expect must be a list (empty for none)") }
            let expect = try lines.map { line in
                do { return try Expectation(line) } catch { throw bad("\(n): \(error)") }
            }
            let agentName = input["agent"] as? String ?? "claude"
            guard let agent = Agent(hookName: agentName) else { throw bad("\(n): unknown agent \(agentName)") }
            let project = input["project"] as? String ?? "jetpack"
            if event == "talk", input["words"] as? String == nil { throw bad("\(n): talk needs words") }
            if event == "command", input["topic"] as? String == nil { throw bad("\(n): a command needs a topic") }
            self.steps.append(Step(
                event: Event(event: event, atMs: at, agent: agent, project: project,
                             session: input["session"] as? String ?? "\(agent.short)-\(project)",
                             error: input["error"] as? String, words: input["words"] as? String,
                             yelled: input["yelled"] as? Bool ?? false, topic: input["topic"] as? String,
                             failed: input["failed"] as? Bool ?? false),
                classifier: try Scenario.classifier(s["classifier"], bad: { bad("\(n): \($0)") }),
                writer: try Scenario.writer(s["writer"], bad: { bad("\(n): \($0)") }),
                expect: expect))
        }
        if self.steps.isEmpty { throw bad("no steps") }
    }

    static func classifier(_ value: Any?, bad: (String) -> Error) throws -> ScriptedClassifier? {
        guard let value else { return nil }
        if let calls = (value as? [String: Any])?["calls"] as? [[String: Any]] {
            return .calls(try calls.map { call in
                guard let name = call["tool"] as? String else { throw bad("a classifier call needs a tool") }
                var arguments: [String: ToolValue] = [:]
                for (key, v) in call where key != "tool" {
                    if let s = v as? String {
                        arguments[key] = .string(s)
                    } else if let n = v as? Int {
                        arguments[key] = .number(n)
                    } else {
                        throw bad("\(name).\(key) must be text or a number")
                    }
                }
                return ToolCall(name, arguments)
            })
        }
        if let error = (value as? [String: Any])?["error"] as? String { return .error(error) }
        if value as? String == "refused" { return .refused }
        if value as? String == "late" { return .late }
        throw bad("classifier is {\"calls\":[…]}, {\"error\":\"…\"}, \"refused\" or \"late\"")
    }

    static func writer(_ value: Any?, bad: (String) -> Error) throws -> ScriptedWriter? {
        guard let value else { return nil }
        if let error = (value as? [String: Any])?["error"] as? String { return .error(error) }
        if let values = value as? [String: String] { return .values(values) }
        if value as? String == "refused" { return .refused }
        if value as? String == "late" { return .late }
        throw bad("writer is {\"react.word\":\"…\"}, {\"error\":\"…\"}, \"refused\" or \"late\"")
    }

    /// `500ms`, `90s`, `12m`, `2h` → ms.
    static func ms(_ text: String) -> Int64? {
        if text.hasSuffix("ms") { return Int64(text.dropLast(2)).flatMap { $0 >= 0 ? $0 : nil } }
        guard let unit = text.last, let n = Int64(text.dropLast()), n >= 0 else { return nil }
        switch unit {
        case "s": return n * 1000
        case "m": return n * 60_000
        case "h": return n * 3_600_000
        default: return nil
        }
    }

    /// Every `.json` file in a directory, sorted by name.
    public static func load(directory: URL) throws -> [Scenario] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(Scenario.init(file:))
    }
}

public struct EvalError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Runs scenarios. Deterministic with the default brains (the rules
/// classifier, no writer): a virtual clock in UTC, a fixed dialect seed, a
/// fresh copy of the sample memory for every scenario. With a model, run
/// each scenario a few times (`boopdev eval --runs`).
public struct Eval: Sendable {
    public struct StepResult: Sendable {
        public var event: Scenario.Event
        public var expect: [Expectation]
        /// Each pass as `describe` writes it.
        public var actual: [String]
        /// How Stage 1 got to each pass: the rule that matched, Jev's answers.
        public var evidence: [String?]
        public var passed: Bool
    }

    public struct Result: Sendable {
        public var scenario: Scenario
        public var steps: [StepResult]
        public var passed: Bool { steps.allSatisfy(\.passed) }
    }

    public var classifier: any Classifier
    public var writer: any Writer
    public var steering: String
    /// The sample memory copied for each scenario.
    public var memory: URL
    /// 2026-10-14 14:00 UTC, as `boopdev replay` starts.
    public var start: Int64 = Replay.defaultStart
    public var time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    public init(classifier: any Classifier = RulesClassifier(), writer: any Writer = NoWriter(), steering: String,
                memory: URL) {
        self.classifier = classifier
        self.writer = writer
        self.steering = steering
        self.memory = memory
    }

    public func run(_ scenario: Scenario) async throws -> Result {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("boop-eval-\(UUID().uuidString)")
        try fm.copyItem(at: memory, to: dir)
        defer { try? fm.removeItem(at: dir) }

        let home = DispatchQueue(label: "boop.eval")
        let script = Script()
        let clock = Clock(start)
        let (core, harness, pending, definitions): (Core, Harness, Pending, [ToolDefinition]) = try home.sync {
            let store = try MemoryStore(directory: dir, steering: steering)
            guard let longTerm = store.longTerm else { throw EvalError("\(memory.path) has no long-term.md") }
            let core = Core(config: .init(name: longTerm.name, time: time, seed: 1),
                            lastActiveDay: store.lastActiveDay)
            let pending = Pending(store: store)
            let context = ActionContext(
                send: { _ in },
                mumblesAllowed: { core.canMumble(at: clock.now) },
                setQuiet: { pending.effects += core.setQuiet(minutes: $0, at: clock.now) },
                quietAsked: { core.quietAsked }, today: { time.day(clock.now) })
            let actions = Actions.all(context: context, voice: Voice(dialect: Dialect(seed: longTerm.seed)), memory: store)
            let harness = Harness(classifier: ScriptedClassifier(base: classifier, script: script),
                                  writer: ScriptedWriter(base: writer, script: script),
                                  tools: actions.map(Harness.Tool.init),
                                  memory: { store.promptMemory(for: $0.kind) }, home: home)
            return (core, harness, pending, actions.map(\.definition))
        }

        /// Carries out effects as the app does, and runs each input through
        /// the harness in turn; returns what each pass did.
        func carryOut(_ effects: [CoreEffect]) async -> [Harness.Record] {
            var out: [Harness.Record] = []
            var queue = effects
            while !queue.isEmpty {
                let effect = queue.removeFirst()
                switch effect {
                case .input(let input):
                    out.append(await harness.respond(to: input))
                    queue += home.sync { defer { pending.effects = [] }; return pending.effects }
                case .aside(let line):
                    home.sync { harness.note(line, at: clock.now) }
                case .happened, .newDay:
                    home.sync { pending.store.apply(effect) }
                case .state, .moment, .mumble, .listen, .endListening:
                    break
                }
            }
            return out
        }

        /// A step's window of passes against what it expects. Something
        /// writes for the step unless the writer is none and nothing's scripted.
        let noWriter = writer is NoWriter
        func result(_ step: Scenario.Step, _ records: [Harness.Record]) -> StepResult {
            let writing = !noWriter || step.writer != nil
            let passed = records.count == step.expect.count
                && zip(step.expect, records).allSatisfy { $0.matches($1, writing: writing, definitions: definitions) }
            return StepResult(event: step.event, expect: step.expect, actual: records.map(Eval.describe),
                              evidence: records.map(\.evidence), passed: passed)
        }

        var results: [StepResult] = []
        var records: [Harness.Record] = []
        home.sync { _ = core.tick(at: start) }
        for (i, step) in scenario.steps.enumerated() {
            // Time passes up to this event, a second at a time, as the app
            // ticks the core; what that releases belongs to the step before.
            let at = start + step.event.atMs
            while clock.now < at {
                clock.now = min(at, clock.now + 1000)
                records += await carryOut(home.sync { core.tick(at: clock.now) })
            }
            if i > 0 { results.append(result(scenario.steps[i - 1], records)) }
            records = []
            script.set(step.classifier, step.writer)
            let effects: [CoreEffect] = home.sync { Eval.apply(step.event, to: core, at: clock.now) }
            records += await carryOut(effects)
        }
        // The last step's window: a few seconds more, so a held input (a
        // burst's merge window) comes out.
        let end = clock.now + 5000
        while clock.now < end {
            clock.now += 1000
            records += await carryOut(home.sync { core.tick(at: clock.now) })
        }
        results.append(result(scenario.steps[scenario.steps.count - 1], records))
        return Result(scenario: scenario, steps: results)
    }

    static func apply(_ step: Scenario.Event, to core: Core, at now: Int64) -> [CoreEffect] {
        func event(_ kind: BoopEvent.Kind) -> [CoreEffect] {
            core.handle(BoopEvent(agent: step.agent, session: step.session, project: step.project, event: kind,
                                  detail: .init(error: step.error), ts: now))
        }
        switch step.event {
        case "turn started": return event(.turnStart)
        case "command":
            // A shell command finished, as Claude's PostToolUse or
            // PostToolUseFailure reports it (ADAPTERS.md §3).
            return core.handle(BoopEvent(agent: step.agent, session: step.session, project: step.project,
                                         event: .activity, detail: .init(tool: "Bash", topic: step.topic,
                                                                         failed: step.failed), ts: now))
        case "turn finished": return event(.turnEnd)
        case "turn failed": return event(.turnFailed)
        case "tap": return core.input(Core.DeviceInput.tap, at: now)
        case "talk": return core.talk(step.words ?? "", yelled: step.yelled, at: now)
        default: return core.tick(at: now)
        }
    }

    /// One pass as the scenarios write it (plan/EVALS.md §3):
    /// `agent finished → react(feeling: proud, voice: mumble)`,
    /// `agent started → nothing`, `you said → remember(where: today) dropped (unwritten)`,
    /// `agent finished → dropped (off menu)`. A writer that failed adds
    /// ` · writer failed (error)`.
    public static func describe(_ record: Harness.Record) -> String {
        let kind = record.input.kind.rawValue
        if let dropped = record.dropped { return "\(kind) → dropped (\(Eval.why(dropped)))" }
        var line = kind + " → "
        if record.ran.isEmpty {
            line += "nothing"
        } else {
            line += record.ran.map { r -> String in
                switch r.outcome {
                case .done: return r.call.plain
                case .dropped(let reason):
                    return "\(r.call.plain) dropped (\(reason == "nothing was written" ? "unwritten" : "action"))"
                }
            }.joined(separator: ", ")
        }
        if let failed = record.writeFailed { line += " · writer failed (\(why(failed)))" }
        return line
    }

    /// Why a pass or a write came to nothing, as a scenario names it.
    static func why(_ reason: String) -> String {
        reason.hasPrefix("off the menu") ? "off menu"
            : reason.hasPrefix(BrainError.refusedPrefix) ? "refused"
            : reason.hasPrefix("late") ? "late"
            : reason.hasPrefix("cancelled") ? "cancelled" : "error"
    }

    /// Expected and actual, step by step, for a failed scenario, with how
    /// Stage 1 got to each actual pass.
    public static func diff(_ result: Result) -> String {
        var lines: [String] = []
        for (i, step) in result.steps.enumerated() where !step.passed {
            let words = step.event.words.map { " \"\($0)\"" } ?? ""
            lines.append("  step \(i + 1) (\(step.event.atMs / 1000)s \(step.event.event)\(words))")
            lines += step.expect.isEmpty ? ["    - (nothing reached the harness)"] : step.expect.map { "    - " + $0.line }
            if step.actual.isEmpty { lines.append("    + (nothing reached the harness)") }
            for (actual, evidence) in zip(step.actual, step.evidence) {
                lines.append("    + " + actual)
                if let evidence { lines.append("        because: " + evidence) }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A report to compare runs: one object per scenario, with each run's
    /// steps, expected and actual passes. A scenario passes when every run did.
    public static func json(_ runs: [[Result]], classifier: String, writer: String) -> String {
        let o: [String: Any] = [
            "classifier": classifier,
            "writer": writer,
            "passed": runs.filter { $0.allSatisfy(\.passed) }.count,
            "total": runs.count,
            "scenarios": runs.compactMap { rs -> [String: Any]? in
                guard let first = rs.first else { return nil }
                return ["name": first.scenario.name, "file": first.scenario.file, "passed": rs.allSatisfy(\.passed),
                        "runs": rs.map { r -> [String: Any] in
                            ["passed": r.passed,
                             "steps": r.steps.map { s -> [String: Any] in
                                 ["at_s": s.event.atMs / 1000, "event": s.event.event, "expect": s.expect.map(\.line),
                                  "actual": s.actual, "evidence": s.evidence.map { $0 ?? "" }, "passed": s.passed]
                             }]
                        }]
            },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .prettyPrinted,
                                                                            .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// The scripted answers for the step being run, if it has any.
final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var classifier: Scenario.ScriptedClassifier?
    private var writer: Scenario.ScriptedWriter?

    func set(_ classifier: Scenario.ScriptedClassifier?, _ writer: Scenario.ScriptedWriter?) {
        lock.withLock {
            self.classifier = classifier
            self.writer = writer
        }
    }

    var forClassifier: Scenario.ScriptedClassifier? { lock.withLock { classifier } }
    var forWriter: Scenario.ScriptedWriter? { lock.withLock { writer } }
}

/// The virtual clock, read by the actions' context.
final class Clock: @unchecked Sendable {
    var now: Int64
    init(_ now: Int64) { self.now = now }
}

/// Effects an action asked the core for (`quiet`), carried out after the
/// pass that caused them. Touched only on the eval's queue.
final class Pending: @unchecked Sendable {
    let store: MemoryStore
    var effects: [CoreEffect] = []
    init(store: MemoryStore) { self.store = store }
}

/// The classifier in use, unless the step scripts Stage 1.
struct ScriptedClassifier: Classifier {
    let base: any Classifier
    let script: Script
    var id: String { base.id }

    func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        switch script.forClassifier {
        case nil: return try await base.classify(context, menu, deadline: deadline)
        case .calls(let calls): return Classification(calls: calls, evidence: "scripted")
        case .error(let why): throw BrainError(why)
        case .refused: throw BrainError.refused("scripted")
        // The harness's own deadline error, without waiting for it.
        case .late: throw BrainError("late: scripted")
        }
    }
}

/// The writer in use, unless the step scripts Stage 2.
struct ScriptedWriter: Writer {
    let base: any Writer
    let script: Script
    var id: String { base.id }

    func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        switch script.forWriter {
        case nil: return try await base.write(context, slots, deadline: deadline)
        case .values(let values): return Writing(values: values, raw: "scripted")
        case .error(let why): throw BrainError(why)
        case .refused: throw BrainError.refused("scripted")
        case .late: throw BrainError("late: scripted")
        }
    }
}
