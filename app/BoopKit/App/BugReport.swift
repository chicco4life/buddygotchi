import Foundation

extension Runtime {
    /// Where `saveReport` puts its folders, in the state directory.
    public static let reportsDir = "bug-reports"
    /// How much of the end of `boop.log` a report copies.
    static let reportLogBytes = 1 << 20

    /// A bug report (harness/HARNESS.md §9): everything needed to work out
    /// afterwards what Boop saw and did, in a new folder under
    /// `bug-reports/`. `debug.jsonl` is this launch's debug lines, debug
    /// mode or not, which `boopdev watch` reads; `boop.log` is the log's
    /// end; `settings.json` and `mood` are copied; `about.json` is the
    /// versions and the status now. Calls `done` on `home` with the folder,
    /// or nil if it couldn't be made.
    public func saveReport(_ done: @escaping @Sendable (URL?) -> Void) {
        home.async { [self] in
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd-HHmmss"
            let dir = options.stateDir.appendingPathComponent(Self.reportsDir)
                .appendingPathComponent(format.string(from: Date(timeIntervalSince1970: Double(options.wallClock()) / 1000)))
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data(recent.kept.map { $0 + "\n" }.joined().utf8).write(to: dir.appendingPathComponent(DebugLog.fileName))
                if let log = FileHandle(forReadingAtPath: options.stateDir.appendingPathComponent("boop.log").path) {
                    let end = (try? log.seekToEnd()) ?? 0
                    try? log.seek(toOffset: end > UInt64(Self.reportLogBytes) ? end - UInt64(Self.reportLogBytes) : 0)
                    try? log.readToEnd()?.write(to: dir.appendingPathComponent("boop.log"))
                    try? log.close()
                }
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
                try Data(DebugLog.json(about).utf8).write(to: dir.appendingPathComponent("about.json"))
                options.log("report: saved \(dir.path)")
                done(dir)
            } catch {
                options.log("report: can't save: \(error)")
                done(nil)
            }
        }
    }
}
