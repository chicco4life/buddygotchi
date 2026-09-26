import Foundation

/// The brain's pipeline (HARNESS.md §3): an input → Stage 1, the classifier,
/// picks outputs from the input's menu → Stage 2, the writer, writes any
/// words they need → each call to its action. Both stages read one
/// append-only transcript (§4). The harness doesn't know what any output
/// does, or what kind of model is behind either stage: the app hands it
/// `(definition, handler)` pairs at startup.
///
/// One pass runs at a time. A newer input replaces one that's waiting, and
/// `you said` cancels whatever is running. A new day waits apart and is never
/// replaced: it comes once a day, and a reflection cut off by you talking runs
/// again after the reply. Everything except the two brain
/// calls runs on `home`, the queue the memory store and the actions live on.
public final class Harness: @unchecked Sendable {
    /// An output as the harness sees it: its definition, and who carries out a call.
    public struct Tool {
        /// Asked again for every pass, since a definition may depend on memory.
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

    /// What one pass did, logged as one JSON line in debug mode (§8).
    public struct Record: Sendable {
        public var input: Input
        public var classifier: String
        public var writer: String
        /// Inputs in the window this pass saw, its own included.
        public var window: Int
        /// Stage 1's calls, in the order they run.
        public var decided: [ToolCall] = []
        public var evidence: String?
        /// Why the pass produced nothing: Stage 1 failed, was late or
        /// cancelled, or answered off the menu.
        public var dropped: String?
        /// The slots Stage 2 was asked to fill, and what it wrote ("" left empty).
        public var slots: [String] = []
        public var wrote: [String: String] = [:]
        public var writerRaw: String?
        /// Why Stage 2 wrote nothing, if it failed or was late.
        public var writeFailed: String?
        /// Each call handed off, with what its action did.
        public var ran: [(call: ToolCall, outcome: ActionOutcome)] = []
        public var classifyMs = 0
        public var writeMs = 0
        public var latencyMs = 0

        public init(input: Input, classifier: String, writer: String, window: Int) {
            self.input = input
            self.classifier = classifier
            self.writer = writer
            self.window = window
        }

        /// Stage 1 answered with calls the menu allows (none counts).
        public var answered: Bool { dropped == nil }
        public var silent: Bool { answered && decided.isEmpty }
        /// A model declined to answer (a guardrail).
        public var refused: Bool {
            (dropped ?? writeFailed ?? "").hasPrefix(BrainError.refusedPrefix)
        }

        /// The one line the app logs for a pass outside debug mode (§8): the
        /// input kind, the latency and the outputs that ran, or why nothing
        /// did. Never argument values, which can carry what you said:
        /// `brain you said 812 ms → quiet, react`. A call its action dropped
        /// shows as `remember (dropped)`; the action logs why.
        public var logLine: String {
            let tools = ran.map { $0.outcome.isDone ? $0.call.name : "\($0.call.name) (dropped)" }
            let answer = dropped.map { "dropped: \($0)" } ?? (tools.isEmpty ? "nothing" : tools.joined(separator: ", "))
            let write = writeFailed.map { " (writer failed: \($0))" } ?? ""
            return "brain \(input.kind.rawValue) \(latencyMs) ms → \(answer)\(write)"
        }

