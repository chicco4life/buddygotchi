import Foundation

/// Boop's record of what happened and what it did (harness/HARNESS.md §5):
/// every raw event, in order, append-only. The view is folded from it, and
/// the state from the view. With a folder, each event is written as a line
/// to `<folder>/<date>.jsonl`, one file per day, and a launch reads the
/// last days back into the view; nothing else is kept in memory. Without
/// one (tests, the evals), the events are kept in memory instead. Touched
/// only on the runtime's queue.
public final class Transcript: @unchecked Sendable {
    /// Days of files kept; older ones are deleted at launch and each new day.
    public static let keptDays = 14
    /// Days read back at launch, for the view and the core to pick up from.
    public static let replayDays = 2
    /// The folder in the state directory.
    public static let folderName = "transcript"

    /// Every event, oldest first, when there's no folder; with one, none.
    public private(set) var events: [Event] = []
    /// The newest event's `seq`, or 0 before the first.
    public private(set) var lastSeq = 0
    let folder: URL?
    let time: LocalTime
    let log: (String) -> Void

    /// With no folder, it's kept in memory only.
    public init(folder: URL? = nil, time: LocalTime = LocalTime(), log: @escaping (String) -> Void = { _ in }) {
        self.folder = folder
        self.time = time
        self.log = log
    }

    /// The file for the day of `ts`.
    public func file(for ts: Int64) -> URL? {
        folder?.appendingPathComponent(time.day(ts) + ".jsonl")
    }

    /// Stamps the event with the next `seq`, and writes its line or keeps it.
    @discardableResult
    public func append(_ event: Event) -> Event {
        var e = event
        lastSeq += 1
        e.seq = lastSeq
        if let url = file(for: e.ts) { LineFile.append(e.jsonLine, to: url) } else { events.append(e) }
        return e
    }

    /// The days that have a file, oldest first.
    func days() -> [String] {
        guard let folder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(".jsonl".count)) }.sorted()
    }

    /// The day `n` days before `now`'s.
    func day(_ n: Int, before now: Int64) -> String { time.day(now - Int64(n) * 24 * 3600 * 1000) }

    /// Deletes the files older than `keptDays` as of `now`: at launch, and
    /// at each new day, for an app left running for weeks.
    public func prune(now: Int64) {
        guard let folder else { return }
        for day in days() where day < self.day(Transcript.keptDays - 1, before: now) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(day + ".jsonl"))
            log("transcript: deleted \(day).jsonl, older than \(Transcript.keptDays) days")
        }
    }

    /// Hands `each` the events of the last `replayDays` days' files as of
    /// `now`, oldest first, each as its line is read, after pruning, and
    /// returns how many. `seq` goes on from the newest file's last event. A
    /// line that doesn't parse, such as one a crash cut short, is skipped,
    /// even when the cut is inside a character.
    @discardableResult
    public func load(now: Int64, each: (Event) -> Void) -> Int {
        guard let folder else { return 0 }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prune(now: now)
        let days = days()
        let oldestRead = day(Transcript.replayDays - 1, before: now)
        var count = 0
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
                    guard let e = Event(jsonLine: line) else { skipped += 1; return }
                    lastSeq = max(lastSeq, e.seq)
                    guard day >= oldestRead else { return }
                    each(e)
                    count += 1
                }
            }
            if skipped > 0 { log("transcript: skipped \(skipped) unreadable line(s) in \(name)") }
        }
        return count
    }
}
