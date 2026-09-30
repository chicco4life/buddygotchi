import Foundation

/// Debug mode's record of the brain (harness/HARNESS.md §9): in the state
/// directory's `debug.jsonl`, every event the transcript records
/// (`event`), every view event (`view`) and every pass with the state and
/// questions it sent (`pass`, with the state's unchanging head in a `head`
/// line only when it changes), one JSON line each, and the same lines
/// readably, for the terminal (`Boop --debug`) and `boopdev watch`. Three
/// more kinds of line are for the dashboard: `questions`, `sent` and
/// `status`.
public enum DebugLog {
    public static let fileName = "debug.jsonl"

    /// `{"<kind>":<json>,"received_at_ms":N}`. `json` goes in as it is, so
    /// `sent` carries the device's line verbatim.
    static func line(_ kind: String, _ json: String, at ms: Int64) -> String {
        "{\"\(kind)\":\(json),\"received_at_ms\":\(ms)}"
    }

    /// A line sent to the device, verbatim, and who sent it: `brain` for
    /// the brain's moments, `rule` for everything else.
    public static func sent(_ json: String, by sender: DeviceLink.Sender, at ms: Int64) -> String {
        "{\"sent\":\(json),\"by\":\"\(sender.rawValue)\",\"received_at_ms\":\(ms)}"
    }

    /// An event as the transcript recorded it, as its line there.
    public static func event(_ e: Event) -> String { line("event", e.jsonLine, at: e.at) }

    /// A view event, gated.
    public static func view(_ v: ViewEvent) -> String { line("view", Event.json(v.json), at: v.ts) }

    /// The head of the state (the guide, PERSONALITY and MOOD), which the
    /// passes after it share: written before a Jev pass whose head differs
    /// from the last one written, so a pass line carries only HISTORY and
    /// NOW.
    public static func head(_ head: String, at ms: Int64) -> String { line("head", Event.json(head), at: ms) }

    /// A pass: what was asked and answered for a view event, with `extra`
    /// (its state's HISTORY and NOW, questions, brain and the last event
    /// its state saw), or the dashboard's forced answers.
    public static func pass(_ p: Harness.Pass, extra: [String: Any], at ms: Int64) -> String {
        var pass: [String: Any] = ["for": p.forSeq ?? NSNull(), "latency_ms": p.latencyMs, "dropped": p.dropped ?? NSNull(),
                                   "answers": answers(p.answers)]
        for (k, v) in extra { pass[k] = v }
        return line("pass", Event.json(pass), at: ms)
    }

    static func answers(_ answers: Answers) -> [String: Any] {
        answers.mapValues { a in
            ["choice": a.choice, "p": a.probabilities.mapValues { ($0 * 1000).rounded() / 1000 }] as [String: Any]
        }
    }