        public var json: String {
            var input: [String: Any] = ["kind": self.input.kind.rawValue, "line": self.input.line, "ts": self.input.ts]
            if let words = self.input.words { input["words"] = words }
            var o: [String: Any] = [
                "input": input, "classifier": classifier, "writer": writer, "window": window,
                "decided": decided.map(\.plain), "slots": slots, "wrote": wrote,
                "classify_ms": classifyMs, "write_ms": writeMs, "latency_ms": latencyMs,
                "ran": ran.map { r -> [String: Any] in
                    switch r.outcome {
                    case .done(let what): ["call": r.call.plain, "done": what]
                    case .dropped(let why): ["call": r.call.plain, "dropped": why]
                    }
                },
            ]
            if let evidence { o["evidence"] = evidence }
            if let dropped { o["dropped"] = dropped }
            if let writerRaw { o["writer_raw"] = writerRaw }
            if let writeFailed { o["write_failed"] = writeFailed }
            let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    public let classifier: any Classifier
    public let writer: any Writer
    let tools: [Tool]
    let memory: (Input) -> Prompt.Memory
    let home: DispatchQueue
    let debugLog: URL?
    let log: (String) -> Void
    /// Shared by both stages (§4). Touched only on `home`.
    public let transcript: Transcript
    /// Called on `home` after every pass, including dropped ones.
    public var onRecord: ((Record) -> Void)?

    // Scheduling, touched only on `home`.
    var running: (id: Int, pass: Pass, task: Task<Void, Never>)?
    var waiting: Input?
    /// A new day's reflection, waiting apart from `waiting`.
    var waitingDay: Input?
    var nextID = 0

    /// Time kept back from Stage 2 so its answer can still be handed off.
    static let marginMs = 100

    /// - Parameters:
    ///   - memory: the memory text for an input, from the memory store.
    ///   - debugLog: a JSONL file for §8's log; nil writes nothing to disk.
    public init(classifier: any Classifier, writer: any Writer, tools: [Tool], memory: @escaping (Input) -> Prompt.Memory,
                home: DispatchQueue, debugLog: URL? = nil, transcript: Transcript = Transcript(),
                log: @escaping (String) -> Void = { _ in }) {
        self.classifier = classifier
        self.writer = writer
        self.tools = tools
        self.memory = memory
        self.home = home
        self.debugLog = debugLog
        self.transcript = transcript
        self.log = log
    }

    // MARK: Scheduling

    /// Queues an input. Call on `home`.
    public func submit(_ input: Input) {
        dispatchPrecondition(condition: .onQueue(home))
        if let running {
            if input.kind == .said {
                running.task.cancel()
                self.running = nil
                transcript.append(.dropped("cancelled by you talking"))
                var record = Record(input: running.pass.input, classifier: classifier.id, writer: writer.id,
                                    window: running.pass.window)
                record.dropped = "cancelled by you talking"
                finish(record)
                // Nothing of a cancelled pass has run, so a reflection can run again.
                if running.pass.input.kind == .newDay { waitingDay = running.pass.input }
            } else if input.kind == .newDay {
                waitingDay = input
                return
            } else {
                if let old = waiting { log("harness: \(old.kind.rawValue) replaced by a newer \(input.kind.rawValue)") }
                waiting = input
                return
            }
        }
        start(input)
    }

    /// Something only the rules handled, for the transcript: a tap, or
    /// something needing you. Call on `home`.
    public func note(_ aside: String, at ts: Int64) {
        dispatchPrecondition(condition: .onQueue(home))
        guard transcript.note(aside, at: ts) else { return }
        if let debugLog {
            let data = (try? JSONSerialization.data(withJSONObject: ["aside": aside, "ts": ts], options: [.sortedKeys])) ?? Data()
            Harness.append(String(decoding: data, as: UTF8.self) + "\n", to: debugLog)
        }
    }

    /// Nothing running and nothing waiting.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(home))
        return running == nil && waiting == nil && waitingDay == nil
    }

    func start(_ input: Input) {
        let pass = prepare(input)
        nextID += 1
        let id = nextID
        let context = pass.context
        let menu = pass.menu
        let task = Task { [self] in
            let thought = await think(context, menu)
            let cancelled = Task.isCancelled
            home.async { [self] in
                guard let running, running.id == id, !cancelled else { return }
                self.running = nil
                finish(hand(running.pass, thought))
                if let next = waiting {
                    waiting = nil
                    start(next)
                } else if let day = waitingDay {
                    waitingDay = nil
                    start(day)
                }
            }
        }
        running = (id, pass, task)
    }

    // MARK: The steps

    /// One pass's inputs, fixed when it starts.
    struct Pass {
        var input: Input
        var context: Context
        var menu: Menu
        var handlers: [String: (ToolCall) -> ActionOutcome]
        var window: Int
    }

    /// Steps 1–2, on `home`: the input and the rules' reaction join the
    /// transcript (moving the window first when it's full), and the menu is
    /// built from the actions' definitions as they are now.
    func prepare(_ input: Input) -> Pass {
        transcript.begin(input)
        let current = tools.map { ($0.definition, $0.handle) }
        let menu = Menu(input.kind.menu, definitions: current.map(\.0))
        let text = memory(input)
        for over in Prompt.overBudget(input, text) {
            log("harness: \(input.kind.rawValue) over budget: \(over)")
        }
        var handlers: [String: (ToolCall) -> ActionOutcome] = [:]
        for (definition, handle) in current { handlers[definition.name] = handle }
        return Pass(input: input, context: Context(input: input, memory: text, window: transcript.window),
                    menu: menu, handlers: handlers, window: transcript.inputs)
    }

    /// What the two brain calls came back with.
    struct Thought: Sendable {
        var classification: Result<Classification, BrainError>
        /// Why Stage 1's calls don't fit the menu.
        var offMenu: String?
        var calls: [ToolCall] = []
        var slots: [Slot] = []
        /// Nil when there was nothing to write.
        var writing: Result<Writing, BrainError>?
        var classifyMs = 0
        var writeMs = 0
    }

