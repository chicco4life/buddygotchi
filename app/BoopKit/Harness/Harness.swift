import Foundation

/// The harness (harness/HARNESS.md): records every event the core hands it,
/// and for each one that wakes the brain, builds the state, asks every
/// action's questions in one request, hands each action its own answers,
/// and records what they report. It never reads an event's facts or an
/// action's answers, builds Minion speech or talks to the device.
///
/// One pass runs at a time; a newer event that wakes the brain replaces one
/// that's waiting. Everything but the brain call runs on `home`.
public final class Harness: @unchecked Sendable {
    /// What one pass did, for the app log and tests.
    public struct Record: Sendable {
        public var event: Event
        public var pass: Transcript.Pass
        public var actions: [Transcript.ActionRecord]

        /// The app log's line (§9): the event's kind, the latency and which
        /// actions returned a result, never their messages.
        public var logLine: String {
            "brain \(event.kind.rawValue) \(pass.latencyMs) ms → "
                + (pass.dropped.map { "dropped: \($0)" } ?? Transcript.ActionRecord.names(actions))
        }
    }

    /// The brain in use, or nil for none (no key): no pass runs.
    public private(set) var brain: (any Brain)?
    let actions: [any Action]
    /// Everything the state needs besides the transcript, for the pass on
    /// an event: the static parts, the status line and the clock.
    let parts: (Transcript.Entry) -> StateText.Parts
    let home: DispatchQueue
    let clock: @Sendable () -> Int64
    let debugLog: URL?
    let log: (String) -> Void

    public let transcript = Transcript()
    /// Called on `home` after every pass, dropped ones included.
    public var onRecord: ((Record) -> Void)?
    /// Called on `home` with every `debug.jsonl` line, file or not.
    public var onDebugLine: ((String) -> Void)?

    /// The whole pass must finish within this.
    public static let deadlineMs = 1250
    /// An action taking longer than this is logged: it should hand slow work off.
    public static let actionSlowMs = 300

    var running: Int?
    var waiting: Transcript.Entry?

    public init(brain: (any Brain)?, actions: [any Action], parts: @escaping (Transcript.Entry) -> StateText.Parts,
                home: DispatchQueue, clock: @escaping @Sendable () -> Int64, debugLog: URL? = nil,
                log: @escaping (String) -> Void = { _ in }) {
        self.brain = brain
        self.actions = actions
        self.parts = parts
        self.home = home
        self.clock = clock
        self.debugLog = debugLog
        self.log = log
        let keys = actions.flatMap { $0.questions().map(\.key) }
        precondition(Set(keys).count == keys.count, "question keys must be unique across actions: \(keys)")
    }

    /// A new brain, from the next pass on; nil for none. Call on `home`.
    public func use(_ brain: (any Brain)?) {
        dispatchPrecondition(condition: .onQueue(home))
        self.brain = brain
    }

    /// An event from the core: recorded, and a pass for it if it wakes the
    /// brain. Call on `home`.
    public func take(_ event: Event) {
        dispatchPrecondition(condition: .onQueue(home))
        let entry = append(.event(event), at: event.receivedAtMs)
        guard event.wakesBrain, brain != nil else { return }
        if running != nil {
            if let old = waiting, case .event(let e) = old.body {
                log("harness: \(e.kind.rawValue) replaced by a newer \(event.kind.rawValue)")
            }
            waiting = entry
            return
        }
        start(entry)
    }