    /// The file's first line at every launch: every action's questions,
    /// which the dashboard builds its pickers from. A pass line names the
    /// options it asked where they differ (`Harness.changedOptions`).
    public static func questions(_ actions: [any Action], at ms: Int64) -> String {
        line("questions", Event.json(actions.flatMap { action in
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
        let value = Event.json(["personality": status.personality.rawValue, "brain": status.brain,
                                "connected": status.connected,
                                "sessions": status.sessions.map { ["agent": $0.agent, "project": $0.project, "status": $0.status.rawValue] }]
                               as [String: Any])
        guard value != last else { return nil }
        last = value
        return line("status", value, at: ms)
    }

    /// This launch's debug lines kept in memory outside debug mode, for a
    /// bug report (§9), back to back as their bytes: the oldest are let go
    /// past `maxBytes`. Touched only on `home`.
    public final class Recent {
        /// About a busy day's worth: a pass's line, the biggest, is under 10 KB.
        public static let maxBytes = 8 << 20

        /// The lines, each with its newline, the ones let go first. Its room
        /// is taken once, for all it holds before it's compacted: memory
        /// is used only as lines fill it, and growing it step by step left
        /// each smaller buffer behind, dirty.
        var text: [UInt8] = []
        /// Where each line starts in `text`, and how many of them are let go.
        var starts: [Int] = []
        var dropped = 0
        /// The launch's `questions` line and the latest `head` line, once
        /// let go: a report starts with them, so its passes read whole.
        var questions: [UInt8]?
        var head: [UInt8]?

        public init() {
            text.reserveCapacity(Recent.maxBytes / 8 * 9 + (16 << 10))
        }

        public func add(_ line: String) {
            starts.append(text.count)
            text += line.utf8
            text.append(0x0A)
            while text.count - starts[dropped] > Recent.maxBytes, starts.count - dropped > 1 {
                let gone = text[starts[dropped]..<starts[dropped + 1]]
                if gone.starts(with: DebugLog.questionsLine) { questions = Array(gone) }
                if gone.starts(with: DebugLog.headLine) { head = Array(gone) }
                dropped += 1
            }
            // Compacted now and then, not on every drop: what's let go is
            // at most an eighth more.
            guard starts[dropped] > Recent.maxBytes / 8 else { return }
            let cut = starts[dropped]
            text.removeFirst(cut)
            starts = starts[dropped...].map { $0 - cut }
            dropped = 0
        }

        /// The kept lines, oldest first, each ending in a newline.
        public var bytes: ArraySlice<UInt8> { text[(starts.isEmpty ? 0 : starts[dropped])...] }

        /// What a report writes, in order: the `questions` and `head` lines
        /// let go, then the kept lines.
        public var pieces: [ArraySlice<UInt8>] { [questions, head].compactMap { $0?[...] } + [bytes] }
    }

    /// How a `questions` line and a `head` line start.
    static let questionsLine = Array(#"{"questions":"#.utf8), headLine = Array(#"{"head":"#.utf8)

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
    /// for the first pass (the latest `head` line's before it, with the
    /// pass's HISTORY and NOW), then only its HISTORY and NOW, which are
    /// what change. Of the raw events only actions are printed: the view
    /// says the rest.
    ///
    ///     ▸ 12 tool end: claude's tests failed on "fix-nav" (landing).
    ///       pass jev:jev-latest 240 ms: mood grumpy 0.69 · react annoyed 0.63 · react.loops twice 0.58 · say.feeling upset 0.57 · say.about tests 0.74 · say.kind sound 0.81
    ///       ✓ mood: Boop's mood changed: happy → grumpy.
    ///       … react: Boop made an annoyed face, held twice, and said "Tsk... Test"
    ///       ✓ react (15) done
    public final class Printer {
        var shownFullState = false
        /// The latest `head` line's before the first pass, which prints it.
        var head = ""

        public init() {}

        /// Takes lines without printing them, for `boopdev watch --new`,
        /// which starts at the file's end: only the latest `head` line of
        /// them counts, so the first pass still prints the head in force.
        public func skip(_ lines: Data) {
            guard let head = lines.split(separator: 0x0A).last(where: { $0.starts(with: DebugLog.headLine) }) else { return }
            _ = readable(String(decoding: head, as: UTF8.self))
        }

        /// Nil for a line it doesn't print: the dashboard's, `head` (the
        /// first pass prints the latest before it), and raw events other
        /// than actions.
        public func readable(_ line: String) -> String? {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: .fragmentsAllowed) as? [String: Any]
            else { return line }
            if let head = o["head"] as? String {
                if !shownFullState { self.head = head }
                return nil
            }
            if let v = o["view"] as? [String: Any] {
                let name = [v["type"] as? String ?? "?", v["phase"] as? String].compactMap { $0 }.joined(separator: " ")
                var out = "▸ \(v["id"] as? Int ?? 0) \(name)\(v["wakes_brain"] as? Bool == true ? "" : " (no pass)"): "
                    + (v["line"] as? String ?? "")
                for note in v["notes"] as? [String] ?? [] { out += "\n    " + note }
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
                    // Older logs' passes carry the whole state.
                    let shown = shownFullState ? StateText.split(state).last : head + state
                    shownFullState = true
                    out += "\n" + shown.split(separator: "\n", omittingEmptySubsequences: false).map { "    │ " + $0 }.joined(separator: "\n")
                }
                return out
            }
            if let raw = o["event"] as? [String: Any], let e = Event(json: raw) ?? Event.legacy(JSONLine.encode(raw)) {
                let by = e["by"]?.string == "rule" || e.type == .needsYou ? " (rule)" : ""
                if e.type == .needsYou {
                    return e.phase == .end ? "  · \(Core.needsYou)\(by) ended" + (e["why"]?.string.map { ": \($0)" } ?? "")
                        : "  … \(Core.needsYou)\(by): \(e["message"]?.string ?? "")"
                }
                guard e.isKit, let name = e.action else { return nil }
                if e.kind == Event.ended {
                    let what = "\(name) (\(e.about ?? 0))"
                    return e["outcome"]?.string == "done" ? "  ✓ \(what) done"
                        : "  ✗ \(what) didn't happen: \(e["why"]?.string ?? "?")"
                }
                guard e.kind == Event.did else { return nil }
                let mark = e["ok"]?.bool != true ? "✗" : e["open"]?.bool == true ? "…" : "✓"
                return "  \(mark) \(name)\(by): \(e["message"]?.string ?? "")"
            }
            return nil
        }
    }
}

extension StateText {
    /// The state's head (the guide, PERSONALITY and MOOD), which changes
    /// only with the personality or the mood, and its HISTORY and NOW,
    /// which `debug.jsonl` logs apart.
    static func split(_ state: String) -> (head: String, last: String) {
        guard let r = state.range(of: "HISTORY (") else { return ("", state) }
        return (String(state[..<r.lowerBound]), String(state[r.lowerBound...]))
    }
}