    /// Steps 3–5, off `home`: Stage 1, the menu check, then Stage 2 when
    /// something needs words, all within the input's deadline.
    func think(_ context: Context, _ menu: Menu) async -> Thought {
        let deadline = context.input.kind.deadlineMs
        let start = ContinuousClock.now
        let classifier = self.classifier
        let result = await Harness.race(deadline) {
            try await classifier.classify(context, menu, deadline: .milliseconds(deadline))
        }
        var thought = Thought(classification: result, classifyMs: Harness.ms(since: start))
        guard case .success(let classification) = result else { return thought }
        if let why = menu.check(classification.calls) {
            thought.offMenu = why
            return thought
        }
        thought.calls = menu.ordered(classification.calls)
        thought.slots = menu.slots(thought.calls)
        guard !thought.slots.isEmpty else { return thought }

        let left = deadline - thought.classifyMs - Harness.marginMs
        let writeStart = ContinuousClock.now
        if left <= 0 {
            thought.writing = .failure(BrainError("late: no time left to write"))
        } else {
            var written = context
            written.window.append(.decided(by: classifier.id, thought.calls, evidence: classification.evidence))
            let writer = self.writer
            let slots = thought.slots
            let asked = written
            thought.writing = await Harness.race(left) {
                try await writer.write(asked, slots, deadline: .milliseconds(left))
            }
        }
        thought.writeMs = Harness.ms(since: writeStart)
        return thought
    }

    /// Step 6, on `home`: the words go into the calls, each call to its
    /// action in order, and everything into the transcript. A slot left
    /// empty leaves its argument out, or drops its call when it's required
    /// (a memory line with no text).
    func hand(_ pass: Pass, _ thought: Thought) -> Record {
        var record = Record(input: pass.input, classifier: classifier.id, writer: writer.id, window: pass.window)
        record.classifyMs = thought.classifyMs
        record.writeMs = thought.writeMs
        record.latencyMs = thought.classifyMs + thought.writeMs
        let classification: Classification
        switch thought.classification {
        case .failure(let error):
            record.dropped = error.description
            transcript.append(.dropped(error.description))
            return record
        case .success(let c):
            classification = c
        }
        record.evidence = classification.evidence
        if let why = thought.offMenu {
            record.decided = classification.calls
            record.dropped = "off the menu: \(why)"
            transcript.append(.decided(by: classifier.id, classification.calls, evidence: classification.evidence))
            transcript.append(.dropped(record.dropped!))
            return record
        }
        record.decided = thought.calls
        transcript.append(.decided(by: classifier.id, thought.calls, evidence: classification.evidence))

        var calls = thought.calls
        var unwritten: Set<Int> = []
        if let writing = thought.writing {
            record.slots = thought.slots.map(\.key)
            var values: [String: String] = [:]
            switch writing {
            case .success(let w):
                record.writerRaw = w.raw
                for slot in thought.slots { values[slot.key] = slot.value(w.values[slot.key]) ?? "" }
                transcript.append(.wrote(by: writer.id, values))
            case .failure(let error):
                record.writerRaw = error.raw
                record.writeFailed = error.description
                for slot in thought.slots { values[slot.key] = "" }
                transcript.append(.writeFailed(by: writer.id, error.description))
            }
            record.wrote = values
            for slot in thought.slots {
                let value = values[slot.key] ?? ""
                if value.isEmpty {
                    if !slot.optional { unwritten.insert(slot.call) }
                } else {
                    calls[slot.call].arguments[slot.parameter] = .string(value)
                }
            }
        }
        for (i, call) in calls.enumerated() {
            let outcome = unwritten.contains(i) ? .dropped("nothing was written") : pass.handlers[call.name]!(call)
            record.ran.append((call, outcome))
            transcript.append(.ran(call, outcome))
        }
        return record
    }

    /// Step 7. On `home`.
    func finish(_ record: Record) {
        if let dropped = record.dropped { log("harness: \(record.input.kind.rawValue) dropped: \(dropped)") }
        if let failed = record.writeFailed { log("harness: \(record.input.kind.rawValue) writer failed: \(failed)") }
        if let debugLog { Harness.append(record.json + "\n", to: debugLog) }
        onRecord?(record)
    }

    /// One input straight through, without the queue: for `boopdev brain`.
    /// Don't call on `home`.
    public func respond(to input: Input) async -> Record {
        let pass = home.sync { prepare(input) }
        let thought = await think(pass.context, pass.menu)
        return home.sync {
            let record = hand(pass, thought)
            finish(record)
            return record
        }
    }

    // MARK: Helpers

    /// `work`, raced against a deadline and cancelling. Work that ignores
    /// cancelling is left to finish on its own; its answer is dropped.
    static func race<T: Sendable>(_ ms: Int, _ work: @escaping @Sendable () async throws -> T) async -> Result<T, BrainError> {
        let once = Once<Result<T, BrainError>>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Result<T, BrainError>, Never>) in
                once.set(k)
                once.add(Task {
                    do {
                        once.resume(.success(try await work()))
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
    }

    static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
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

/// Resumes a continuation once, from whichever of the work, the deadline or
/// cancelling gets there first, then cancels the others.
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
