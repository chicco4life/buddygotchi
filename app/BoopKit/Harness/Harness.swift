import Foundation

/// The harness (harness/HARNESS.md): for each view event that wakes the
/// brain, builds the state, asks every action's questions in one request,
/// hands each action its own answers, and records what they report as
/// `action` events in the transcript. It never reads a view event's facts
/// or an action's answers, builds Minion speech or talks to the device.
///
/// One pass runs at a time; a newer view event that wakes the brain
/// replaces one that's waiting. Everything but the brain call runs on
/// `home`.
public final class Harness: @unchecked Sendable {
    /// What the brain was asked and answered for one view event, or the
    /// answers the dashboard forced, for none (`forSeq` nil). Only
    /// `debug.jsonl` keeps it.
    public struct Pass: Equatable, Sendable {
        /// The raw event its view event came from.
        public var forSeq: Int?
        public var answers: Answers
        /// Why nothing ran: Jev failed, was late, or had no answer.
        public var dropped: String?
        public var latencyMs: Int
    }

    /// What one action reported, and its `action` event's `seq`.
    public struct ActionRecord: Equatable, Sendable {
        public var name: String
        public var result: ActionResult
        public var latencyMs: Int
        public var seq: Int

        /// Which actions returned a result, for the app log:
        /// `mood, react (failed)`, or `nothing`.
        public static func names(_ records: [ActionRecord]) -> String {
            records.isEmpty ? "nothing" : records.map { $0.name + ($0.result.ok ? "" : " (failed)") }.joined(separator: ", ")
        }
    }

    /// What one pass did, for the app log and tests.
    public struct Record: Sendable {
        public var now: ViewEvent
        public var pass: Pass
        public var actions: [ActionRecord]

        /// The app log's line (§9): the view event's kind, the latency and
        /// which actions returned a result, never their messages.
        public var logLine: String {
            "brain \(now.name) \(pass.latencyMs) ms → "
                + (pass.dropped.map { "dropped: \($0)" } ?? ActionRecord.names(actions))
        }
    }

    /// Who forces passes and actions, for no view event: its actions are
    /// `by` it (harness/HARNESS.md §9).
    public static let forcedBy = "dashboard"

    /// The brain in use, or nil for none (no key): no pass runs.
    public private(set) var brain: (any Brain)?
    /// Whether the brain has failed for long enough to say so (§7), and
    /// how many passes that asked it have dropped in a row.
    public private(set) var trouble: BrainTrouble?
    var droppedInARow = 0
    let actions: [any Action]
    /// Where events are recorded and the view is kept.
    public let pipeline: Pipeline
    /// Everything the state needs besides the view, for the pass on a view
    /// event: the static parts, the closing line and the clock.
    let parts: (ViewEvent) -> StateText.Parts
    let home: DispatchQueue
    let clock: @Sendable () -> Int64
    let debugLog: URL?
    let log: (String) -> Void

    /// Called on `home` after every pass, dropped ones included.
    public var onRecord: ((Record) -> Void)?
    /// Called on `home` with every pass's `debug.jsonl` line, file or not.
    public var onDebugLine: ((String) -> Void)?
    /// Whether a waiting view event's pass may start now: not while
    /// something needs you, when nothing but a poke wakes the brain
    /// (EVENTS.md §6).
    public var mayStart: (ViewEvent) -> Bool = { _ in true }

    /// The whole pass must finish within this.
    public static let deadlineMs = 1500
    /// An action taking longer than this is logged: it should hand slow work off.
    public static let actionSlowMs = 300
    /// A started action still in progress this long after its result is
    /// ended as failed (§5.1).
    public static let pendingMaxMs: Int64 = 60_000

    var running: Int?
    var waiting: ViewEvent?
    /// The actions the dashboard made act while the running pass ran: the
    /// pass's state is from before, so they sit its answers out (§2).
    var changedDuringPass: Set<String> = []

    /// A started action, still in progress: its name, when its result was
    /// recorded, and who it was by.
    struct Open {
        var name: String
        var since: Int64
        var by: String
    }

    /// Started actions still in progress, by their `action` event's `seq`.
    var open: [Int: Open] = [:]

    public init(brain: (any Brain)?, actions: [any Action], pipeline: Pipeline,
                parts: @escaping (ViewEvent) -> StateText.Parts, home: DispatchQueue,
                clock: @escaping @Sendable () -> Int64, debugLog: URL? = nil, log: @escaping (String) -> Void = { _ in }) {
        self.brain = brain
        self.actions = actions
        self.pipeline = pipeline
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
        trouble = nil
        droppedInARow = 0
    }

