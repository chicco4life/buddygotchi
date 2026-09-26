import Darwin
import Foundation

/// The app's own settings, in `settings.json` next to the memory files. Name
/// and nature live in `long-term.md`; the API key lives in the Keychain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// `apple`, `rules`, `jev` or `cloud:<model>` (HARNESS.md §7).
    public var brain = "apple"
    public var volume = 6
    public var away = false
    /// The day "I'm away" started, `yyyy-MM-dd`, so a restart keeps pausing
    /// hunger from then rather than from the day it restarts.
    public var awaySince: String?
    /// Boop's record (UX.md §7): turns finished and how many projects, as
    /// totals. Project names are kept only to count them.
    public var finished = 0
    public var projects: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults, so older files still load.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brain = try c.decodeIfPresent(String.self, forKey: .brain) ?? brain
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
        away = try c.decodeIfPresent(Bool.self, forKey: .away) ?? away
        awaySince = try c.decodeIfPresent(String.self, forKey: .awaySince)
        finished = try c.decodeIfPresent(Int.self, forKey: .finished) ?? finished
        projects = try c.decodeIfPresent([String].self, forKey: .projects) ?? projects
    }

    public static let file = "settings.json"

    public static func load(from directory: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.file), options: .atomic)
    }

    /// `~/Library/Application Support/Boop`: the everyday app's memory files,
    /// settings and hook socket.
    public static func defaultStateDir(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Boop")
    }
}

/// One app per state directory: a second copy would fight over the memory
/// files and the hook socket. The lock goes away with the process.
public final class InstanceLock {
    let fd: Int32

    public init?(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("boop.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
