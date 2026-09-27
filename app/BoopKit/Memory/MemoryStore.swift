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
        for file in [Self.longTermFile, Self.shortTermFile] where stamp(file) != stamps[file] {
            load(file)
        }
    }

    func reload() {
        load(Self.longTermFile)
        load(Self.shortTermFile)
    }

    func stamp(_ file: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(file).path))?[.modificationDate] as? Date
    }

    func load(_ file: String) {
        defer { stamps[file] = stamp(file) }
        guard let text = try? String(contentsOf: url(file), encoding: .utf8) else {
            // Missing: long-term waits for setup, short-term for the first activity.
            if file == Self.longTermFile { longTermValue = nil } else { shortTermValue = nil }
            return
        }
        do {
            try assign(file, text)
        } catch {
            restore(file, because: error)
        }
    }

    func assign(_ file: String, _ text: String) throws {
        if file == Self.longTermFile { longTermValue = try LongTerm.parse(text) } else { shortTermValue = try ShortTerm.parse(text) }
    }

    /// Keeps the broken file as `<file>.broken`. Long-term memory comes back
    /// from the newest snapshot that reads, or from what this store last had.
    /// Short-term snapshots are always of an earlier day, so short-term memory
    /// starts fresh instead, keeping the file's date if it has one so the day
    /// isn't started twice.
    func restore(_ file: String, because error: Error) {
        let broken = url(file + ".broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.copyItem(at: url(file), to: broken)
        if file == Self.shortTermFile {
            let text = (try? String(contentsOf: url(file), encoding: .utf8)) ?? ""
            let date = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).map(String.init).first(where: LocalTime.isDay)
            if let date {
                log("memory: \(file) didn't read (\(error)); kept it as \(file).broken and wrote back \(date)")
                save(ShortTerm(date: date))
            } else {
                log("memory: \(file) didn't read (\(error)); kept it as \(file).broken and starting it fresh")
                shortTermValue = nil
                try? FileManager.default.removeItem(at: url(file))
            }
            return
        }
        let days = ((try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(Self.historyDir).path)) ?? [])
            .filter(LocalTime.isDay).sorted(by: >)
        for day in days {
            guard let text = try? String(contentsOf: historyURL(day).appendingPathComponent(file), encoding: .utf8),
                  (try? assign(file, text)) != nil
            else { continue }
            log("memory: \(file) didn't read (\(error)); restored from history/\(day), kept the old one as \(file).broken")
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