    /// View events from the pipeline: a pass for each that wakes the
    /// brain. Call on `home`.
    public func take(_ views: [ViewEvent]) {
        dispatchPrecondition(condition: .onQueue(home))
        for view in views where view.wakesBrain && brain != nil {
            if running != nil {
                if let old = waiting { log("harness: \(old.name) replaced by a newer \(view.name)") }
                waiting = view
                continue
            }
            start(view)
        }
    }

    /// Nothing running and nothing waiting. Call on `home`.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(home))
        return running == nil && waiting == nil
    }

    // MARK: A pass (§3)

    /// What a pass sends, fixed when it starts on `home`, and the last
    /// event its state saw.
    struct Job: Sendable {
        var brain: any Brain
        var state: String
        var questions: [Question]
        var seen: Int
    }

    var nextPass = 0

    func start(_ now: ViewEvent) {
        guard let brain else { return }
        nextPass += 1
        let id = nextPass
        running = id
        changedDuringPass = []
        let job = prepare(now, brain: brain)
        let kind = now.name
        Task { [self] in
            let (result, ms) = await Harness.ask(job) { [weak self] ms, late in
                self?.home.async { [weak self] in
                    self?.log("harness: \(job.brain.id) answered after \(ms) ms, too late for the \(kind) pass" + late)
                }
            }
            home.async { [self] in
                guard running == id else { return }
                running = nil
                finish(now, job, result, latencyMs: ms)
                changedDuringPass = []
                if let next = waiting {
                    waiting = nil
                    if mayStart(next) {
                        start(next)
                    } else {
                        finish(next, nil, .failure(BrainError("something needs you")), latencyMs: 0, brainID: job.brain.id)
                    }
                }
            }
        }
    }

    /// Step 3, on `home`: the state and every action's questions.
    func prepare(_ now: ViewEvent, brain: any Brain) -> Job {
        let state = StateText.build(pipeline.view.events, now: now, at: clock(), parts(now))
        return Job(brain: brain, state: state, questions: actions.flatMap { $0.questions() },
                   seen: pipeline.transcript.events.last?.seq ?? now.seq)
    }

    /// Steps 5–7, on `home`: each action gets its own answers, in order,
    /// and everything is recorded.
    /// A pass with no `job` never asked the brain `brainID`: a waiting
    /// view event whose pass couldn't start.
    func finish(_ now: ViewEvent, _ job: Job?, _ result: Result<Answers, BrainError>, latencyMs: Int,
                brainID: String? = nil) {
        var pass = Pass(forSeq: now.seq, answers: [:], dropped: nil, latencyMs: latencyMs)
        if job != nil {
            // Only a pass that asked the brain says how it's doing.
            let error: BrainError? = if case .failure(let e) = result { e } else { nil }
            (droppedInARow, trouble) = BrainTrouble.after(error, previous: droppedInARow)
        }
        switch result {
        case .failure(let error):
            pass.dropped = error.description
            if let raw = error.raw, let job { log("harness: \(job.brain.id) answered what couldn't be used (\(raw.count) bytes)") }
        case .success(let answers):
            pass.answers = answers
        }
        var nowJSON: [String: Any] = ["id": now.id, "type": now.type.rawValue, "line": now.line]
        if let phase = now.phase { nowJSON["phase"] = phase.rawValue }
        var extra: [String: Any] = ["now": nowJSON]
        if let job {
            extra.merge(["state": job.state, "questions": job.questions.map(\.key), "brain": job.brain.id, "seen": job.seen]) { $1 }
        } else {
            extra["brain"] = brainID ?? brain?.id ?? "none"
        }
        logPass(pass, extra: extra)
        let ran = pass.dropped == nil
            ? runActions(pass.answers, forSeq: now.seq, by: "brain", skipping: changedDuringPass) : []
        let record = Record(now: now, pass: pass, actions: ran)
        if let dropped = pass.dropped { log("harness: \(now.name) dropped: \(dropped)") }
        onRecord?(record)
    }

    /// Hands each action its own answers, in order, and records what each
    /// reports. The ones named in `skipping` sit out: they changed since
    /// the state the answers are about.
    func runActions(_ answers: Answers, forSeq: Int?, by: String, skipping: Set<String> = []) -> [ActionRecord] {
        var ran: [ActionRecord] = []
        for action in actions {
            if skipping.contains(action.name) {
                log("harness: \(action.name) sat out the pass: the dashboard changed it while the pass ran")
                continue
            }
            let own = Dictionary(uniqueKeysWithValues: action.questions().compactMap { q in answers[q.key].map { (q.key, $0) } })
            let started = ContinuousClock.now
            let result = action.run(own)
            let ms = (ContinuousClock.now - started).ms
            if ms > Harness.actionSlowMs { log("harness: \(action.name) took \(ms) ms; slow work should be handed off") }
            guard let result else { continue }
            ran.append(record(action.name, result, forSeq: forSeq, by: by, latencyMs: ms))
        }
        return ran
    }

    /// Records an action's result as an `action` event (EVENTS.md §2): one
    /// that started something is a `start`, open until its handle ends and
    /// its `end` is recorded (§5.1).
    func record(_ name: String, _ result: ActionResult, forSeq: Int?, by: String, latencyMs: Int) -> ActionRecord {
        let started = result.ok && result.pending != nil
        let e = pipeline.record(Event(ts: clock(), source: .boop, type: .action, phase: started ? .start : nil,
                                      specificType: name,
                                      data: ["for": forSeq.map { .int(Int64($0)) } ?? .null, "by": .string(by),
                                             "ok": .bool(result.ok), "message": .string(result.message),
                                             "latency_ms": .int(Int64(latencyMs))]))
        if started, let pending = result.pending {
            open[e.seq] = Open(name: name, since: e.ts, by: by)
            pending.bind { [weak self] end in self?.settle(e.seq, end) }
        }
        return ActionRecord(name: name, result: result, latencyMs: latencyMs, seq: e.seq)
    }

    /// Ends an open action; one already ended is left alone. A handle is
    /// finished on `home`, so this runs there.
    func settle(_ seq: Int, _ end: Pending.End) {
        dispatchPrecondition(condition: .onQueue(home))
        guard let item = open.removeValue(forKey: seq) else { return }
        var data: [String: JSONValue] = ["for": .int(Int64(seq)), "by": .string(item.by)]
        switch end {
        case .done: data["outcome"] = "done"
        case .failed(let why): data["outcome"] = "failed"; data["why"] = .string(why)
        }
        pipeline.record(Event(ts: clock(), source: .boop, type: .action, phase: .end, specificType: item.name, data: data))
    }

    /// Ends every action still in progress `pendingMaxMs` after its result,
    /// so HISTORY never says so for good. The runtime calls it every
    /// second. Call on `home`.
    public func tick(now: Int64) {
        dispatchPrecondition(condition: .onQueue(home))
        for (seq, item) in open.sorted(by: { $0.key < $1.key }) where now - item.since >= Harness.pendingMaxMs {
            log("harness: \(item.name) was still in progress after \(now - item.since) ms; ended it")
            settle(seq, .failed("no word it finished"))
        }
    }

    // MARK: Forced (the dashboard, §9)

    /// A pass whose answers are given, not asked: each choice at
    /// probability 1, handed to the actions exactly as Jev's would be. It
    /// runs at once, needs no brain, and leaves the pass running or waiting
    /// alone. It's for no view event; a choice that isn't one of its
    /// question's options is left out. Call on `home`.
    public func force(_ choices: [String: String]) -> [ActionRecord] {
        dispatchPrecondition(condition: .onQueue(home))
        let asked = actions.flatMap { $0.questions() }.filter { q in q.options.contains { $0.name == choices[q.key] } }
        let answers = Dictionary(uniqueKeysWithValues: asked.compactMap { q in
            choices[q.key].map { (q.key, Answer(choice: $0, probabilities: [$0: 1])) }
        })
        if answers.count < choices.count { log("harness: forced answers left out: \(Set(choices.keys).subtracting(answers.keys).sorted())") }
        logPass(Pass(forSeq: nil, answers: answers, dropped: nil, latencyMs: 0),
                extra: ["questions": asked.map(\.key), "by": Harness.forcedBy])
        let ran = runActions(answers, forSeq: nil, by: Harness.forcedBy)
        for a in ran where a.result.ok { changedOutsidePass(a.name) }
        return ran
    }

    /// An action acted outside any pass: if a pass is running, its state is
    /// from before, so the action sits that pass's answers out (§2).
    func changedOutsidePass(_ name: String) {
        if running != nil { changedDuringPass.insert(name) }
    }

    /// One action doing `body` outside any pass, such as setting the mood
    /// the dashboard picked: its result is recorded for no view event.
    /// Call on `home`.
    public func force(_ action: any Action, _ body: () -> ActionResult?) -> ActionResult? {
        dispatchPrecondition(condition: .onQueue(home))
        let started = ContinuousClock.now
        guard let result = body() else { return nil }
        _ = record(action.name, result, forSeq: nil, by: Harness.forcedBy, latencyMs: (ContinuousClock.now - started).ms)
        if result.ok { changedOutsidePass(action.name) }
        return result
    }

    /// A pass's `debug.jsonl` line (§9).
    func logPass(_ pass: Pass, extra: [String: Any]) {
        guard debugLog != nil || onDebugLine != nil else { return }
        let line = DebugLog.pass(pass, extra: extra, at: clock())
        if let debugLog { Harness.appendLine(line, to: debugLog) }
        onDebugLine?(line)
    }

    /// One view event straight through, without the queue: for the evals.
    /// Don't call on `home`. Returns nil when it doesn't wake the brain.
    public func respond(to now: ViewEvent) async -> Record? {
        let job: Job? = home.sync {
            guard now.wakesBrain, let brain else { return nil }
            return prepare(now, brain: brain)
        }
        guard let job else { return nil }
        let (result, ms) = await Harness.ask(job)
        return home.sync {
            var out: Record?
            let keep = onRecord
            onRecord = { out = $0; keep?($0) }
            finish(now, job, result, latencyMs: ms)
            onRecord = keep
            return out
        }
    }

    // MARK: Helpers

    /// Step 4, off `home`: the brain's answers within the deadline, and how
    /// long they took in ms. A request the deadline passed goes on to its
    /// end, and `late` gets how long it took and what it came to (`""`, or
    /// `: ` and why it failed), so the log can say when the brain did
    /// answer: a dropped pass's own latency is only the deadline's.
    private static func ask(_ job: Job, late: @escaping @Sendable (Int, String) -> Void = { _, _ in }) async
        -> (Result<Answers, BrainError>, Int) {
        let started = ContinuousClock.now
        let result = await race(deadlineMs, late: { ms, result in
            if case .failure(let error) = result { late(ms, ": " + error.description) } else { late(ms, "") }
        }) {
            try await job.brain.answer(state: job.state, questions: job.questions, deadline: .milliseconds(deadlineMs))
        }
        return (result, (ContinuousClock.now - started).ms)
    }

    /// How late the deadline's timer may fire: the system's default leeway
    /// let it fire up to 7% late, 1.6 s for 1.5 s.
    static let deadlineLeewayMs = 5

    /// `work`, raced against a deadline and cancelling. Past the deadline,
    /// work goes on to its end if `late` is given, which then gets how long
    /// it took and its result; otherwise it's cancelled. Work that ignores
    /// cancelling is left to finish on its own. Either way its answer is
    /// dropped.
    static func race<T: Sendable>(_ ms: Int, late: (@Sendable (Int, Result<T, BrainError>) -> Void)? = nil,
                                  _ work: @escaping @Sendable () async throws -> T) async -> Result<T, BrainError> {
        let once = Once<Result<T, BrainError>>()
        let started = ContinuousClock.now
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Result<T, BrainError>, Never>) in
                once.set(k)
                once.add(Task {
                    let result: Result<T, BrainError>
                    do {
                        result = .success(try await work())
                    } catch let error as BrainError {
                        result = .failure(error)
                    } catch {
                        result = .failure(BrainError("\(error)"))
                    }
                    if !once.resume(result), let late { late((ContinuousClock.now - started).ms, result) }
                })
                once.add(Task {
                    try? await Task.sleep(for: .milliseconds(ms), tolerance: .milliseconds(deadlineLeewayMs))
                    once.resume(.failure(BrainError("late: no answer within \(ms) ms")), cancellingOthers: late == nil)
                })
            }
        } onCancel: {
            once.resume(.failure(BrainError("cancelled")))
        }
    }

    /// Appends `line` and a newline, opening the file for each line.
    public static func appendLine(_ line: String, to url: URL) {
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

    /// Delivers `value` if nothing came first, and says whether it did.
    /// The other tasks are cancelled then, unless `cancellingOthers` is
    /// false.
    @discardableResult
    func resume(_ value: T, cancellingOthers: Bool = true) -> Bool {
        let (k, others, first): (CheckedContinuation<T, Never>?, [Task<Void, Never>], Bool) = lock.withLock {
            guard !done else { return (nil, [], false) }
            guard let continuation else {
                guard pending == nil else { return (nil, [], false) }
                pending = value
                return (nil, [], true)
            }
            done = true
            self.continuation = nil
            return (continuation, cancellingOthers ? tasks : [], true)
        }
        guard let k else { return first }
        k.resume(returning: value)
        for task in others { task.cancel() }
        return true
    }
}
