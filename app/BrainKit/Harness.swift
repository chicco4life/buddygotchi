import Foundation

/// The brain kit's harness (kit/BRAIN-KIT.md): registration on both sides
/// and the log in the middle. Events come in (`emit`) and are logged;
/// registered kinds get a line from their transform; rules run at once;
/// an event that wakes the brain gets a call, whose prompt is your
/// sections, HISTORY and NOW, and whose answers go to the outputs, each
/// its own; what they did is logged too.
///
/// Everything but the brain call runs on `queue`, which the caller owns:
/// call every method there. The one thing kept in memory besides the log
/// is which call is running (§9); each event's line is worked out once
/// and kept with it (§3.1).
public final class Harness: @unchecked Sendable {
    public struct Options: Sendable {
        /// The whole call must finish within this (§9).
        public var deadlineMs = 1500
        /// How late the deadline's timer may fire.
        public var deadlineLeewayMs = 5
        /// An event older than this is never answered (§9).
        public var maxWaitMs: Int64 = 10_000
        /// HISTORY reaches back this far, or to `reachBack`, whichever is
        /// further, and holds at most `historyLimit` events (§7.2).
        public var historyMs: Int64 = 10 * 60_000
        public var historyLimit = 40
        /// An output's `run` taking longer than this is logged.
        public var actionSlowMs = 300
        /// An open `did` is ended after this, unless its output says (§5.3).
        public var openForMs: Int64 = 60_000
        /// How often `start()` ticks.
        public var tickMs = 1000
        /// How to read HISTORY and NOW, placed after your sections: the
        /// kit's own words, yours, or none (you place your own in a
        /// section) (§7.2).
        public var reading: Reading = .standard
        /// NOW's heading, from the wall clock: `14:09, Wednesday`.
        public var heading: @Sendable (Int64) -> String = Harness.heading
        /// Whether an event that wakes the brain gets a call on its own;
        /// false leaves it to `respond(to:)` (the evals).
        public var loop = true

        public init() {}
    }

    public enum Reading: Sendable, Equatable {
        case standard, none
        case custom(String)
    }

    /// The clock (§10): `now` for events' `at`, relative times and
    /// `openFor`; `wall` for NOW's heading. Both unix milliseconds.
    public struct Clock: Sendable {
        public var now: @Sendable () -> Int64
        public var wall: @Sendable () -> Int64

        public init(now: @escaping @Sendable () -> Int64, wall: (@Sendable () -> Int64)? = nil) {
            self.now = now
            self.wall = wall ?? now
        }

        public static let system = Clock(now: { Int64(Date().timeIntervalSince1970 * 1000) })
    }

    /// What one output did in a pass, and its `did`'s `seq`.
    public struct ActionRecord: Equatable, Sendable {
        public var name: String
        public var result: ActionResult
        public var latencyMs: Int
        public var seq: Int

        /// Which outputs returned a result: `mood, react (failed)`, or
        /// `nothing`.
        public static func names(_ records: [ActionRecord]) -> String {
            records.isEmpty ? "nothing" : records.map { $0.name + ($0.result.ok ? "" : " (failed)") }.joined(separator: ", ")
        }
    }

    /// One pass (§9), for `onPass`: a call to the brain, one held back when
    /// its turn came, or a forced one.
    public struct Pass: Sendable {
        /// The event it answered; nil for a forced pass.
        public var event: Event?
        /// That event's line.
        public var line: String?
        /// Its `pass` event's `seq`.
        public var seq: Int
        public var answers: Answers
        /// Why no output ran: the brain failed or was late; nil when they
        /// ran, or the event was held back.
        public var dropped: String?
        /// Why the event was held back when its turn came (§9), so the
        /// brain wasn't asked; nil when it was.
        public var held: String?
        public var latencyMs: Int
        /// The brain it asked, or would have; nil for a forced pass.
        public var brain: String?
        /// Who forced it; nil for the brain's.
        public var by: String?
        /// The prompt it sent; nil for one that asked nothing.
        public var prompt: String?
        public var questions: [Question]
        /// The log's last `seq` when its prompt was built.
        public var seen: Int
        public var actions: [ActionRecord]
        /// The brain's error, when it failed.
        public var error: BrainError?
        /// Whether it asked the brain in use now, not one `use` has
        /// replaced since.
        public var current: Bool
    }

