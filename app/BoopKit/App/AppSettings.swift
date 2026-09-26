import Darwin
import Foundation

/// The app's own settings, in `settings.json` next to the memory files. Name
/// and nature live in `long-term.md`; the API key lives in the Keychain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// How much Boop reacts (BEHAVIORS.md §6); it picks the brain.
    public var mode = Mode.normal
    public var volume = 6

    public init() {}

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults, so older files still load; keys
        // this version doesn't know are ignored: `classifier`, `writer` and
        // `brain` from before the modes, which all start in normal, and
        // `focus`, `away`, `awaySince`, `finished` and `projects` from before
        // 2026-09-26. An unknown mode is normal.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decodeIfPresent(String.self, forKey: .mode), let mode = Mode(rawValue: raw) { self.mode = mode }
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
    }

    enum CodingKeys: String, CodingKey { case mode, volume }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode.rawValue, forKey: .mode)
        try c.encode(volume, forKey: .volume)
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
