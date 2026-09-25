import Foundation

/// Trigger → prompt → one brain call → shape check → each tool call to its
/// handler (HARNESS.md §3). It doesn't know what any tool does: the app hands
/// it `(definition, handler)` pairs at startup.
///
/// One call runs at a time. A newer trigger replaces one that's waiting, and
/// `talk` cancels whatever is running. Everything except the brain call runs
/// on `home`, the queue the memory store and the actions live on.
public final class Harness: @unchecked Sendable {
    /// A tool as the harness sees it: what the brain is shown, and who
    /// carries out a call.
    public struct Tool {
        /// Asked again for every call, since a definition may depend on
        /// memory (`forget` offers the lines there are).
        let define: () -> ToolDefinition
        public var handle: (ToolCall) -> ActionOutcome
        public var definition: ToolDefinition { define() }

        public init(definition: @escaping @autoclosure () -> ToolDefinition, handle: @escaping (ToolCall) -> ActionOutcome) {
            self.define = definition
            self.handle = handle
        }

        public init(_ action: Action) {
            self.init(definition: action.definition, handle: { action.run($0) })
        }
    }

    /// What one call did, logged as one JSON line in debug mode (§8).
    public struct Record: Sendable {
        public var trigger: Trigger
        public var brain: String
        public var prompt: Prompt
        public var tools: [String]
        /// The brain's answer as it came back, if it did.
        public var raw: String?
        /// Why the call produced nothing: a brain error, lateness, cancelling,
        /// or the shape check dropping the whole answer.
        public var dropped: String?
        /// Each call handed off, with what its handler did.
        public var ran: [(call: ToolCall, outcome: ActionOutcome)]
        public var latencyMs: Int

        /// The answer passed the shape check (an empty one counts).
        public var validShape: Bool { raw != nil && dropped == nil }
        public var silent: Bool { validShape && ran.isEmpty }

        public var json: String {
            var o: [String: Any] = [
                "trigger": ["kind": trigger.kind.rawValue, "line": trigger.line, "ts": trigger.ts],
                "brain": brain, "system": prompt.system, "user": prompt.user, "tools": tools,
                "latency_ms": latencyMs,
                "ran": ran.map { r -> [String: Any] in
                    switch r.outcome {
                    case .done(let what): ["call": r.call.description, "done": what]
                    case .dropped(let why): ["call": r.call.description, "dropped": why]
                    }
                },
            ]
            if let raw { o["raw"] = raw }
            if let dropped { o["dropped"] = dropped }
            let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    public let brain: any Brain
    let tools: [Tool]
    let memory: (Trigger) -> Prompt.Memory
    let home: DispatchQueue
    let debugLog: URL?
    let log: (String) -> Void
    /// Called on `home` after every call, including dropped ones.
    public var onRecord: ((Record) -> Void)?

    // Scheduling, touched only on `home`.
    var running: (id: Int, trigger: Trigger, task: Task<Void, Never>)?
    var waiting: Trigger?
    var nextID = 0
    /// The running call's tools as offered.
    var pending: [Offered] = []

    /// - Parameters:
    ///   - memory: the text for a trigger's prompt, from the memory store.
    ///   - debugLog: a JSONL file for §8's log; nil writes nothing to disk.
    public init(brain: any Brain, tools: [Tool], memory: @escaping (Trigger) -> Prompt.Memory,
                home: DispatchQueue, debugLog: URL? = nil, log: @escaping (String) -> Void = { _ in }) {
        self.brain = brain
        self.tools = tools
        self.memory = memory
        self.home = home
        self.debugLog = debugLog
        self.log = log
    }

    /// The tools offered for a trigger: its kind's list, in the order given
    /// at startup.
    public func offered(_ kind: Trigger.Kind) -> [Tool] {
        tools.filter { kind.tools.contains($0.definition.name) }
    }

    // MARK: Scheduling

    /// Queues a trigger. Call on `home`.
    public func submit(_ trigger: Trigger) {
        dispatchPrecondition(condition: .onQueue(home))
        if let running {
            if trigger.kind == .talk {
                running.task.cancel()
                self.running = nil
                finish(Record(trigger: running.trigger, brain: brain.id, prompt: Prompt(system: "", user: ""),
                              tools: [], raw: nil, dropped: "cancelled by talk", ran: [], latencyMs: 0))
            } else {
                if let old = waiting { log("harness: \(old.kind.rawValue) replaced by a newer \(trigger.kind.rawValue)") }
                waiting = trigger
                return
            }
        }
        start(trigger)
    }

    /// Nothing running and nothing waiting.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(home))
        return running == nil && waiting == nil
    }

    func start(_ trigger: Trigger) {
        let (prompt, offered) = prepare(trigger)
        let definitions = offered.map(\.definition)
        nextID += 1
        let id = nextID
        pending = offered
        let task = Task { [self] in
            let (answer, ms) = await ask(prompt, definitions, deadline: trigger.kind.deadlineMs)
            let cancelled = Task.isCancelled
            home.async { [self] in
                guard running?.id == id, !cancelled else { return }
                running = nil
                finish(hand(trigger, prompt, pending, answer, ms))
                if let next = waiting {
                    waiting = nil
                    start(next)
                }
            }
        }
        running = (id, trigger, task)
    }

