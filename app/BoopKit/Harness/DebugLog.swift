import Foundation

/// Debug mode's record of the brain (HARNESS.md §8): every pass and aside as
/// one JSON line in the state directory's `debug.jsonl`, and the same lines
/// readably, for the terminal (`Boop --debug`) and `boopdev watch`.
public enum DebugLog {
    public static let fileName = "debug.jsonl"

    /// Empties the file, so each launch starts afresh. In place, so a
    /// `boopdev watch` already following it sees it start again.
    public static func start(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            try? handle.truncate(atOffset: 0)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    /// The transcript's window as the brains see it (Jev reads it grouped
    /// like this): one line per input, with what you said, the rules'
    /// reaction and the calls that ran, and one per aside.
    ///
    ///     agent started · claude · jetpack · 14:02 Tuesday · rules: wiggle · did: react(feeling: curious, voice: mumble)
    ///     · tapped · 14:03 Tuesday: Boop wiggled
    public static func lines(_ window: [Transcript.Entry]) -> [String] {
        Transcript.groups(window).map { g in
            guard let did = g.did else { return "· " + g.happened }
            var line = g.happened
            if let words = g.words { line += " \"\(Transcript.oneLine(words))\"" }
            if let rules = g.rules { line += " · rules: \(rules)" }
            if !did.isEmpty { line += " · did: " + did.map(\.plain).joined(separator: ", ") }
            return line
        }
    }

    /// Turns debug lines into readable text, in order. Memory is printed in
    /// full for the first pass, then only the lines added (+) and removed
    /// (-) since the pass before, unless that's longer than the memory
    /// itself; the window every time.
    public final class Printer {
        var memory: [String]?

        public init() {}

        public func readable(_ line: String) -> String {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return line }
            if let aside = o["aside"] as? String { return "· \(aside)" }
            let input = o["input"] as? [String: Any] ?? [:]
            var out = ["▸ \(input["line"] as? String ?? "?")   [\(o["classifier"] as? String ?? "?") → "
                       + "\(o["writer"] as? String ?? "?"), \(o["latency_ms"] as? Int ?? 0) ms]"]
            if let words = input["words"] as? String { out.append("    said     \"\(words)\"") }
            if let memory = o["memory"] as? [String: String] {
                out += self.memory(memory)
            }
            if let context = o["context"] as? [String] {
                out.append("    window   \(o["window"] as? Int ?? 0) inputs, oldest first (Stage 1's)")
                out += context.map(indent)
            }
            let decided = o["decided"] as? [String] ?? []
            out.append("    decided  " + (decided.isEmpty ? "nothing" : decided.joined(separator: ", "))
                       + " (\(o["classify_ms"] as? Int ?? 0) ms)")
            if let evidence = o["evidence"] as? String { out.append("    because  \(evidence)") }
            if let dropped = o["dropped"] as? String { out.append("    DROPPED  \(dropped)") }
            if let raw = o["classifier_raw"] as? String { out.append("    raw      \(raw)") }
            if let prompt = o["writer_prompt"] as? String {
                out.append("    asked    the writer, after its instructions:")
                out += prompt.split(separator: "\n", omittingEmptySubsequences: false).map { indent(String($0)) }
            }
            if let wrote = o["wrote"] as? [String: String], !wrote.isEmpty {
                let values = wrote.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value.isEmpty ? "(empty)" : "\"\($0.value)\"")" }
                out.append("    wrote    " + values.joined(separator: ", ") + " (\(o["write_ms"] as? Int ?? 0) ms)")
            }
            if let failed = o["write_failed"] as? String { out.append("    WRITER   failed: \(failed)") }
            if let raw = o["writer_raw"] as? String { out.append("    raw      \(raw)") }
            for r in o["ran"] as? [[String: Any]] ?? [] {
                let what = (r["done"] as? String).map { "done: \($0)" } ?? "dropped: \(r["dropped"] as? String ?? "?")"
                out.append("    ran      \(r["call"] as? String ?? "?") → \(what)")
            }
            return out.joined(separator: "\n")
        }

        /// A line under its label; an empty one stays empty.
        func indent(_ line: String) -> String { line.isEmpty ? "" : "      " + line }

        /// The memory's lines: all of them the first time, else what changed.
        func memory(_ memory: [String: String]) -> [String] {
            let text = [memory["long_term"], memory["short_term"]].compactMap { $0 }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n\n")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            defer { self.memory = lines }
            guard let before = self.memory else { return ["    memory"] + lines.map(indent) }
            let changes = lines.difference(from: before)
            if changes.isEmpty { return ["    memory   the same as the pass before"] }
            guard changes.count <= lines.count else { return ["    memory   changed"] + lines.map(indent) }
            return ["    memory   \(changes.count) \(changes.count == 1 ? "line" : "lines") changed since the pass before"]
                + changes.map { change in
                    switch change {
                    case .remove(_, let line, _): "      - \(line)"
                    case .insert(_, let line, _): "      + \(line)"
                    }
                }
        }
    }
}
