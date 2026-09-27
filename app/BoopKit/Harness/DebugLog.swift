import Foundation

/// Debug mode's record of the brain (harness/HARNESS.md §9): every
/// transcript entry as one JSON line in the state directory's
/// `debug.jsonl`, a pass's with the state and questions it sent, and the
/// same lines readably, for the terminal (`Boop --debug`) and
/// `boopdev watch`.
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

    /// Turns debug lines into readable text. The state is printed in full
    /// for the first pass, then only its HISTORY and NOW, which are what
    /// change.
    ///
    ///     ▸ 12 tool_use: claude's tests failed again on "fix-nav" (landing), 3 in a row.
    ///       pass jev:jev-latest 240 ms: mood grumpy 0.69 · react annoyed 0.63 · word.feeling again 0.57 · word.about tests 0.81
    ///       ✓ mood: Boop's mood changed: happy → grumpy.
    ///       ✓ react: Boop mumbled, annoyed: "…again!"
    public final class Printer {
        var shownFullState = false

        public init() {}

        public func readable(_ line: String) -> String {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return line }
            let seq = o["seq"] as? Int ?? 0
            if let e = o["event"] as? [String: Any] {
                var out = "▸ \(seq) \(e["kind"] as? String ?? "?")\(e["wakes_brain"] as? Bool == true ? "" : " (no pass)"): "
                    + (e["line"] as? String ?? "")
                if let reaction = e["reaction"] as? String { out += "\n    " + reaction }
                return out
            }
            if let p = o["pass"] as? [String: Any] {
                var out = "  pass \(p["brain"] as? String ?? "?") \(p["latency_ms"] as? Int ?? 0) ms: "
                if let dropped = p["dropped"] as? String {
                    out += "dropped: \(dropped)"
                } else {
                    let answers = p["answers"] as? [String: [String: Any]] ?? [:]
                    out += answers.keys.sorted().map { key in
                        let a = answers[key]!
                        let choice = a["choice"] as? String ?? "?"
                        let prob = (a["p"] as? [String: Any])?[choice] as? Double
                        return "\(key) \(choice)" + (prob.map { String(format: " %.2f", $0) } ?? "")
                    }.joined(separator: " · ")
                }
                if let state = p["state"] as? String {
                    let shown = shownFullState ? StateText.lastSections(state) : state
                    shownFullState = true
                    out += "\n" + shown.split(separator: "\n", omittingEmptySubsequences: false).map { "    │ " + $0 }.joined(separator: "\n")
                }
                return out
            }
            if let a = o["action"] as? [String: Any] {
                return "  \(a["ok"] as? Bool == true ? "✓" : "✗") \(a["name"] as? String ?? "?"): \(a["message"] as? String ?? "")"
            }
            return line
        }
    }
}

extension StateText {
    /// HISTORY and NOW alone, for printing a state after the first.
    static func lastSections(_ state: String) -> String {
        guard let r = state.range(of: "HISTORY (") else { return state }
        return String(state[r.lowerBound...])
    }
}