    // MARK: The steps

    /// A tool as offered for one call: its definition fixed at prompt time.
    struct Offered {
        var definition: ToolDefinition
        var handle: (ToolCall) -> ActionOutcome
    }

    /// Steps 3–4's inputs: the prompt and the offered tools. On `home`.
    func prepare(_ trigger: Trigger) -> (Prompt, [Offered]) {
        let offered = offered(trigger.kind).map { Offered(definition: $0.definition, handle: $0.handle) }
        let text = memory(trigger)
        for over in Prompt.overBudget(trigger, text, tools: offered.map(\.definition)) {
            log("harness: \(trigger.kind.rawValue) prompt over budget: \(over)")
        }
        return (Prompt(trigger: trigger, memory: text), offered)
    }

    /// Step 4: the brain call, raced against the deadline. A brain that
    /// ignores cancelling is left to finish on its own; its answer is dropped.
    func ask(_ prompt: Prompt, _ tools: [ToolDefinition], deadline ms: Int) async -> (Result<String, BrainError>, Int) {
        let start = ContinuousClock.now
        let brain = self.brain
        let once = Once<Result<String, BrainError>>()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Result<String, BrainError>, Never>) in
                once.set(k)
                once.add(Task {
                    do {
                        once.resume(.success(try await brain.complete(system: prompt.system, user: prompt.user,
                                                                      tools: tools, deadline: .milliseconds(ms))))
                    } catch let error as BrainError {
                        once.resume(.failure(error))
                    } catch {
                        once.resume(.failure(BrainError("\(error)")))
                    }
                })
                once.add(Task {
                    try? await Task.sleep(for: .milliseconds(ms))
                    once.resume(.failure(BrainError("late: no answer within \(ms) ms")))
                })
            }
        } onCancel: {
            once.resume(.failure(BrainError("cancelled")))
        }
        let elapsed = ContinuousClock.now - start
        return (result, Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000))
    }

    /// Steps 5–6: shape check, then each call to its handler in order. On `home`.
    func hand(_ trigger: Trigger, _ prompt: Prompt, _ offered: [Offered], _ answer: Result<String, BrainError>,
              _ ms: Int) -> Record {
        var record = Record(trigger: trigger, brain: brain.id, prompt: prompt, tools: offered.map(\.definition.name),
                            raw: nil, dropped: nil, ran: [], latencyMs: ms)
        switch answer {
        case .failure(let error):
            record.dropped = error.description
        case .success(let raw):
            record.raw = raw
            switch Answer.check(raw, tools: offered.map(\.definition)) {
            case .failure(let why):
                record.dropped = "shape: \(why)"
            case .success(let calls):
                for call in calls {
                    let tool = offered.first { $0.definition.name == call.name }!
                    record.ran.append((call, tool.handle(call)))
                }
            }
        }
        return record
    }

    /// Step 7. On `home`.
    func finish(_ record: Record) {
        if let dropped = record.dropped { log("harness: \(record.trigger.kind.rawValue) answer dropped: \(dropped)") }
        if let debugLog { Harness.append(record.json + "\n", to: debugLog) }
        onRecord?(record)
    }

    /// One trigger straight through, without the queue: for `boopdev brain`.
    /// Don't call on `home`.
    public func respond(to trigger: Trigger) async -> Record {
        let (prompt, offered) = home.sync { prepare(trigger) }
        let (answer, ms) = await ask(prompt, offered.map(\.definition), deadline: trigger.kind.deadlineMs)
        return home.sync {
            let record = hand(trigger, prompt, offered, answer, ms)
            finish(record)
            return record
        }
    }

    static func append(_ line: String, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// Resumes a continuation once, from whichever of the brain, the deadline
/// or cancelling gets there first, then cancels the others.
final class Once<T: Sendable>: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<T, Never>?
    var pending: T?
    var done = false
    var tasks: [Task<Void, Never>] = []

    func set(_ k: CheckedContinuation<T, Never>) {
        let early: T? = lock.withLock {
            guard let pending else {
                continuation = k
                return nil
            }
            done = true
            return pending
        }
        if let early { k.resume(returning: early) }
    }

    func add(_ task: Task<Void, Never>) {
        let finished = lock.withLock {
            tasks.append(task)
            return done
        }
        if finished { task.cancel() }
    }

    func resume(_ value: T) {
        let (k, others): (CheckedContinuation<T, Never>?, [Task<Void, Never>]) = lock.withLock {
            guard !done else { return (nil, []) }
            guard let continuation else {
                if pending == nil { pending = value }
                return (nil, [])
            }
            done = true
            self.continuation = nil
            return (continuation, tasks)
        }
        guard let k else { return }
        k.resume(returning: value)
        for task in others { task.cancel() }
    }
}
