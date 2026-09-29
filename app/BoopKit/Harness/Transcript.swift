import Foundation

/// Boop's record of what happened and what it did (harness/HARNESS.md §5):
/// every raw event, in order, append-only. The view is folded from it, and
/// the state from the view. With a folder, each event is also written as a
/// line to `<folder>/<date>.jsonl`, one file per day, and a launch reads
/// the last days back. Touched only on the runtime's queue.
public final class Transcript: @unchecked Sendable {
    /// Days of files kept; older ones are deleted at launch.
    public static let keptDays = 14
    /// Days read back at launch, for the view to pick up from.
    public static let replayDays = 2
    /// Past this many events the oldest are let go from memory; the files
    /// keep them.
    public static let limit = 1000
    /// The folder in the state directory.
    public static let folderName = "transcript"

    /// The latest events, oldest first, up to `limit`.
    public private(set) var events: [Event] = []
    var nextSeq = 1
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

    /// Stamps the event with the next `seq`, keeps it and writes its line.
    @discardableResult
    public func append(_ event: Event) -> Event {
        var e = event
        e.seq = nextSeq
        nextSeq += 1
        events.append(e)
        if events.count > Transcript.limit { events.removeFirst(events.count - Transcript.limit) }
        if let url = file(for: e.ts) { LineFile.append(e.jsonLine, to: url) }
        return e
    }

    /// The events of the last `replayDays` days' files as of `now`, oldest
    /// first, after deleting files older than `keptDays`. `seq` goes on
    /// from the newest file's last event. A line that doesn't parse, such
    /// as one a crash cut short, is skipped.
    public func load(now: Int64) -> [Event] {
        guard let folder else { return [] }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.sorted()
        let dayMs: Int64 = 24 * 3600 * 1000
        let oldestKept = time.day(now - Int64(Transcript.keptDays - 1) * dayMs)
        let oldestRead = time.day(now - Int64(Transcript.replayDays - 1) * dayMs)
        var loaded: [Event] = []
        for name in names {
            let day = String(name.dropLast(".jsonl".count))
            if day < oldestKept {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
                log("transcript: deleted \(name), older than \(Transcript.keptDays) days")
                continue
            }
            // An older file is read only if it's the newest, for `seq`.
            guard day >= oldestRead || name == names.last,
                  let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            var skipped = 0
            let parsed = text.split(separator: "\n").compactMap { line -> Event? in
                guard let e = Event(jsonLine: line) else { skipped += 1; return nil }
                return e
            }
            if skipped > 0 { log("transcript: skipped \(skipped) unreadable line(s) in \(name)") }
            if let last = parsed.map(\.seq).max() { nextSeq = max(nextSeq, last + 1) }
            if day >= oldestRead { loaded += parsed }
        }
        events = Array(loaded.suffix(Transcript.limit))
        return loaded
    }
}
