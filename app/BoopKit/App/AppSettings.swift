import Darwin
import Foundation

/// The app's own settings, in `settings.json` next to the memory files. Name
/// and nature live in `long-term.md`; the API key lives in the Keychain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// `apple`, `rules` or `cloud:<model>` (HARNESS.md §7).
    public var brain = "apple"
    public var volume = 6

    public init() {}

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults, so older files still load; keys
        // this version doesn't know (`focus`, `away`, `awaySince`, `finished`
        // and `projects` from before 2026-09-26) are ignored.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brain = try c.decodeIfPresent(String.self, forKey: .brain) ?? brain
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
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
