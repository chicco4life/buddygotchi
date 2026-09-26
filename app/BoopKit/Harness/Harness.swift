import Foundation

/// Trigger → situation and menu → one brain call → check → each tool call to
/// its handler (HARNESS.md §3). It doesn't know what any tool does, or what
/// kind of model the brain is: the app hands it `(definition, handler)` pairs
/// at startup, and the brain answers with typed calls.
///
/// One call runs at a time. A newer trigger replaces one that's waiting, and
/// `talk` cancels whatever is running. Event, tap and talk calls share one
/// conversation and are offered the same tools every time; a tool past its
/// limit (HARNESS.md §5) is named in the menu and a call to it is dropped.
/// Everything except the brain call runs on `home`, the queue the memory
/// store and the actions live on.
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
        /// The situation as a language model sees it, whatever the brain.
        public var prompt: Prompt
        public var tools: [String]
        /// The brain's answer as it came back, if it did: a model's JSON, Jev's
        /// answers, or the calls in the answer format.
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
        /// The brain declined to answer (a guardrail); nothing ran.
        public var refused: Bool { dropped?.hasPrefix(BrainError.refusedPrefix) ?? false }

        /// The one line the app logs for a call outside debug mode (§8): the
        /// trigger kind, the latency and the tools that ran, or why nothing
        /// did. Never argument values, which can carry what you said:
        /// `brain talk 812 ms → face, quiet`. A call its action or a limit
        /// dropped shows as `note (dropped)`; the action logs why.
        public var logLine: String {
            let tools = ran.map { $0.outcome.isDone ? $0.call.name : "\($0.call.name) (dropped)" }
            let answer = dropped.map { "dropped: \($0)" } ?? (tools.isEmpty ? "quiet" : tools.joined(separator: ", "))
            return "brain \(trigger.kind.rawValue) \(latencyMs) ms → \(answer)"
        }

        public var json: String {
            var o: [String: Any] = [
                "trigger": ["kind": trigger.kind.rawValue, "line": trigger.line, "ts": trigger.ts],
                "brain": brain, "system": prompt.system, "history": prompt.history.count, "user": prompt.user, "tools": tools,
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
    /// When each limited tool last ran (HARNESS.md §5).
    let limits: ToolLimits
    /// The earlier turns sent with every conversation call (HARNESS.md §4).
    let conversation: Conversation
    /// Called on `home` after every call, including dropped ones.
    public var onRecord: ((Record) -> Void)?

    // Scheduling, touched only on `home`.
    var running: (id: Int, trigger: Trigger, task: Task<Void, Never>)?
    var waiting: Trigger?
    var nextID = 0
    /// The running call's tools as offered, and its conversation's generation.
    var pending: [Offered] = []
    var pendingGeneration: Int?

    /// - Parameters:
    ///   - memory: the text for a trigger's prompt, from the memory store.
    ///   - debugLog: a JSONL file for §8's log; nil writes nothing to disk.
    public init(brain: any Brain, tools: [Tool], memory: @escaping (Trigger) -> Prompt.Memory,
                home: DispatchQueue, debugLog: URL? = nil, limits: ToolLimits = ToolLimits(),
                conversation: Conversation = Conversation(), log: @escaping (String) -> Void = { _ in }) {
        self.brain = brain
        self.tools = tools
        self.memory = memory
        self.home = home
        self.debugLog = debugLog
        self.log = log
        self.limits = limits
        self.conversation = conversation
    }

    /// The tools offered for a trigger, in the order given at startup. A
    /// conversation call gets every conversing kind's tools, so the list never
    /// changes within a conversation; reflection gets its own.
    public func offered(_ kind: Trigger.Kind) -> [Tool] {
        tools.filter { kind.offered.contains($0.definition.name) }
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
        let (call, offered, generation) = prepare(trigger)
        nextID += 1
        let id = nextID
        pending = offered
        pendingGeneration = generation
        let task = Task { [self] in
            let (answer, ms) = await ask(call.situation, call.menu, deadline: trigger.kind.deadlineMs)
            let cancelled = Task.isCancelled
            home.async { [self] in
                guard running?.id == id, !cancelled else { return }
                running = nil
                finish(hand(call, pending, answer, ms, generation: pendingGeneration))
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

    /// One brain call's input: the situation and menu the brain gets, and the
    /// same as a text prompt, for the budget and the log.
    struct Call {
        var situation: Situation
        var menu: Menu
        var prompt: Prompt
        var trigger: Trigger { situation.trigger }
    }

    /// Step 3: the call, the offered tools and, for a conversation call, the
    /// conversation's generation. The conversation starts over when its
    /// opening (system prompt, memory text, tools) has changed, it holds its
    /// most turns, or the request as text would pass its budget. On `home`.
    func prepare(_ trigger: Trigger) -> (Call, [Offered], Int?) {
        let offered = offered(trigger.kind).map { Offered(definition: $0.definition, handle: $0.handle) }
        let definitions = offered.map(\.definition)
        let text = memory(trigger)
        for over in Prompt.overBudget(trigger, text, tools: definitions) {
            log("harness: \(trigger.kind.rawValue) prompt over budget: \(over)")
        }
        func call(_ situation: Situation, _ menu: Menu) -> Call { Call(situation: situation, menu: menu, prompt: Prompt(situation, menu)) }
        guard trigger.kind.converses else {
            return (call(Situation(trigger: trigger, memory: text), Menu(tools: definitions)), offered, nil)
        }
        let menu = Menu(tools: definitions, limits: definitions.compactMap { limits.blocked($0.name, for: trigger) })
        conversation.open([Prompt.system(text.steering), text.longTerm, text.shortTerm,
                           definitions.map(\.json).joined(separator: "\n")].joined(separator: "\n\u{0}\n"))
        if conversation.turns.count > conversation.maxExchanges { conversation.restart() }
        var c = call(Situation(trigger: trigger, memory: text, recent: conversation.turns), menu)
        if !c.situation.recent.isEmpty, Conversation.tokens(c.prompt, tools: definitions) > Conversation.budget {
            conversation.restart()
            c = call(Situation(trigger: trigger, memory: text), menu)
        }
        return (c, offered, conversation.generation)
    }

    /// Step 4: the brain call, raced against the deadline. A brain that
    /// ignores cancelling is left to finish on its own; its answer is dropped.
    func ask(_ situation: Situation, _ menu: Menu, deadline ms: Int) async -> (Result<Decision, BrainError>, Int) {
        let start = ContinuousClock.now
        let brain = self.brain
        let once = Once<Result<Decision, BrainError>>()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Result<Decision, BrainError>, Never>) in
                once.set(k)
                once.add(Task {
                    do {
                        once.resume(.success(try await brain.decide(situation, menu, deadline: .milliseconds(ms))))
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

    /// Steps 5–6: check, then each call to its handler in order, then the
    /// conversation. On `home`.
    func hand(_ call: Call, _ offered: [Offered], _ answer: Result<Decision, BrainError>,
              _ ms: Int, generation: Int?) -> Record {
        let record = handOff(call, offered, answer, ms)
        if let generation { remember(record, limits: call.menu.limits, generation: generation) }
        return record
    }

    /// A conversation call adds what actually ran. A refused, failed or badly
    /// shaped answer starts the conversation over instead, since its history
    /// may be the cause; a late or cancelled one changes nothing.
    func remember(_ record: Record, limits: [String], generation: Int) {
        guard generation == conversation.generation else { return }
        if let dropped = record.dropped {
            if !dropped.hasPrefix("late") && !dropped.hasPrefix("cancelled") { conversation.restart() }
            return
        }
        let done = record.ran.filter { $0.outcome.isDone }.map(\.call)
        conversation.append(Turn(trigger: record.trigger, limits: limits, did: done), generation: generation)
    }

    func handOff(_ c: Call, _ offered: [Offered], _ answer: Result<Decision, BrainError>, _ ms: Int) -> Record {
        let trigger = c.trigger
        var record = Record(trigger: trigger, brain: brain.id, prompt: c.prompt, tools: offered.map(\.definition.name),
                            raw: nil, dropped: nil, ran: [], latencyMs: ms)
        switch answer {
        case .failure(let error):
            record.raw = error.raw
            record.dropped = error.description
        case .success(let decision):
            record.raw = decision.raw ?? Answer.json(decision.calls)
            // Whatever the brain, its calls must fit the menu.
            if let why = Answer.check(calls: decision.calls, tools: offered.map(\.definition)) {
                record.dropped = "shape: \(why)"
            } else {
                for call in decision.calls {
                    // Past its limit, even if the menu said so or an
                    // earlier call in this answer just used it up.
                    if let why = limits.blocked(call.name, for: trigger) {
                        record.ran.append((call, .dropped(why)))
                        continue
                    }
                    let tool = offered.first { $0.definition.name == call.name }!
                    let outcome = tool.handle(call)
                    if outcome.isDone { limits.ran(call.name, for: trigger) }
                    record.ran.append((call, outcome))
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
        let (call, offered, generation) = home.sync { prepare(trigger) }
        let (answer, ms) = await ask(call.situation, call.menu, deadline: trigger.kind.deadlineMs)
        return home.sync {
            let record = hand(call, offered, answer, ms, generation: generation)
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
