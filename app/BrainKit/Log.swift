import Foundation

/// The log (kit/BRAIN-KIT.md §2.3): every event, in order, append-only,
/// the only state the kit keeps. With a folder, each event is written as
/// it's appended to `<folder>/<day>.jsonl`, one file a day, and a launch
/// reads the files back; the last `keepMs` of events are kept in memory,
/// indexed for looking back. Without one (tests) it's in memory only.
/// Touched only on its owner's queue.
public final class Log: @unchecked Sendable {
    public struct Options: Sendable {
        /// Days of files kept, today included; older ones are deleted at
        /// launch and at each new day.
        public var keptDays = 14
        /// How far back events are kept in memory.
        public var keepMs: Int64 = 24 * 60 * 60 * 1000
        /// The day an event's file is named for: `yyyy-MM-dd`, in the
        /// Mac's time zone by default.
        public var day: @Sendable (Int64) -> String = Log.localDay
        /// Reads a line that isn't the log's own shape, such as an older
        /// app's; nil skips it.
        public var decode: (@Sendable (Substring) -> Event?)?

        public init() {}
    }

    public let folder: URL?
    public let options: Options
    let note: (String) -> Void

    /// The events in memory, oldest first: the last `keepMs` of them.
    public private(set) var events: [Event] = []
    /// The newest event's `seq`, or 0 before the first.
    public private(set) var lastSeq = 0
    /// Each kind's events, by `seq`, oldest first.
    var byKind: [String: [Int]] = [:]
    /// The kit's own events by what they're `for` (§2.2): `did`s by their
    /// event, `ended` by its `did`, and which events have a `pass`.
    var didsFor: [Int: [Int]] = [:]
    var endedFor: [Int: Int] = [:]
    var passed: Set<Int> = []
    /// The `did`s still open: `open`, with no `ended` yet (§5.3).
    public private(set) var openDids: Set<Int> = []

    public init(folder: URL? = nil, options: Options = Options(), note: @escaping (String) -> Void = { _ in }) {
        self.folder = folder
        self.options = options
        self.note = note
    }

