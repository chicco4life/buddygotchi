import Foundation

/// Reads display metadata only, never transcripts or raw prompts. Call off the
/// main actor at turn boundaries; a missing index simply retains the fallback.
enum SessionTitleReader {
    static func codexTitle(sessionId: String, index: URL? = nil) -> String? {
        let url = index ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
            .appendingPathComponent("session_index.jsonl")
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return nil }
        let offset = size > 262144 ? size-262144 : 0
        guard (try? file.seek(toOffset: offset)) != nil,
              let bytes = try? file.read(upToCount: 262144) else { return nil }
        var lines = bytes.split(separator: 10)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["id"] as? String == sessionId, let name = obj["thread_name"] as? String else { continue }
            let title = deviceTitle(name)
            return title.isEmpty ? nil : title
        }
        return nil
    }
}
