import Foundation

/// The only code that reads or writes the memory files (ARCHITECTURE.md §3.6,
/// §4): who this Boop is, and which day it last saw. It writes atomically,
/// snapshots the files to `history/<date>/`, and restores a file that won't
/// parse.
///
/// Hand edits are welcome: a file changed on disk is read again before the
/// next change, so the edit isn't overwritten.
public final class MemoryStore {
    public static let longTermFile = "long-term.md"
    public static let shortTermFile = "short-term.md"
    public static let historyDir = "history"

    public let directory: URL
    let log: (String) -> Void

    var longTermValue: LongTerm?
    var shortTermValue: ShortTerm?

    /// The files as they are now, read again if they changed on disk.
    public var longTerm: LongTerm? {
        refresh()
        return longTermValue
    }

    public var shortTerm: ShortTerm? {
        refresh()
        return shortTermValue
    }
    var stamps: [String: Date] = [:]

    public init(directory: URL, log: @escaping (String) -> Void = { _ in }) throws {
        self.directory = directory
        self.log = log
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    public var isSetUp: Bool { longTerm != nil }

    /// Creates `long-term.md` for a new Boop. Refuses if one exists.
    public func setUp(name: String, nature: LongTerm.Nature, seed: UInt64, today: String) throws {
        guard longTerm == nil else { throw Refusal("already set up") }
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.count <= 23, !clean.contains("·"), !clean.contains(":"), !clean.contains("\n")
        else { throw Refusal("a name is 1–23 characters, without · or :") }
        let lt = LongTerm(name: clean, hatched: today, nature: nature, seed: seed)
        try write(lt.markdown, Self.longTermFile)
        longTermValue = lt
        try snapshot(day: today)
    }

    /// Today's date in `short-term.md`, for `Core.init`'s `lastActiveDay`.
    public var lastActiveDay: String? { shortTerm?.date }

    // MARK: Core effects

    /// The core's `.newDay`: snapshots both files to `history/<the old
    /// day>/` and starts short-term memory fresh.
    public func startDay(_ date: String) {
        if let old = shortTerm, old.date != date {
            do {
                try snapshot(day: old.date)
            } catch {
                log("memory: snapshot for \(old.date) failed: \(error)")
            }
        }
        save(ShortTerm(date: date))
    }

    // MARK: Files

    func url(_ file: String) -> URL { directory.appendingPathComponent(file) }
    func historyURL(_ day: String) -> URL { directory.appendingPathComponent(Self.historyDir).appendingPathComponent(day) }

    /// Copies both files to `history/<day>/`, replacing an earlier copy.
    func snapshot(day: String) throws {
        let dir = historyURL(day)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in [Self.longTermFile, Self.shortTermFile] {
            guard let data = FileManager.default.contents(atPath: url(file).path) else { continue }
            try data.write(to: dir.appendingPathComponent(file), options: .atomic)
        }
    }

    /// Reads both files if they changed on disk since this store last saw them.
    func refresh() {
        if stamp(Self.longTermFile) != stamps[Self.longTermFile] { loadLongTerm() }
        if stamp(Self.shortTermFile) != stamps[Self.shortTermFile] { loadShortTerm() }
    }

    func reload() {
        loadLongTerm()
        loadShortTerm()
    }

    func stamp(_ file: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(file).path))?[.modificationDate] as? Date
    }

    func text(_ file: String) -> String? { try? String(contentsOf: url(file), encoding: .utf8) }

    /// Missing, it waits for setup. One that won't parse is kept as
    /// `long-term.md.broken` and comes back from the newest snapshot that
    /// reads, or from what this store last had.
    func loadLongTerm() {
        let file = Self.longTermFile
        defer { stamps[file] = stamp(file) }
        guard let text = text(file) else { longTermValue = nil; return }
        do {
            longTermValue = try LongTerm.parse(text)
        } catch {
            keepBroken(file)
            let history = directory.appendingPathComponent(Self.historyDir).path
            let days = ((try? FileManager.default.contentsOfDirectory(atPath: history)) ?? []).filter(LocalTime.isDay).sorted(by: >)
            for day in days {
                guard let text = try? String(contentsOf: historyURL(day).appendingPathComponent(file), encoding: .utf8),
                      let restored = try? LongTerm.parse(text)
                else { continue }
                log("memory: \(file) didn't read (\(error)); restored from history/\(day), kept the old one as \(file).broken")
                longTermValue = restored
                try? write(text, file)
                return
            }
            if let longTerm = longTermValue {
                log("memory: \(file) didn't read (\(error)) and there's no snapshot; wrote back the last good copy")
                try? write(longTerm.markdown, file)
            } else {
                log("memory: \(file) didn't read (\(error)) and there's no snapshot; kept it as \(file).broken")
            }
        }
    }

    /// Missing, it waits for the first activity. Its snapshots are always of
    /// an earlier day, so one that won't parse is kept as
    /// `short-term.md.broken` and starts fresh instead, keeping the file's
    /// date if it has one so the day isn't started twice.
    func loadShortTerm() {
        let file = Self.shortTermFile
        defer { stamps[file] = stamp(file) }
        guard let text = text(file) else { shortTermValue = nil; return }
        do {
            shortTermValue = try ShortTerm.parse(text)
        } catch {
            keepBroken(file)
            let date = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).map(String.init).first(where: LocalTime.isDay)
            if let date {
                log("memory: \(file) didn't read (\(error)); kept it as \(file).broken and wrote back \(date)")
                save(ShortTerm(date: date))
            } else {
                log("memory: \(file) didn't read (\(error)); kept it as \(file).broken and starting it fresh")
                shortTermValue = nil
                try? FileManager.default.removeItem(at: url(file))
            }
        }
    }

    /// Copies a file that won't parse to `<file>.broken`.
    func keepBroken(_ file: String) {
        let broken = url(file + ".broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.copyItem(at: url(file), to: broken)
    }

    func save(_ st: ShortTerm) {
        do {
            try write(st.markdown, Self.shortTermFile)
            shortTermValue = st
        } catch {
            log("memory: writing \(Self.shortTermFile) failed: \(error)")
        }
    }

    /// Atomic: a temporary file renamed over the old one.
    func write(_ text: String, _ file: String) throws {
        try Data(text.utf8).write(to: url(file), options: .atomic)
        stamps[file] = stamp(file)
    }
}
