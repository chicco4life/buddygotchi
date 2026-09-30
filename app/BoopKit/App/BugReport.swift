import Foundation

extension Runtime {
    /// Where `saveReport` puts its folders, in the state directory.
    public static let reportsDir = "bug-reports"
    /// How much of the end of `boop.log` a report copies.
    static let reportLogBytes = 1 << 20

    /// A bug report (harness/HARNESS.md §9): everything needed to work out
    /// afterwards what Boop saw and did, in a new folder under
    /// `bug-reports/`. `debug.jsonl` is this launch's debug lines, debug
    /// mode or not (`recent`, or in debug mode the file's end, up to
    /// `DebugLog.Recent.maxBytes`), which `boopdev watch` reads; `boop.log`
    /// is the log's end; `settings.json` and `mood` are copied;
    /// `about.json` is the versions and the status now. Calls `done` on
    /// `home` with the folder, or nil if it couldn't be made.
    public func saveReport(_ done: @escaping @Sendable (URL?) -> Void) {
        home.async { [self] in
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd-HHmmss"
            let dir = options.stateDir.appendingPathComponent(Self.reportsDir)
                .appendingPathComponent(format.string(from: Date(timeIntervalSince1970: Double(options.wallClock()) / 1000)))
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let lines = dir.appendingPathComponent(DebugLog.fileName)
                if options.debug {
                    try Self.write(Self.debugLines(debugLogURL), to: lines)
                } else {
                    try Self.write(recent.pieces, to: lines)
                }
                try? Self.end(of: options.stateDir.appendingPathComponent("boop.log"), bytes: Self.reportLogBytes)?
                    .write(to: dir.appendingPathComponent("boop.log"))
                for name in [AppSettings.file, MoodStore.fileName] {
                    try? fm.copyItem(at: options.stateDir.appendingPathComponent(name), to: dir.appendingPathComponent(name))
                }
                let now = options.clock()
                let about: [String: Any] = [
                    "app": BoopVersion.current, "firmware": link.status?.fw ?? NSNull(), "device": link.status?.id ?? NSNull(),
                    "link": options.link?.name ?? "none", "connected": link.connected, "debug": options.debug,
                    "personality": personality.rawValue, "mood": mood.current, "brain": harness.brain?.id ?? "none",
                    "taken_at_ms": now, "taken_at_wall_ms": options.wallClock(),
                    "sessions": core.sessionList(at: now).map { ["agent": $0.agent, "project": $0.project, "status": $0.status.rawValue] },
                ]
                try Data(Event.json(about).utf8).write(to: dir.appendingPathComponent("about.json"))
                options.log("report: saved \(dir.path)")
                done(dir)
            } catch {
                options.log("report: can't save: \(error)")
                done(nil)
            }
        }
    }

    /// The last `bytes` of the file at `url`, from the start of a line;
    /// nil when there's no file. Mapped, not read, so a copy of megabytes
    /// leaves no memory behind.
    static func end(of url: URL, bytes: Int) -> Data? {
        (try? Data(contentsOf: url, options: .alwaysMapped)).map { end(of: $0, bytes: bytes) }
    }

    static func end(of data: Data, bytes: Int) -> Data {
        guard data.count > bytes else { return data }
        let end = data.suffix(bytes)
        guard data[end.startIndex - 1] != 0x0A else { return end }
        return end.firstIndex(of: 0x0A).map { end[end.index(after: $0)...] } ?? Data()
    }

    /// Debug mode's `debug.jsonl` for a report, as `recent` would have it:
    /// its end, after the launch's `questions` line and the `head` line in
    /// force where the end starts, when those come before it.
    static func debugLines(_ url: URL) -> [Data] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let end = end(of: data, bytes: DebugLog.Recent.maxBytes)
        let before = data[..<end.startIndex]
        func line(from start: Data.Index) -> Data { before[start...(before[start...].firstIndex(of: 0x0A) ?? before.endIndex - 1)] }
        var pieces: [Data] = []
        if before.starts(with: DebugLog.questionsLine) { pieces.append(line(from: before.startIndex)) }
        if let head = before.range(of: Data([0x0A] + DebugLog.headLine), options: .backwards) { pieces.append(line(from: head.lowerBound + 1)) }
        return pieces + [end]
    }

    /// Writes `pieces` one after another to a new file at `url`, without
    /// joining them first.
    static func write<Piece: DataProtocol>(_ pieces: [Piece], to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        for piece in pieces { try file.write(contentsOf: piece) }
    }
}