    /// Nothing running and nothing waiting. Call on `home`.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(home))
        return running == nil && waiting == nil
    }

    // MARK: A pass (§3)

    /// What a pass sends, fixed when it starts on `home`.
    struct Job: Sendable {
        var brain: any Brain
        var state: String
        var questions: [Question]
    }

    var nextPass = 0

    func start(_ entry: Transcript.Entry) {
        guard let brain else { return }
        nextPass += 1
        let id = nextPass
        running = id
        let job = prepare(entry, brain: brain)
        Task { [self] in
            let started = ContinuousClock.now
            let result = await Harness.race(Harness.deadlineMs) {
                try await job.brain.answer(state: job.state, questions: job.questions, deadline: .milliseconds(Harness.deadlineMs))
            }
            let ms = (ContinuousClock.now - started).ms
            home.async { [self] in
                guard running == id else { return }
                running = nil
                finish(entry, job, result, latencyMs: ms)
                if let next = waiting {
                    waiting = nil
                    start(next)
                }
            }
        }
    }

    /// Step 3, on `home`: the state and every action's questions.
    func prepare(_ entry: Transcript.Entry, brain: any Brain) -> Job {
        let state = StateText.build(transcript.entries, now: entry, at: clock(), parts(entry))
        return Job(brain: brain, state: state, questions: actions.flatMap { $0.questions() })
    }

    /// Steps 5–7, on `home`: each action gets its own answers, in order,
    /// and everything is recorded.
    func finish(_ entry: Transcript.Entry, _ job: Job, _ result: Result<Answers, BrainError>, latencyMs: Int) {
        guard case .event(let event) = entry.body else { return }
        var pass = Transcript.Pass(forSeq: entry.seq, answers: [:], dropped: nil, latencyMs: latencyMs)
        switch result {
        case .failure(let error):
            pass.dropped = error.description
            if let raw = error.raw { log("harness: \(job.brain.id) answered what couldn't be used (\(raw.count) bytes)") }
        case .success(let answers):
            pass.answers = answers
        }
        record(.pass(pass), extra: ["state": job.state, "questions": job.questions.map(\.key), "brain": job.brain.id])
        let ran = pass.dropped == nil ? runActions(pass.answers, forSeq: entry.seq) : []
        let record = Record(event: event, pass: pass, actions: ran)
        if let dropped = pass.dropped { log("harness: \(event.kind.rawValue) dropped: \(dropped)") }
        onRecord?(record)
    }

    /// Hands each action its own answers, in order, and records what each
    /// reports.
    func runActions(_ answers: Answers, forSeq: Int?) -> [Transcript.ActionRecord] {
        var ran: [Transcript.ActionRecord] = []
        for action in actions {
            let own = Dictionary(uniqueKeysWithValues: action.questions().compactMap { q in answers[q.key].map { (q.key, $0) } })
            let started = ContinuousClock.now
            let result = action.run(own)
            let ms = (ContinuousClock.now - started).ms
            if ms > Harness.actionSlowMs { log("harness: \(action.name) took \(ms) ms; slow work should be handed off") }
            guard let result else { continue }
            let a = Transcript.ActionRecord(forSeq: forSeq, name: action.name, result: result, latencyMs: ms)
            ran.append(a)
            record(.action(a))
        }
        return ran
    }

    // MARK: Forced (the dashboard, §9)

    /// A pass whose answers are given, not asked: each choice at
    /// probability 1, handed to the actions exactly as Jev's would be. It
    /// runs at once, needs no brain, and leaves the pass running or waiting
    /// alone. It's recorded for no event; a choice that isn't one of its
    /// question's options is left out. Call on `home`.
    public func force(_ choices: [String: String]) -> [Transcript.ActionRecord] {
        dispatchPrecondition(condition: .onQueue(home))
        let asked = actions.flatMap { $0.questions() }.filter { q in q.options.contains { $0.name == choices[q.key] } }
        let answers = Dictionary(uniqueKeysWithValues: asked.compactMap { q in
            choices[q.key].map { (q.key, Answer(choice: $0, probabilities: [$0: 1])) }
        })
        if answers.count < choices.count { log("harness: forced answers left out: \(Set(choices.keys).subtracting(answers.keys).sorted())") }
        record(.pass(Transcript.Pass(forSeq: nil, answers: answers, dropped: nil, latencyMs: 0)), extra: ["questions": asked.map(\.key)])
        return runActions(answers, forSeq: nil)
    }

    /// One action doing `body` outside any pass, such as setting the mood
    /// the dashboard picked: its result is recorded for no event. Call on
    /// `home`.
    public func force(_ action: any Action, _ body: () -> ActionResult?) -> ActionResult? {
        dispatchPrecondition(condition: .onQueue(home))
        let started = ContinuousClock.now
        guard let result = body() else { return nil }
        record(.action(Transcript.ActionRecord(forSeq: nil, name: action.name, result: result,
                                               latencyMs: (ContinuousClock.now - started).ms)))
        return result
    }

    /// Appends and logs one entry.
    @discardableResult
    func append(_ body: Transcript.Body, at ms: Int64, extra: [String: Any] = [:]) -> Transcript.Entry {
        let entry = transcript.append(body, at: ms)
        if debugLog != nil || onDebugLine != nil {
            let line = Transcript.json(entry, extra: extra)
            if let debugLog { Harness.appendLine(line, to: debugLog) }
            onDebugLine?(line)
        }
        return entry
    }

    func record(_ body: Transcript.Body, extra: [String: Any] = [:]) {
        append(body, at: clock(), extra: extra)
    }

    /// One event straight through, without the queue: for the evals. Don't
    /// call on `home`. Returns nil when it didn't wake the brain.
    public func respond(to event: Event) async -> Record? {
        let (entry, job): (Transcript.Entry, Job?) = home.sync {
            let entry = append(.event(event), at: event.receivedAtMs)
            guard event.wakesBrain, let brain else { return (entry, nil) }
            return (entry, prepare(entry, brain: brain))
        }
        guard let job else { return nil }
        let started = ContinuousClock.now
        let result = await Harness.race(Harness.deadlineMs) {
            try await job.brain.answer(state: job.state, questions: job.questions, deadline: .milliseconds(Harness.deadlineMs))
        }
        let ms = (ContinuousClock.now - started).ms
        return home.sync {
            var out: Record?
            let keep = onRecord
            onRecord = { out = $0; keep?($0) }
            finish(entry, job, result, latencyMs: ms)
            onRecord = keep
            return out
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

    /// Appends `line` and a newline, opening the file for each line.
    static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

extension Duration {
    /// In whole milliseconds.
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
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
