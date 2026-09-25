import Foundation

/// The only code that reads or writes the memory files (ARCHITECTURE.md §3.6,
/// §4). It supplies their text for prompts, applies changes within each
/// section's limits, writes atomically, snapshots the files to
/// `history/<date>/`, and restores a file that won't parse.
///
/// Hand edits are welcome: a file changed on disk is read again before the
/// next change, so the edit isn't overwritten.
public final class MemoryStore {
    public static let longTermFile = "long-term.md"
    public static let shortTermFile = "short-term.md"
    public static let historyDir = "history"

    public let directory: URL
    /// `steering.md`, read-only. The app passes its bundled copy.
    public let steering: String
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
    /// The day the last reflection is about, set when a new day starts.
    public private(set) var reflecting: String?
    /// The day `temperament` last changed, so it changes at most once a day.
    var temperamentChanged: String?
    var stamps: [String: Date] = [:]

    public init(directory: URL, steering: String, log: @escaping (String) -> Void = { _ in }) throws {
        self.directory = directory
        self.steering = steering
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

    // MARK: Text for the prompt

    public var longTermText: String {
        refresh()
        return longTerm?.markdown ?? ""
    }

    public var shortTermText: String {
        refresh()
        return shortTerm?.markdown ?? ""
    }

    /// Short-term memory for the day being reflected on, from its snapshot.
    public var reflectionText: String? {
        guard let reflecting else { return nil }
        return try? String(contentsOf: historyURL(reflecting).appendingPathComponent(Self.shortTermFile), encoding: .utf8)
    }

    /// Today's date in `short-term.md`, for `Core.init`'s `lastActiveDay`.
    public var lastActiveDay: String? {
        refresh()
        return shortTerm?.date
    }

    // MARK: Core effects

    /// Applies the core's `.happened`, `.growth` and `.newDay`; ignores the rest.
    public func apply(_ effect: CoreEffect) {
        refresh()
        switch effect {
        case .happened(let line):
            guard var st = shortTerm else { return }
            st.happened.append(line)
            st.happened = Array(st.happened.suffix(MemoryLimits.happened))
            while st.markdown.utf8.count > MemoryLimits.shortTermBytes && !st.happened.isEmpty {
                st.happened.removeFirst()
            }
            save(st)
        case .growth(let growth):
            guard var lt = longTerm else { return }
            lt.growth = growth
            save(lt)
        case .newDay(let date, let firstSeen, let mood):
            startDay(date, firstSeen: firstSeen, mood: mood)
        default:
            break
        }
    }

    /// Updates the mood on the Today line.
    public func setMood(_ mood: String) {
        refresh()
        guard var st = shortTerm, st.mood != mood else { return }
        st.mood = mood
        save(st)
    }

    /// Snapshots both files to `history/<the old day>/`, keeps that day for
    /// the reflection, and starts short-term memory fresh.
    func startDay(_ date: String, firstSeen: String, mood: String) {
        if let old = shortTerm, old.date != date {
            do {
                try snapshot(day: old.date)
                reflecting = old.date
            } catch {
                log("memory: snapshot for \(old.date) failed: \(error)")
            }
        }
        save(ShortTerm(date: date, firstSeen: firstSeen, mood: mood))
    }

    // MARK: Changes from actions

    /// `note`: a line in today's Notes; the oldest drops past ten.
    public func note(_ text: String) -> Result<String, Refusal> {
        refresh()
        guard var st = shortTerm else { return .failure(Refusal("no short-term memory yet")) }
        let line: String
        switch MemoryText.check(text, max: MemoryLimits.noteChars, names: false) {
        case .failure(let why): return .failure(why)
        case .success(let s): line = s
        }
        if st.notes.contains(where: { $0.lowercased() == line.lowercased() }) {
            return .failure(Refusal("already noted"))
        }
        st.notes.append(line)
        st.notes = Array(st.notes.suffix(MemoryLimits.notes))
        while st.markdown.utf8.count > MemoryLimits.shortTermBytes && !st.happened.isEmpty {
            st.happened.removeFirst()
        }
        save(st)
        return .success(line)
    }

    public enum FactKind: String, CaseIterable, Sendable {
        case aboutYou = "about_you"
        case preference
    }

    /// `remember`: a line in About you or Preferences.
    public func remember(_ text: String, as kind: FactKind) -> Result<String, Refusal> {
        refresh()
        guard var lt = longTerm else { return .failure(Refusal("not set up")) }
        let line: String
        switch MemoryText.check(text, max: MemoryLimits.factChars, names: true, boopName: lt.name) {
        case .failure(let why): return .failure(why)
        case .success(let s): line = s
        }
        let all = lt.aboutYou + lt.preferences
        if all.contains(where: { Self.same($0, line) }) { return .failure(Refusal("already remembered")) }
        switch kind {
        case .aboutYou:
            guard lt.aboutYou.count < MemoryLimits.aboutYou else { return .failure(Refusal("About you is full")) }
            lt.aboutYou.append(line)
        case .preference:
            guard lt.preferences.count < MemoryLimits.preferences else {
                return .failure(Refusal("Preferences is full"))
            }
            lt.preferences.append(line)
        }
        return commit(lt).map { line }
    }

    /// `forget`: removes the About you or Preferences line that matches, or
    /// the only one that contains the text.
    public func forget(_ text: String) -> Result<String, Refusal> {
        refresh()
        guard var lt = longTerm else { return .failure(Refusal("not set up")) }
        let needle = Self.key(text)
        guard !needle.isEmpty else { return .failure(Refusal("empty")) }
        let lists = [lt.aboutYou, lt.preferences]
        var hits: [(list: Int, index: Int)] = []
        for (l, list) in lists.enumerated() {
            for (i, line) in list.enumerated() where Self.key(line) == needle { hits.append((l, i)) }
        }
        if hits.isEmpty {
            for (l, list) in lists.enumerated() {
                for (i, line) in list.enumerated() where Self.key(line).contains(needle) { hits.append((l, i)) }
            }
        }
        guard hits.count == 1, let hit = hits.first else {
            return .failure(Refusal(hits.isEmpty ? "nothing matches" : "\(hits.count) lines match"))
        }
        let removed: String
        if hit.list == 0 { removed = lt.aboutYou.remove(at: hit.index) } else { removed = lt.preferences.remove(at: hit.index) }
        return commit(lt).map { removed }
    }

    /// `temperament`: one new sentence, at most once a day. Past five, it
    /// replaces the oldest.
    public func temperament(_ text: String, today: String) -> Result<String, Refusal> {
        refresh()
        guard var lt = longTerm else { return .failure(Refusal("not set up")) }
        if temperamentChanged == today { return .failure(Refusal("temperament already changed today")) }
        let line: String
        switch MemoryText.check(text, max: MemoryLimits.temperamentChars, names: true, boopName: lt.name) {
        case .failure(let why): return .failure(why)
        case .success(let s): line = s
        }
        let body = line.dropLast(line.last.map { ".!?".contains($0) } == true ? 1 : 0)
        if body.contains(where: { ".!?".contains($0) }) { return .failure(Refusal("more than one sentence")) }
        if lt.temperament.contains(where: { Self.same($0, line) }) { return .failure(Refusal("already says that")) }
        lt.temperament.append(line)
        if lt.temperament.count > MemoryLimits.temperamentSentences { lt.temperament.removeFirst() }
        return commit(lt).map {
            temperamentChanged = today
            return line
        }
    }

    /// `moment`: a memorable day, at most one per day. Past twenty, the
    /// oldest drops.
    public func moment(_ text: String, day: String) -> Result<String, Refusal> {
        refresh()
        guard var lt = longTerm else { return .failure(Refusal("not set up")) }
        if lt.moments.contains(where: { $0.date == day }) { return .failure(Refusal("already a moment for \(day)")) }
        let line: String
        switch MemoryText.check(text, max: MemoryLimits.momentChars, names: true, boopName: lt.name) {
        case .failure(let why): return .failure(why)
        case .success(let s): line = s
        }
        lt.moments.append(.init(date: day, text: line))
        lt.moments.sort { $0.date < $1.date }
        if lt.moments.count > MemoryLimits.moments { lt.moments.removeFirst() }
        return commit(lt).map { line }
    }

    /// Writes long-term memory if it fits its budget.
    func commit(_ lt: LongTerm) -> Result<Void, Refusal> {
        guard lt.markdown.utf8.count <= MemoryLimits.longTermBytes else {
            return .failure(Refusal("long-term memory is full"))
        }
        save(lt)
        return .success(())
    }

    static func key(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?")))
    }

    static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }

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
    /// isn't started (and reflected on) twice.
    func restore(_ file: String, because error: Error) {
        let broken = url(file + ".broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.copyItem(at: url(file), to: broken)
        if file == Self.shortTermFile {
            let text = (try? String(contentsOf: url(file), encoding: .utf8)) ?? ""
            let date = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).map(String.init).first(where: LocalTime.isDay)
            if let date {
                let st = shortTermValue?.date == date ? shortTermValue! : ShortTerm(date: date, firstSeen: "", mood: "")
                log("memory: \(file) didn't read (\(error)); kept it as \(file).broken and wrote back \(date)")
                save(st)
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

    func save(_ lt: LongTerm) {
        do {
            try write(lt.markdown, Self.longTermFile)
            longTermValue = lt
        } catch {
            log("memory: writing \(Self.longTermFile) failed: \(error)")
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
