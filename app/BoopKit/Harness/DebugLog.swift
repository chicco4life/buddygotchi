import Foundation

/// Debug mode's record of the brain (harness/HARNESS.md §9): every
/// transcript entry as one JSON line in the state directory's
/// `debug.jsonl`, a pass's with the state and questions it sent, and the
/// same lines readably, for the terminal (`Boop --debug`) and
/// `boopdev watch`. Three more kinds of line, with no `seq`, are for the
/// dashboard: `questions`, `sent` and `status`.
public enum DebugLog {
    public static let fileName = "debug.jsonl"

    /// `{"<kind>":<json>,"received_at_ms":N}`: a line that isn't a
    /// transcript entry. `json` goes in as it is, so `sent` carries the
    /// device's line verbatim.
    static func line(_ kind: String, _ json: String, at ms: Int64) -> String {
        "{\"\(kind)\":\(json),\"received_at_ms\":\(ms)}"
    }

    static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The file's first line at every launch: every action's questions,
    /// which the dashboard builds its pickers from.
    public static func questions(_ actions: [any Action], at ms: Int64) -> String {
        line("questions", json(actions.flatMap { action in
            action.questions().map { q in
                ["action": action.name, "key": q.key, "text": q.text,
                 "options": q.options.map { ["name": $0.name, "what": $0.what, "not_for": $0.notFor ?? NSNull()] as [String: Any] }]
                    as [String: Any]
            }
        }), at: ms)
    }

    /// What the device lines don't carry: the personality, the brain, the
    /// sessions and whether the device is connected (a `state` carries the
    /// mood). Nil when it's the same as `last`; the runtime writes only
    /// changes.
    public static func status(_ status: Runtime.Status, at ms: Int64, last: inout String?) -> String? {
        let value = json(["personality": status.personality.rawValue, "brain": status.brain,
                          "connected": status.connected,
                          "sessions": status.sessions.map { ["agent": $0.agent, "project": $0.project, "status": $0.status.rawValue] }]
                         as [String: Any])
        guard value != last else { return nil }
        last = value
        return line("status", value, at: ms)
    }

    /// How many earlier launches' files are kept beside the file, so a
    /// relaunch mid-day doesn't lose the morning (`boopctl day` reads them
    /// all): `debug.1.jsonl` is the launch before this one, up to
    /// `debug.10.jsonl`.
    public static let keptLaunches = 10

    /// Where launch `n` before this one is kept: `debug.<n>.jsonl` beside
    /// `url`.
    public static func kept(_ n: Int, of url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).\(n).\(url.pathExtension)")
    }

    /// Keeps a copy of the last launch's lines (`keptLaunches`, the oldest
    /// let go), then empties the file, so each launch starts afresh. In
    /// place, so a `boopdev watch` or the dashboard already following it
    /// sees it start again.
    public static func start(_ url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > 0 {
            try? fm.removeItem(at: kept(keptLaunches, of: url))
            for n in stride(from: keptLaunches - 1, through: 1, by: -1) {
                try? fm.moveItem(at: kept(n, of: url), to: kept(n + 1, of: url))
            }
            try? fm.copyItem(at: url, to: kept(1, of: url))
        }
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
    ///     ▸ 12 tool_use: claude's tests failed on "fix-nav" (landing).
    ///       pass jev:jev-latest 240 ms: mood grumpy 0.69 · react grumpy 0.63 · react.loops twice 0.58 · word.feeling again 0.57 · word.about tests 0.81
    ///       ✓ mood: Boop's mood changed: happy → grumpy.
    ///       … react: Boop made a grumpy face, held twice, and mumbled "…again!"
    ///       ✓ react (15) done
    public final class Printer {
        var shownFullState = false
        /// Each action's name by its `seq`, for its settle's line.
        var names: [Int: String] = [:]

        public init() {}

        /// Nil for a line with no `seq`, which isn't a transcript entry: the
        /// dashboard's.
        public func readable(_ line: String) -> String? {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return line }
            guard let seq = o["seq"] as? Int else { return nil }
            if let e = o["event"] as? [String: Any] {
                var out = "▸ \(seq) \(e["kind"] as? String ?? "?")\(e["wakes_brain"] as? Bool == true ? "" : " (no pass)"): "
                    + (e["line"] as? String ?? "")
                if let reaction = e["reaction"] as? String { out += "\n    " + reaction }
                return out
            }
            if let p = o["pass"] as? [String: Any] {
                var out = "  pass \(p["brain"] as? String ?? p["by"] as? String ?? "?") \(p["latency_ms"] as? Int ?? 0) ms: "
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
                let name = a["name"] as? String ?? "?"
                names[seq] = name
                let mark = a["ok"] as? Bool != true ? "✗" : a["pending"] as? Bool == true ? "…" : "✓"
                return "  \(mark) \(name): \(a["message"] as? String ?? "")"
            }
            if let s = o["settle"] as? [String: Any], let action = s["for"] as? Int {
                let name = "\(names[action] ?? "?") (\(action))"
                return s["end"] as? String == "done" ? "  ✓ \(name) done" : "  ✗ \(name) didn't happen: \(s["why"] as? String ?? "?")"
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