    public let name: String
    public let log: Log
    public let options: Options
    public let clock: Clock
    let queue: DispatchQueue
    /// App log lines: the kit's own, prefixed `harness: `.
    public var note: (String) -> Void

    /// The brain in use, or nil for none: nothing wakes it.
    public private(set) var brain: (any Brain)?
    /// Bumped by every `use`: a call that asked an earlier brain says
    /// nothing of this one.
    var generation = 0

    /// Every line worked out, as each event is emitted (§3.1): `onLine`.
    public var onLine: ((Event, Line, Bool) -> Void)?
    /// Every pass, after its outputs ran.
    public var onPass: ((Pass) -> Void)?

    // Registration.
    struct Input {
        var wake: Int?
        var hold: ((Event, LogView) -> String?)?
        var transform: ((Event, LogView) -> Line?)?
    }
    var inputs: [String: Input] = [:]
    var rules: [(kind: String, run: (Event) -> Void)] = []
    struct Output {
        var action: any Action
        var openForMs: Int64
    }
    var outputs: [Output] = []
    var sections: [(LogView) -> String?] = []
    var closingLine: ((Int64, LogView) -> String?)?
    var reachBackTo: ((Int64, LogView) -> Int64?)?
    var checks: [(Int64, LogView) -> Event?] = []

    // Worked out from the log, kept with it.
    /// Each event's line, by `seq`.
    var lines: [Int: Line] = [:]
    /// `did`s for no event, by the event they show under: the latest with
    /// a line before them (§5.2).
    var loose: [Int: [Int]] = [:]
    /// The latest event with a line.
    var lastLined: Int?

    // The loop's own (§9).
    var running: (id: Int, seq: Int)?
    var nextPass = 0
    var deadline: DispatchSourceTimer?
    var timer: DispatchSourceTimer?
    /// Emits under way: nothing wakes the brain until the outermost ends,
    /// so its rules and outputs have all run first.
    var depth = 0
    /// Outputs that acted outside a pass while one ran: they sit its
    /// answers out (§5.4).
    var changedDuringPass: Set<String> = []
    /// Stale events already noted, so each is noted once.
    var notedStale: Set<Int> = []

    public init(name: String, brain: (any Brain)?, log: Log, clock: Clock = .system, queue: DispatchQueue,
                options: Options = Options(), note: @escaping (String) -> Void = { _ in }) {
        self.name = name
        self.brain = brain
        self.log = log
        self.clock = clock
        self.queue = queue
        self.options = options
        self.note = note
    }

    // MARK: - Registration (§3–7, §10)

    /// A kind with a line: `wake` its priority (nil: it never wakes the
    /// brain), `transform` its line from the event and the log before it.
    public func input(_ kind: String, wake: Int? = nil, _ transform: @escaping (Event, LogView) -> Line?) {
        inputs[kind] = Input(wake: wake, hold: inputs[kind]?.hold, transform: transform)
    }

    /// A kind with no transform: its events show their own `line`, or
    /// their data (`hold: secs 2`).
    public func input(_ kind: String, wake: Int? = nil) {
        inputs[kind] = Input(wake: wake, hold: inputs[kind]?.hold, transform: nil)
    }

    /// A check for `kind`, asked when one of its events' turn to wake the
    /// brain comes (§9): a reason to hold it back, or nil. It can read your
    /// live state as well as the log.
    public func hold(_ kind: String, _ check: @escaping (Event, LogView) -> String?) {
        var input = inputs[kind] ?? Input(wake: nil, hold: nil, transform: nil)
        input.hold = check
        inputs[kind] = input
    }

