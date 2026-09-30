import Foundation

/// The harness (harness/HARNESS.md): for each view event that wakes the
/// brain, builds the state, asks every action's questions in one request,
/// hands each action its own answers, and records what they report as
/// `action` events in the transcript. It never reads a view event's facts
/// or an action's answers, builds Minion speech or talks to the device.
///
/// One pass runs at a time. A newer view event that wakes the brain
/// replaces the last one waiting if that one's priority is 0, and waits
/// behind the ones at its own priority or higher. Everything but the
/// brain call runs on `home`.
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
        /// The questions the pass asked, with the options it offered; none
        /// for a pass that couldn't start.
        public var questions: [Question] = []

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
    /// How many times `use` has changed the brain: a pass that asked an
    /// earlier one doesn't say how this one is doing.
    var brainChanges = 0
    /// The NOW whose answers the actions are running with, while they
    /// run; nil otherwise, and for a forced pass. The harness only holds
    /// it: whoever wired an action may ask it what NOW is about.
    public private(set) var acting: ViewEvent?
    var droppedInARow = 0
    let actions: [any Action]
    /// Where events are recorded and the view is kept.
    public let pipeline: Pipeline
    /// Everything the state needs besides the view: the static parts, the
    /// closing line and the clock.
    let parts: () -> StateText.Parts
    let home: DispatchQueue
    let clock: @Sendable () -> Int64
    let log: (String) -> Void

    /// Called on `home` after every pass, dropped ones included.
    public var onRecord: ((Record) -> Void)?
    /// Called on `home` with every pass's `debug.jsonl` line.
    public var onDebugLine: ((String) -> Void)?

    /// The whole pass must finish within this.
    public static let deadlineMs = 1500
    /// An action taking longer than this is logged: it should hand slow work off.
    public static let actionSlowMs = 300
    /// A started action still in progress this long after its result is
    /// ended as failed (§5.1): past the longest reaction, held four times
    /// in the design with the longest loop.
    public static let pendingMaxMs: Int64 = 90_000

    var running: Int?
    /// The view events waiting for their pass, in the order they start:
    /// the highest `ViewEvent.passPriority` first, oldest first within
    /// one, so at most one at 0 waits, the newest, last.
    var waiting: [ViewEvent] = []
    /// The actions the dashboard made act while the running pass ran: the
    /// pass's state is from before, so they sit its answers out (§2).
    var changedDuringPass: Set<String> = []
    /// Each question's option names as the launch's `questions` line in
    /// `debug.jsonl` gives them (§9): a pass line names the options it
    /// asked only where they differ, such as the mood's once it has moved.
    let launchOptions: [String: [String]]
    /// The state's head as the last `head` line in `debug.jsonl` gave it.
    var loggedHead: String?

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
                parts: @escaping () -> StateText.Parts, home: DispatchQueue,
                clock: @escaping @Sendable () -> Int64, log: @escaping (String) -> Void = { _ in }) {
        self.brain = brain
        self.actions = actions
        self.pipeline = pipeline
        self.parts = parts
        self.home = home
        self.clock = clock
        self.log = log
        let keys = actions.flatMap { $0.questions().map(\.key) }
        precondition(Set(keys).count == keys.count, "question keys must be unique across actions: \(keys)")
        launchOptions = Dictionary(uniqueKeysWithValues: actions.flatMap { $0.questions() }.map { ($0.key, $0.options.map(\.name)) })
    }

    /// A new brain, from the next pass on; nil for none. Call on `home`.
    public func use(_ brain: (any Brain)?) {
        dispatchPrecondition(condition: .onQueue(home))
        self.brain = brain
        brainChanges += 1
        trouble = nil
        droppedInARow = 0
    }

    /// View events from the pipeline: a pass for each that wakes the
    /// brain. Call on `home`.
    public func take(_ views: [ViewEvent]) {
        dispatchPrecondition(condition: .onQueue(home))
        for view in views where view.wakesBrain && brain != nil {
            if running != nil {
                if let old = waiting.last, old.passPriority == 0 {
                    log("harness: \(old.name) replaced by a newer \(view.name)")
                    waiting.removeLast()
                }
                waiting.insert(view, at: waiting.firstIndex { $0.passPriority < view.passPriority } ?? waiting.endIndex)
                continue
            }
            start(view)
        }
    }

    /// Nothing running and nothing waiting. Call on `home`.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(home))
        return running == nil && waiting.isEmpty
    }

    // MARK: A pass (§3)

    /// What a pass sends, fixed when it starts on `home`, and the last
    /// event its state saw.
    struct Job: Sendable {
        var brain: any Brain
        /// `brainChanges` when it started.
        var brainChanges: Int
        var state: String
        var questions: [Question]
        var seen: Int
    }

    var nextPass = 0
    /// The running pass's deadline.
    var deadline: DispatchSourceTimer?

    /// A pass, its request off `home`. Past the deadline it's dropped, and
    /// the request goes on to its end, so the log can say when the brain
    /// did answer, with `: ` and why if it failed: a dropped pass's own
    /// latency is only the deadline's.
    func start(_ now: ViewEvent) {
        guard let brain else { return }
        nextPass += 1
        let id = nextPass
        running = id
        changedDuringPass = []
        let job = prepare(now, brain: brain)
        let started = ContinuousClock.now
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: home)
        timer.schedule(deadline: .now() + .milliseconds(Harness.deadlineMs), leeway: .milliseconds(Harness.deadlineLeewayMs))
        timer.setEventHandler { [weak self] in self?.ended(id, now, job, .failure(Harness.late), since: started) }
        deadline = timer
        timer.resume()
        Task { [self] in
            let result = await Harness.answer(job)
            home.async { [self] in
                guard running == id else {
                    let why = if case .failure(let e) = result { ": " + e.description } else { "" }
                    log("harness: \(job.brain.id) answered after \((ContinuousClock.now - started).ms) ms, too late for the "
                        + "\(now.name) pass" + why)
                    return
                }
                ended(id, now, job, result, since: started)
            }
        }
    }

    /// Pass `id` is over, answered or past its deadline. Then the next
    /// waiting view event's pass starts; each that may no longer wake the
    /// brain, by the pipeline's gate asked again (EVENTS.md §6), is
    /// dropped on the way.
    func ended(_ id: Int, _ now: ViewEvent, _ job: Job, _ result: Result<Answers, BrainError>,
               since started: ContinuousClock.Instant) {
        guard running == id else { return }
        running = nil
        deadline?.cancel()
        deadline = nil
        finish(now, job, result, latencyMs: (ContinuousClock.now - started).ms)
        changedDuringPass = []
        while running == nil, !waiting.isEmpty {
            let next = waiting.removeFirst()
            if let why = pipeline.whyNotWake(next) {
                finish(next, nil, .failure(BrainError(why)), latencyMs: 0, brainID: job.brain.id)
            } else {
                start(next)
            }
        }
    }

    /// Step 3, on `home`: the state and every action's questions.
    func prepare(_ now: ViewEvent, brain: any Brain) -> Job {
        let state = StateText.build(pipeline.view.events, now: now, at: clock(), parts())
        return Job(brain: brain, brainChanges: brainChanges, state: state, questions: actions.flatMap { $0.questions() },
                   seen: pipeline.transcript.lastSeq)
    }

    /// Steps 5–7, on `home`: each action gets its own answers, in order,
    /// and everything is recorded.
    /// A pass with no `job` never asked the brain `brainID`: a waiting
    /// view event whose pass couldn't start.
    @discardableResult
    func finish(_ now: ViewEvent, _ job: Job?, _ result: Result<Answers, BrainError>, latencyMs: Int,
                brainID: String? = nil) -> Record {
        var pass = Pass(forSeq: now.seq, answers: [:], dropped: nil, latencyMs: latencyMs)
        if job?.brainChanges == brainChanges {
            // Only a pass that asked the brain in use says how it's doing.
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
            // The head is logged only when it changes; the pass, HISTORY and NOW (§9).
            let (head, last) = StateText.split(job.state)
            if head != loggedHead, let onDebugLine {
                onDebugLine(DebugLog.head(head, at: clock()))
                loggedHead = head
            }
            extra.merge(["state": last, "questions": job.questions.map(\.key), "brain": job.brain.id, "seen": job.seen]) { $1 }
            if let options = changedOptions(job.questions) { extra["options"] = options }
        } else {
            extra["brain"] = brainID ?? brain?.id ?? "none"
        }
        logPass(pass, extra: extra)
        acting = now
        defer { acting = nil }
        let ran = pass.dropped == nil
            ? runActions(pass.answers, forSeq: now.seq, by: "brain", skipping: changedDuringPass) : []
        let record = Record(now: now, pass: pass, actions: ran, questions: job?.questions ?? [])
        if let dropped = pass.dropped { log("harness: \(now.name) dropped: \(dropped)") }
        onRecord?(record)
        return record
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
    /// its `end` is recorded (§5.1). The result's own facts go in its data
    /// too, unread; the harness's keys win a clash.
    func record(_ name: String, _ result: ActionResult, forSeq: Int?, by: String, latencyMs: Int) -> ActionRecord {
        let started = result.ok && result.pending != nil
        let data: [String: JSONValue] = ["for": forSeq.map { .int(Int64($0)) } ?? .null, "by": .string(by),
                                         "ok": .bool(result.ok), "message": .string(result.message),
                                         "latency_ms": .int(Int64(latencyMs))]
        let e = pipeline.record(Event(ts: clock(), source: .boop, type: .action, phase: started ? .start : nil,
                                      specificType: name, data: data.merging(result.facts) { mine, _ in mine }))
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
        var extra: [String: Any] = ["questions": asked.map(\.key), "by": Harness.forcedBy]
        if let options = changedOptions(asked) { extra["options"] = options }
        logPass(Pass(forSeq: nil, answers: answers, dropped: nil, latencyMs: 0), extra: extra)
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

    /// The option names of `asked` that differ from the launch's `questions`
    /// line (§9), by key, such as the mood's moves once it has moved; nil
    /// when none do. A pass line carries them, so it says what it offered.
    func changedOptions(_ asked: [Question]) -> [String: [String]]? {
        let changed = asked.filter { launchOptions[$0.key] != $0.options.map(\.name) }
        return changed.isEmpty ? nil : Dictionary(uniqueKeysWithValues: changed.map { ($0.key, $0.options.map(\.name)) })
    }

    /// A pass's `debug.jsonl` line (§9).
    func logPass(_ pass: Pass, extra: [String: Any]) {
        guard let onDebugLine else { return }
        onDebugLine(DebugLog.pass(pass, extra: extra, at: clock()))
    }

    /// One view event straight through, without the queue: for the evals.
    /// Don't call on `home`. Returns nil when it doesn't wake the brain.
    /// Past the deadline the request is cancelled.
    public func respond(to now: ViewEvent) async -> Record? {
        let job: Job? = home.sync {
            guard now.wakesBrain, let brain else { return nil }
            return prepare(now, brain: brain)
        }
        guard let job else { return nil }
        let started = ContinuousClock.now
        let result = await withTaskGroup(of: Result<Answers, BrainError>.self) { group in
            group.addTask { await Harness.answer(job) }
            group.addTask {
                do {
                    try await Task.sleep(for: .milliseconds(Harness.deadlineMs), tolerance: .milliseconds(Harness.deadlineLeewayMs))
                    return .failure(Harness.late)
                } catch {
                    return .failure(BrainError("cancelled"))
                }
            }
            let first = await group.next()!
            group.cancelAll()
            return Task.isCancelled ? .failure(BrainError("cancelled")) : first
        }
        let ms = (ContinuousClock.now - started).ms
        return home.sync { finish(now, job, result, latencyMs: ms) }
    }

    // MARK: Helpers

    /// Step 4, off `home`: the brain's answers, or why there are none.
    static func answer(_ job: Job) async -> Result<Answers, BrainError> {
        do {
            return .success(try await job.brain.answer(state: job.state, questions: job.questions,
                                                      deadline: .milliseconds(deadlineMs)))
        } catch let error as BrainError {
            return .failure(error)
        } catch {
            return .failure(BrainError("\(error)"))
        }
    }

    /// Why a pass the deadline passed is dropped.
    static var late: BrainError { BrainError("late: no answer within \(deadlineMs) ms") }

    /// How late the deadline's timer may fire: the system's default leeway
    /// let it fire up to 7% late, 1.6 s for 1.5 s.
    static let deadlineLeewayMs = 5
}

extension Duration {
    /// In whole milliseconds.
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