    /// `yyyy-MM-dd` in the Mac's time zone.
    public static let localDay: @Sendable (Int64) -> String = { ms in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// The file for the day of `at`.
    public func file(for at: Int64) -> URL? {
        folder?.appendingPathComponent(options.day(at) + ".jsonl")
    }

    /// Logs an event: the next `seq`, and `now` as its `at` if it has none.
    @discardableResult
    public func append(_ event: Event, now: Int64) -> Event {
        var e = event
        lastSeq += 1
        e.seq = lastSeq
        if e.at == 0 { e.at = now }
        if let url = file(for: e.at) { LineFile.append(e.jsonLine, to: url) }
        keep(e)
        trim(now: e.at)
        return e
    }

    /// Keeps `e` in memory, indexed.
    func keep(_ e: Event) {
        events.append(e)
        byKind[e.kind, default: []].append(e.seq)
        if e.kind == Event.did, e.source == Event.kit, e["open"]?.bool == true, e["ok"]?.bool != false { openDids.insert(e.seq) }
        guard e.source == Event.kit, let about = e.about else { return }
        switch e.kind {
        case Event.did:
            didsFor[about, default: []].append(e.seq)
        case Event.ended:
            if endedFor[about] == nil { endedFor[about] = e.seq }
            openDids.remove(about)
        case Event.pass:
            passed.insert(about)
        default:
            break
        }
    }

    /// Lets go of the events older than `keepMs`, now and then: once the
    /// oldest is an hour past it, so it isn't every append.
    func trim(now: Int64) {
        guard let first = events.first, now - first.at > options.keepMs + 3_600_000 else { return }
        let cut = events.firstIndex { now - $0.at <= options.keepMs } ?? events.count
        let gone = events[..<cut]
        let last = gone.last?.seq ?? 0
        events.removeFirst(cut)
        for (kind, seqs) in byKind {
            let kept = seqs.drop { $0 <= last }
            byKind[kind] = kept.isEmpty ? nil : Array(kept)
        }
        didsFor = didsFor.filter { $0.key > last }
        endedFor = endedFor.filter { $0.key > last }
        passed = passed.filter { $0 > last }
        openDids = openDids.filter { $0 > last }
    }

    /// The days that have a file, oldest first.
    func days() -> [String] {
        guard let folder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(".jsonl".count)) }.sorted()
    }

    /// Deletes the files older than `keptDays` as of `now`: at launch, and
    /// at each new day.
    public func prune(now: Int64) {
        guard let folder else { return }
        let oldest = options.day(now - Int64(options.keptDays - 1) * 24 * 3_600_000)
        for day in days() where day < oldest {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(day + ".jsonl"))
            note("log: deleted \(day).jsonl, older than \(options.keptDays) days")
        }
    }

    /// Reads the files back as of `now`, after pruning: the events of the
    /// last `keepMs` into memory, in order, and `seq` on from the newest
    /// file's last event. Returns the events read into memory. A line
    /// that doesn't parse, such as one a crash cut short, is skipped, even
    /// when the cut is inside a character.
    @discardableResult
    public func load(now: Int64) -> ArraySlice<Event> {
        guard let folder else { return events[...] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prune(now: now)
        let days = days()
        let from = now - options.keepMs
        let oldestRead = options.day(from)
        let start = events.count
        for day in days {
            let name = day + ".jsonl"
            // An older file is read only if it's the newest, for `seq`.
            let url = folder.appendingPathComponent(name)
            guard day >= oldestRead || day == days.last, let data = try? Data(contentsOf: url) else { continue }
            // Decoded leniently: a torn character spoils only its own line.
            let text = String(decoding: data, as: UTF8.self)
            // A line a crash cut short is ended, so the next one written
            // isn't glued to it and lost with it.
            if !text.isEmpty, !text.hasSuffix("\n") { LineFile.append("", to: url) }
            var skipped = 0
            for line in text.split(separator: "\n") {
                // What each line's parse leaves is let go at once: a launch
                // reads thousands, before any run loop drains a pool.
                autoreleasepool {
                    guard let e = Event(jsonLine: line) ?? options.decode?(line) else { skipped += 1; return }
                    lastSeq = max(lastSeq, e.seq)
                    guard e.at >= from, e.seq > (events.last?.seq ?? 0) else { return }
                    keep(e)
                }
            }
            if skipped > 0 { note("log: skipped \(skipped) unreadable line(s) in \(name)") }
        }
        return events[start...]
    }

    // MARK: Looking back

    /// Everything so far, at `now`.
    public func view(now: Int64) -> LogView { LogView(log: self, upTo: Int.max, now: now) }

    /// Everything before `e`, at its time: a transform's view (§2.4).
    public func view(before e: Event) -> LogView { LogView(log: self, upTo: e.seq, now: e.at) }

    /// Where the event with `seq` is in memory, or nil.
    func index(of seq: Int) -> Int? {
        var lo = 0, hi = events.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = events[mid].seq
            if s == seq { return mid }
            if s < seq { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// The first index whose event's `seq` is over `seq`.
    func index(after seq: Int) -> Int {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].seq <= seq { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public func event(_ seq: Int) -> Event? { index(of: seq).map { events[$0] } }

    /// The `did`s for the event `seq`, in order.
    public func dids(for seq: Int) -> [Event] { (didsFor[seq] ?? []).compactMap(event) }

    /// How the `did` `seq` ended, or nil while it hasn't.
    public func ended(_ did: Int) -> Event? { endedFor[did].flatMap(event) }

    /// Whether the event `seq` has a `pass`.
    public func answered(_ seq: Int) -> Bool { passed.contains(seq) }
}

/// A read-only view of the log (kit/BRAIN-KIT.md §2.4): everything so far,
/// or, for a transform, everything before its event.
public struct LogView {
    let log: Log
    /// Events at or after this `seq` aren't in view.
    public let upTo: Int
    /// The event's `at`, or the clock.
    public let now: Int64

    /// The events in view, oldest first.
    public var events: ArraySlice<Event> { log.events[..<log.index(after: upTo - 1)] }

    public func event(_ seq: Int) -> Event? { seq < upTo ? log.event(seq) : nil }

    /// Every event after `seq`, of any kind, oldest first.
    public func events(after seq: Int) -> ArraySlice<Event> {
        log.events[log.index(after: seq)..<log.index(after: upTo - 1)]
    }

    /// Every event at or after `now - ms`, oldest first.
    public func recent(within ms: Int64) -> ArraySlice<Event> {
        let all = events
        let from = all.lastIndex { $0.at < now - ms }.map { $0 + 1 } ?? all.startIndex
        return all[from...]
    }

    /// The `seq`s of `kind`'s events in view, oldest first.
    func seqs(_ kind: String) -> ArraySlice<Int> {
        let all = log.byKind[kind] ?? []
        var lo = 0, hi = all.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if all[mid] < upTo { lo = mid + 1 } else { hi = mid }
        }
        return all[..<lo]
    }

    /// The newest event of `kind` in view that matches.
    public func last(_ kind: String, where match: ((Event) -> Bool)? = nil) -> Event? {
        for seq in seqs(kind).reversed() {
            guard let e = log.event(seq) else { continue }
            if match?(e) ?? true { return e }
        }
        return nil
    }

    /// Every event of `kind` in view after `since` (everything, for nil)
    /// that matches, oldest first.
    public func all(_ kind: String, since: Event? = nil, where match: ((Event) -> Bool)? = nil) -> [Event] {
        let after = since?.seq ?? 0
        return seqs(kind).filter { $0 > after }.compactMap(log.event).filter { match?($0) ?? true }
    }

    public func count(_ kind: String, since: Event? = nil, where match: ((Event) -> Bool)? = nil) -> Int {
        guard since != nil || match != nil else { return seqs(kind).count }
        return all(kind, since: since, where: match).count
    }

    /// How many of `kind` in view came at or after `now - ms`.
    public func count(_ kind: String, within ms: Int64) -> Int {
        seqs(kind).reversed().prefix { log.event($0).map { $0.at >= now - ms } ?? false }.count
    }

    /// The `did`s for the event `seq`, in order: those in the log so far,
    /// whatever the view's cut.
    public func dids(for seq: Int) -> [Event] { log.dids(for: seq) }

    /// How the `did` `seq` ended, if it has, as the log has it so far.
    public func ended(_ did: Int) -> Event? { log.ended(did) }

    /// Whether the event `seq` has a `pass`.
    public func answered(_ seq: Int) -> Bool { log.answered(seq) }
}