    /// Registers kinds from a JSON object: `{"kind": {"line": "… {field} …",
    /// "wake": 1}}` (§3.2).
    public func load(_ url: URL) throws {
        guard let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw SteeringError("\(url.lastPathComponent) isn't a JSON object")
        }
        for (kind, raw) in o {
            guard let spec = raw as? [String: Any] else { throw SteeringError("\(url.lastPathComponent): \(kind) isn't an object") }
            let wake = (spec["wake"] as? NSNumber)?.intValue
            if let template = spec["line"] as? String {
                input(kind, wake: wake) { e, _ in Line(Harness.fill(template, e)) }
            } else {
                input(kind, wake: wake)
            }
        }
    }

    /// `{field}` filled from the event's data; a field it hasn't is left.
    public static func fill(_ template: String, _ e: Event) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let key = String(rest[rest.index(after: open)..<close])
            switch e[key] {
            case .string(let s)?: out += s
            case .int(let n)?: out += String(n)
            case .double(let d)?: out += String(d)
            case .bool(let b)?: out += String(b)
            default: out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// A rule: runs at once on every event of `kind` (`*` for every
    /// event), right after it's logged and before the brain hears of it.
    public func on(_ kind: String, _ rule: @escaping (Event) -> Void) {
        rules.append((kind, rule))
    }

    /// An output; they run in registration order. What it starts is ended
    /// after `openFor` if nothing ends it first.
    public func output(_ action: any Action, openFor: Int64? = nil) {
        outputs.append(Output(action: action, openForMs: openFor ?? options.openForMs))
    }

    /// The outputs, in the order they run.
    public var actions: [any Action] { outputs.map(\.action) }

    /// A section of the prompt, built for every call; nil or empty is left out.
    public func section(_ build: @escaping (LogView) -> String?) { sections.append(build) }

    /// The line that closes HISTORY, if any.
    public func closing(_ build: @escaping (Int64, LogView) -> String?) { closingLine = build }

    /// How far back HISTORY reaches at least, if further than `historyMs`.
    public func reachBack(_ build: @escaping (Int64, LogView) -> Int64?) { reachBackTo = build }

    /// A timed check, run on every tick: an event to emit, or nil.
    public func tick(_ check: @escaping (Int64, LogView) -> Event?) { checks.append(check) }

    /// A new brain, from the next call on; nil for none.
    public func use(_ brain: (any Brain)?) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.brain = brain
        generation += 1
        wake()
    }

    // MARK: - In (§3.3, §4)

    /// Logs an event, works out its line, runs the rules for it, and wakes
    /// the brain if it should. Returns it as logged.
    @discardableResult
    public func emit(_ event: Event) -> Event {
        dispatchPrecondition(condition: .onQueue(queue))
        depth += 1
        let e = log.append(event, now: clock.now())
        place(e)
        if let line = lines[e.seq] { onLine?(e, line, wakes(e)) }
        for rule in rules where rule.kind == e.kind || rule.kind == "*" { rule.run(e) }
        depth -= 1
        if depth == 0 { wake() }
        return e
    }

    /// Runs `body`, which may emit several events and run your own rules,
    /// and only then wakes the brain: for an app whose rules need more than
    /// the event (§4).
    public func batch(_ body: () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        depth += 1
        body()
        depth -= 1
        if depth == 0 { wake() }
    }

    @discardableResult
    public func emit(source: String, kind: String, data: [String: JSONValue] = [:], line: String? = nil) -> Event {
        emit(Event(source: source, kind: kind, line: line, data: data))
    }

    /// What a rule did (§4): its whole line, for its event.
    @discardableResult
    public func did(_ message: String, for e: Event?, action: String, by: String = "rule",
                    facts: [String: JSONValue] = [:]) -> Event {
        emit(Event.did(message, for: e?.seq, action: action, by: by, facts: facts))
    }

    /// An event's line, and where a `did` for no event shows: worked out
    /// once, in order, as it's emitted or read back.
    func place(_ e: Event) {
        if e.isKit {
            if e.kind == Event.did, e.about == nil, let target = lastLined { loose[target, default: []].append(e.seq) }
            return
        }
        guard let input = inputs[e.kind] else { return }
        let line: Line?
        if let transform = input.transform {
            line = transform(e, log.view(before: e))
        } else {
            line = e.line.map { Line($0) } ?? Line.fallback(e)
        }
        guard let line else { return }
        lines[e.seq] = line
        lastLined = e.seq
        if lines.count > log.events.count + 1000, let first = log.events.first?.seq {
            lines = lines.filter { $0.key >= first }
            loose = loose.filter { $0.key >= first }
        }
    }

    /// The line worked out for the event `seq`, if it has one.
    public func line(_ seq: Int) -> Line? { lines[seq] }

    /// Whether `e` is of a kind that wakes the brain and has a line.
    public func wakes(_ e: Event) -> Bool { inputs[e.kind]?.wake != nil && lines[e.seq] != nil }

    /// Reads the log back at launch (§2.3): every event's line in order,
    /// and any `did` the last launch left open ended as `restarted`. The
    /// rules don't run for what's read back. Returns the events read.
    @discardableResult
    public func resume() -> ArraySlice<Event> {
        dispatchPrecondition(condition: .onQueue(queue))
        let read = log.load(now: clock.now())
        for e in read { place(e) }
        depth += 1
        for seq in log.openDids.sorted() {
            guard let d = log.event(seq) else { continue }
            emit(Event.ended(seq, action: d.action ?? "", by: d["by"]?.string ?? "brain", failed: Harness.restarted))
        }
        depth -= 1
        return read
    }

    /// Why an open `did` from before a relaunch ended.
    public static let restarted = "restarted"

    // MARK: - The prompt (§7)

    /// The whole prompt for a call about `e`, as of now.
    public func prompt(for e: Event) -> String {
        let now = clock.now()
        let view = log.view(now: now)
        var parts = sections.compactMap { $0(view) }.filter { !$0.isEmpty }
        switch options.reading {
        case .standard: parts.append(Harness.reading(name))
        case .custom(let text): parts.append(text)
        case .none: break
        }
        parts.append(history(before: e, now: now, view: view))
        parts.append(nowSection(e))
        return parts.joined(separator: "\n\n")
    }

    /// The kit's own words on how to read HISTORY and NOW.
    public static func reading(_ name: String) -> String {
        """
        How to read HISTORY and NOW:
        - HISTORY is oldest first. Each line says how long ago it happened.
          Lines indented under it add to it: its notes, then what \(name) did.
          A line of what \(name) did ending in (in progress) hasn't finished yet.
        - NOW is what to react to. Its last line is what \(name) already did on
          its own, by reflex.
        """
    }

    public static let historyHeading = "HISTORY (oldest first; indented lines add to the line above)"

    /// HISTORY for a call about `e` at `now` (§7.2).
    func history(before e: Event, now: Int64, view: LogView) -> String {
        let from = min(now - options.historyMs, reachBackTo?(now, view) ?? Int64.max)
        let inRange = log.events.filter { $0.seq < e.seq && $0.at >= from && lines[$0.seq] != nil }
        let picked = inRange.dropLast(options.historyLimit).filter { didLines($0.seq).contains { $0.open } }
            + inRange.suffix(options.historyLimit)
        var out = [Harness.historyHeading]
        for ev in picked {
            let line = lines[ev.seq]!
            out.append("\(Harness.ago(now - ev.at)): \(line.text)")
            for note in line.notes { out.append("  " + note) }
            for d in didLines(ev.seq) { out.append("  " + d.text) }
        }
        if let closing = closingLine?(now, view) { out.append(closing) }
        return out.joined(separator: "\n")
    }

    /// What was done about the event `seq`, in order (§5.2): a `did` that's
    /// `ok`, marked in progress while open; one that failed, or ended
    /// failed, left out.
    func didLines(_ seq: Int) -> [(text: String, open: Bool)] {
        let dids = (log.dids(for: seq) + (loose[seq] ?? []).compactMap(log.event)).sorted { $0.seq < $1.seq }
        return dids.compactMap { d in
            guard d["ok"]?.bool == true, let message = d["message"]?.string else { return nil }
            guard d["open"]?.bool == true else { return (message, false) }
            guard let end = log.ended(d.seq) else { return (message + " (in progress)", true) }
            return end["outcome"]?.string == "done" ? (message, false) : nil
        }
    }

    /// NOW: its heading, its line and notes, and what the rules did.
    func nowSection(_ e: Event) -> String {
        let line = lines[e.seq] ?? Line(e.line ?? e.kind)
        let reflex = log.dids(for: e.seq).filter { $0["by"]?.string == "rule" && $0["ok"]?.bool == true }
            .compactMap { $0["message"]?.string }
        return (["NOW (\(options.heading(clock.wall())))", line.text] + line.notes.map { "  " + $0 }
            + (reflex.isEmpty ? ["\(name) did nothing on its own."] : reflex)).joined(separator: "\n")
    }

    /// `just now`, `9 min ago`, `2 h ago`.
    public static func ago(_ ms: Int64) -> String {
        ms < 60_000 ? "just now" : ms < 60 * 60_000 ? "\(ms / 60_000) min ago" : "\(ms / 3_600_000) h ago"
    }

    /// `14:09, Wednesday`, in the Mac's time zone.
    public static let heading: @Sendable (Int64) -> String = { ms in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm, EEEE"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    // MARK: - The loop (§9)

    /// Nothing running and nothing waiting.
    public var idle: Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        return running == nil && next() == nil
    }

    func wake(_ e: Event) -> Int { inputs[e.kind]?.wake ?? 0 }

    /// The event the brain answers next, worked out from the log: of those
    /// that wake it, have a line, have no `pass` yet, aren't running and
    /// are under `maxWaitMs` old, the highest `wake`, oldest first within
    /// it; one at 0 gives way to any newer one that wakes the brain,
    /// answered or not.
    func next() -> Event? {
        let now = clock.now()
        let recent = log.view(now: now).recent(within: options.maxWaitMs).filter { !$0.isKit && wakes($0) }
        let waiting = recent.filter { !log.answered($0.seq) && $0.seq != running?.seq }
        var live: [Event] = []
        for e in waiting {
            if wake(e) == 0, let newer = recent.last(where: { $0.seq > e.seq }) {
                if notedStale.insert(e.seq).inserted { note("harness: \(e.kind) passed over for a newer \(newer.kind)") }
                continue
            }
            live.append(e)
        }
        return live.max { (wake($0), -$0.seq) < (wake($1), -$1.seq) }
    }

    /// Starts a call for the next event, if the brain is free: one held
    /// back when its turn came is logged as a dropped pass, and the next
    /// is tried.
    func wake() {
        guard depth == 0, options.loop, running == nil, let brain else { return }
        while running == nil, let e = next() {
            let view = log.view(now: clock.now())
            if let why = inputs[e.kind]?.hold?(e, view) {
                finish(e, nil, .success([:]), latencyMs: 0, brainID: brain.id, held: why)
                continue
            }
            start(e, brain)
        }
    }

    /// What a call sends, fixed when it starts.
    struct Job: Sendable {
        var brain: any Brain
        var generation: Int
        var prompt: String
        var questions: [Question]
        /// Each output's question keys, in order.
        var keys: [[String]]
        var seen: Int
    }

    /// The prompt and every output's questions for a call about `e`.
    func prepare(_ e: Event, _ brain: any Brain) -> Job {
        let view = log.view(now: clock.now())
        let asked = outputs.map { $0.action.questions(now: e, log: view) }
        let questions = asked.flatMap { $0 }
        let keys = questions.map(\.key)
        precondition(Set(keys).count == keys.count, "question keys must be unique across outputs: \(keys)")
        return Job(brain: brain, generation: generation, prompt: prompt(for: e), questions: questions,
                   keys: asked.map { $0.map(\.key) }, seen: log.lastSeq)
    }

    /// A call, its request off the queue. Past the deadline it's dropped,
    /// and the request goes on to its end, so the log can say when the
    /// brain did answer.
    func start(_ e: Event, _ brain: any Brain) {
        nextPass += 1
        let id = nextPass
        running = (id, e.seq)
        changedDuringPass = []
        let job = prepare(e, brain)
        let started = ContinuousClock.now
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(options.deadlineMs), leeway: .milliseconds(options.deadlineLeewayMs))
        timer.setEventHandler { [weak self] in self?.ended(id, e, job, .failure(self?.late ?? BrainError("late")), since: started) }
        deadline = timer
        timer.resume()
        let deadlineMs = options.deadlineMs
        Task { [self] in
            let result = await Harness.answer(job, deadlineMs: deadlineMs)
            queue.async { [self] in
                guard running?.id == id else {
                    let why = if case .failure(let error) = result { ": " + error.description } else { "" }
                    note("harness: \(job.brain.id) answered after \((ContinuousClock.now - started).ms) ms, too late for the "
                         + "\(e.kind) pass" + why)
                    return
                }
                ended(id, e, job, result, since: started)
            }
        }
    }

    /// Call `id` is over, answered or past its deadline; then the next.
    func ended(_ id: Int, _ e: Event, _ job: Job, _ result: Result<Answers, BrainError>, since started: ContinuousClock.Instant) {
        guard running?.id == id else { return }
        running = nil
        deadline?.cancel()
        deadline = nil
        finish(e, job, result, latencyMs: (ContinuousClock.now - started).ms)
        changedDuringPass = []
        wake()
    }

    /// Why a call past its deadline is dropped.
    var late: BrainError { BrainError("late: no answer within \(options.deadlineMs) ms") }

    /// Logs a pass and, unless it was dropped or held, hands each output
    /// its own answers, in order, logging what each did. A pass with no
    /// `job` asked nothing: its event was `held` back.
    @discardableResult
    func finish(_ e: Event, _ job: Job?, _ result: Result<Answers, BrainError>, latencyMs: Int,
                brainID: String? = nil, held: String? = nil) -> Pass {
        depth += 1
        var answers: Answers = [:]
        var dropped: String?
        var error: BrainError?
        switch result {
        case .failure(let failure):
            dropped = failure.description
            error = failure
            if let raw = failure.raw, let job { note("harness: \(job.brain.id) answered what couldn't be used (\(raw.count) bytes)") }
        case .success(let got):
            answers = got
        }
        let brainID = job?.brain.id ?? brainID ?? brain?.id ?? "none"
        var data: [String: JSONValue] = ["for": .int(Int64(e.seq)), "brain": .string(brainID), "answers": Harness.json(answers),
                                         "dropped": .of(dropped), "ms": .int(Int64(latencyMs))]
        if let held { data["held"] = .string(held) }
        let passEvent = emit(Event(source: Event.kit, kind: Event.pass, data: data))
        if let dropped { note("harness: \(e.kind) dropped: \(dropped)") }
        if let held { note("harness: \(e.kind) held: \(held)") }
        let ran = dropped == nil && held == nil
            ? runOutputs(answers, keys: job?.keys, now: e, by: "brain", skipping: changedDuringPass) : []
        depth -= 1
        let pass = Pass(event: e, line: lines[e.seq]?.text, seq: passEvent.seq, answers: answers, dropped: dropped, held: held, latencyMs: latencyMs, brain: brainID,
                        by: nil, prompt: job?.prompt, questions: job?.questions ?? [], seen: job?.seen ?? log.lastSeq,
                        actions: ran, error: job == nil ? nil : error, current: job?.generation == generation)
        onPass?(pass)
        return pass
    }

    /// Answers as the `pass` event keeps them: each key's `choice`, and
    /// `p`, every option's probability to three places.
    public static func json(_ answers: Answers) -> JSONValue {
        .object(answers.mapValues { a in
            ["choice": .string(a.choice), "p": .object(a.probabilities.mapValues { .double(($0 * 1000).rounded() / 1000) })]
        })
    }

    /// Hands each output its own answers, in order, and logs what each
    /// reports. `keys` are each output's question keys as they were asked;
    /// nil asks them again. The ones in `skipping` sit out.
    func runOutputs(_ answers: Answers, keys: [[String]]?, now: Event?, by: String,
                    skipping: Set<String> = []) -> [ActionRecord] {
        var ran: [ActionRecord] = []
        for (i, output) in outputs.enumerated() {
            let action = output.action
            if skipping.contains(action.name) {
                note("harness: \(action.name) sat out the pass: it changed while the pass ran")
                continue
            }
            let view = log.view(now: clock.now())
            let own = keys?[i] ?? action.questions(now: now, log: view).map(\.key)
            let mine = Dictionary(uniqueKeysWithValues: own.compactMap { k in answers[k].map { (k, $0) } })
            let started = ContinuousClock.now
            let result = action.run(mine, now: now, log: view)
            let ms = (ContinuousClock.now - started).ms
            if ms > options.actionSlowMs { note("harness: \(action.name) took \(ms) ms; slow work should be handed off") }
            guard let result else { continue }
            ran.append(record(action.name, result, for: now?.seq, by: by, latencyMs: ms))
        }
        return ran
    }

    /// Logs a result as a `did`: open while what it started plays, its
    /// handle bound to end it.
    func record(_ name: String, _ result: ActionResult, for about: Int?, by: String, latencyMs: Int) -> ActionRecord {
        let started = result.ok && result.pending != nil
        let facts = result.facts.merging(["latency_ms": .int(Int64(latencyMs))]) { _, mine in mine }
        let d = emit(Event.did(result.message, for: about, action: name, by: by, ok: result.ok, open: started, facts: facts))
        if started, let pending = result.pending {
            pending.bind { [weak self] end in self?.settle(d.seq, end) }
        }
        return ActionRecord(name: name, result: result, latencyMs: latencyMs, seq: d.seq)
    }

    /// Ends an open `did`; one already ended is left alone.
    func settle(_ seq: Int, _ end: Pending.End) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard log.openDids.contains(seq), let d = log.event(seq) else { return }
        let why: String? = if case .failed(let why) = end { why } else { nil }
        emit(Event.ended(seq, action: d.action ?? "", by: d["by"]?.string ?? "brain", failed: why))
    }

    // MARK: - The tick (§10)

    /// Starts ticking every `tickMs` on the queue.
    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(options.tickMs), repeating: .milliseconds(options.tickMs))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One tick: ends every `did` open past its output's `openFor`, then
    /// runs the timed checks, emitting what they return.
    public func tick() {
        dispatchPrecondition(condition: .onQueue(queue))
        let now = clock.now()
        depth += 1
        for seq in log.openDids.sorted() {
            guard let d = log.event(seq) else { continue }
            let openFor = outputs.first { $0.action.name == d.action }?.openForMs ?? options.openForMs
            guard now - d.at >= openFor else { continue }
            note("harness: \(d.action ?? "?") was still in progress after \(now - d.at) ms; ended it")
            emit(Event.ended(seq, action: d.action ?? "", by: d["by"]?.string ?? "brain", failed: Harness.noWord))
        }
        for check in checks {
            if let e = check(now, log.view(now: now)) { emit(e) }
        }
        depth -= 1
        wake()
    }

    /// Why a `did` open past its `openFor` ended.
    public static let noWord = "no word it finished"

    // MARK: - Forced (§5.4)

    /// A pass whose answers are given, not asked: each choice at
    /// probability 1, handed to the outputs as the brain's would be, for
    /// no event. A choice that isn't one of its question's options is left
    /// out.
    @discardableResult
    public func force(_ choices: [String: String], by: String) -> [ActionRecord] {
        dispatchPrecondition(condition: .onQueue(queue))
        let view = log.view(now: clock.now())
        let asked = outputs.flatMap { $0.action.questions(now: nil, log: view) }
            .filter { q in q.options.contains { $0.name == choices[q.key] } }
        let answers = Dictionary(uniqueKeysWithValues: asked.compactMap { q in
            choices[q.key].map { (q.key, Answer(choice: $0, probabilities: [$0: 1])) }
        })
        if answers.count < choices.count { note("harness: forced answers left out: \(Set(choices.keys).subtracting(answers.keys).sorted())") }
        depth += 1
        let passEvent = emit(Event(source: Event.kit, kind: Event.pass,
                                   data: ["for": .null, "by": .string(by), "answers": Harness.json(answers), "dropped": .null,
                                          "ms": 0]))
        let ran = runOutputs(answers, keys: nil, now: nil, by: by)
        depth -= 1
        for a in ran where a.result.ok { changedOutside(a.name) }
        onPass?(Pass(event: nil, line: nil, seq: passEvent.seq, answers: answers, dropped: nil, held: nil, latencyMs: 0, brain: nil, by: by, prompt: nil,
                     questions: asked, seen: log.lastSeq, actions: ran, error: nil, current: true))
        wake()
        return ran
    }

    /// One output acting outside any pass, such as a value set from a
    /// dashboard: its result is logged for no event.
    @discardableResult
    public func force(_ action: any Action, by: String, _ body: () -> ActionResult?) -> ActionResult? {
        dispatchPrecondition(condition: .onQueue(queue))
        let started = ContinuousClock.now
        guard let result = body() else { return nil }
        _ = record(action.name, result, for: nil, by: by, latencyMs: (ContinuousClock.now - started).ms)
        if result.ok { changedOutside(action.name) }
        return result
    }

    func changedOutside(_ name: String) {
        if running != nil { changedDuringPass.insert(name) }
    }

    // MARK: - One event, straight through

    /// One event's call without the loop, for evals: nil when it doesn't
    /// wake the brain, there's no brain, or it's held back. Don't call on
    /// the queue. Past the deadline the request is cancelled.
    public func respond(to e: Event) async -> Pass? {
        let job: Job? = queue.sync {
            guard wakes(e), let brain, inputs[e.kind]?.hold?(e, log.view(now: clock.now())) == nil else { return nil }
            return prepare(e, brain)
        }
        guard let job else { return nil }
        let started = ContinuousClock.now
        let deadlineMs = options.deadlineMs, leeway = options.deadlineLeewayMs, late = self.late
        let result = await withTaskGroup(of: Result<Answers, BrainError>.self) { group in
            group.addTask { await Harness.answer(job, deadlineMs: deadlineMs) }
            group.addTask {
                do {
                    try await Task.sleep(for: .milliseconds(deadlineMs), tolerance: .milliseconds(leeway))
                    return .failure(late)
                } catch {
                    return .failure(BrainError("cancelled"))
                }
            }
            let first = await group.next()!
            group.cancelAll()
            return Task.isCancelled ? .failure(BrainError("cancelled")) : first
        }
        let ms = (ContinuousClock.now - started).ms
        return queue.sync { finish(e, job, result, latencyMs: ms) }
    }

    /// The brain's answers, or why there are none.
    static func answer(_ job: Job, deadlineMs: Int) async -> Result<Answers, BrainError> {
        do {
            return .success(try await job.brain.answer(state: job.prompt, questions: job.questions,
                                                      deadline: .milliseconds(deadlineMs)))
        } catch let error as BrainError {
            return .failure(error)
        } catch {
            return .failure(BrainError("\(error)"))
        }
    }
}

extension Duration {
    /// In whole milliseconds.
    public var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
