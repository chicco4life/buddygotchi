import Foundation

/// Builds Jev's state for one pass (harness/HARNESS.md §5.3, §6): the guide
/// with how to read the rest, PERSONALITY, MOOD, then HISTORY and NOW from
/// the transcript. A pure function of what it's given: the same inputs
/// always give the same text. It never writes an event's line or an
/// action's message; it only places them, and marks a started action's
/// progress.
public enum StateText {
    /// HISTORY reaches back this far, or to the oldest turn still working,
    /// whichever is further, and holds at most `historyLimit` events.
    public static let historyMs: Int64 = 10 * 60_000
    public static let historyLimit = 40

    /// The layout part of how to read HISTORY and NOW (§6.1).
    public static let reading = """
        How to read HISTORY and NOW:
        - HISTORY is oldest first. Each line says how long ago it happened, and
          lines indented under it are what Boop did. A line of what Boop did
          ending in (in progress) hasn't finished yet.
        - NOW is what to react to. Its second line is what Boop already did on
          its own, by reflex.
        """

    public struct Parts: Sendable {
        public var guide: String
        public var personality: String
        public var mood: String
        /// The line that closes HISTORY, how long Boop has been in its
        /// mood, or nil for none.
        public var closing: String?
        /// How far back HISTORY reaches at most: the oldest working turn's start.
        public var workingSince: Int64?
        /// `14:23, Tuesday`, for NOW's heading.
        public var clock: String

        public init(guide: String, personality: String, mood: String, closing: String?, workingSince: Int64?,
                    clock: String) {
            self.guide = guide
            self.personality = personality
            self.mood = mood
            self.closing = closing
            self.workingSince = workingSince
            self.clock = clock
        }
    }

    /// The whole state for the pass on the event `now`.
    public static func build(_ entries: [Transcript.Entry], now: Transcript.Entry, at nowMs: Int64, _ parts: Parts) -> String {
        [
            parts.guide + "\n" + reading + "\n" + EventLine.words,
            parts.personality,
            parts.mood,
            history(entries, now: now, at: nowMs, closing: parts.closing, workingSince: parts.workingSince),
            nowSection(now, clock: parts.clock),
        ].joined(separator: "\n\n")
    }

    /// HISTORY, built step by step as §5.3 says.
    public static func history(_ entries: [Transcript.Entry], now: Transcript.Entry, at nowMs: Int64, closing: String?,
                               workingSince: Int64?) -> String {
        let from = min(nowMs - historyMs, workingSince ?? Int64.max)
        let inRange = entries.filter { e in
            guard case .event = e.body else { return false }
            return e.seq < now.seq && e.receivedAtMs >= from
        }
        // The newest 40, and any older one whose started action is still in
        // progress: Boop is still doing it, so a pass must see it.
        let open = inProgress(entries)
        let picked = inRange.dropLast(historyLimit).filter { open.contains($0.seq) } + inRange.suffix(historyLimit)
        var lines = ["HISTORY (oldest first; indented lines are what Boop did)"]
        for e in picked {
            guard case .event(let event) = e.body else { continue }
            lines.append("\(ago(nowMs - e.receivedAtMs)): \(event.line)")
            for did in didLines(for: e, event: event, in: entries) { lines.append("  " + did) }
        }
        if let closing { lines.append(closing) }
        return lines.joined(separator: "\n")
    }

    /// The events with a started action still in progress: under its
    /// event, or, forced, the latest event before it, as `didLines` places
    /// it.
    static func inProgress(_ entries: [Transcript.Entry]) -> Set<Int> {
        var latest: Int?
        var open: [Int: Int] = [:]  // the action entry's seq: its event's
        for e in entries {
            switch e.body {
            case .event: latest = e.seq
            case .action(let a) where a.result.ok && a.result.pending != nil:
                if let about = a.forSeq ?? latest { open[e.seq] = about }
            case .settle(let s): open[s.forSeq] = nil
            default: break
            }
        }
        return Set(open.values)
    }

    /// NOW: its heading, its line, and its rule reaction.
    public static func nowSection(_ now: Transcript.Entry, clock: String) -> String {
        guard case .event(let event) = now.body else { return "NOW (\(clock))" }
        return "NOW (\(clock))\n\(event.line)\n\(event.reaction ?? "Boop did nothing on its own.")"
    }

    /// What Boop did about an event: its rule reaction, then the messages of
    /// its successful actions, in order. A forced action, which is for no
    /// event, counts as done about the latest event before it. A started
    /// one is `(in progress)` until it settles, then plain if it was done;
    /// one that didn't happen isn't shown.
    static func didLines(for entry: Transcript.Entry, event: Event, in entries: [Transcript.Entry]) -> [String] {
        var lines = event.reaction.map { [$0] } ?? []
        var latest = true
        /// Started actions shown here: their line's index and message.
        var started: [Int: (index: Int, message: String)] = [:]
        /// The lines of started actions that didn't happen.
        var gone: Set<Int> = []
        for e in entries where e.seq > entry.seq {
            switch e.body {
            case .event: latest = false
            case .action(let a) where a.result.ok && (a.forSeq == entry.seq || (a.forSeq == nil && latest)):
                if a.result.pending != nil {
                    started[e.seq] = (lines.count, a.result.message)
                    lines.append(a.result.message + " (in progress)")
                } else {
                    lines.append(a.result.message)
                }
            case .settle(let s):
                guard let placed = started[s.forSeq] else { break }
                switch s.end {
                case .done: lines[placed.index] = placed.message
                case .failed: gone.insert(placed.index)
                }
            default: break
            }
        }
        return lines.indices.filter { !gone.contains($0) }.map { lines[$0] }
    }

    /// `just now`, `9 min ago`, `2 h ago`.
    public static func ago(_ ms: Int64) -> String {
        ms < 60_000 ? "just now" : ms < 60 * 60_000 ? "\(ms / 60_000) min ago" : "\(ms / 3_600_000) h ago"
    }
}
