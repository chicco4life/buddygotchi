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
          lines indented under it are what Boop did. The last line lists the
          threads still working.
        - A line of what Boop did may end in brackets: (in progress) means it
          hasn't finished yet, and (didn't happen: …) means it never did, and
          why.
        - NOW is what to react to. Its second line is what Boop already did on
          its own, by reflex.
        """

    public struct Parts: Sendable {
        public var guide: String
        public var personality: String
        public var mood: String
        /// The status line that closes HISTORY.
        public var status: String
        /// How far back HISTORY reaches at most: the oldest working turn's start.
        public var workingSince: Int64?
        /// `14:23, Tuesday`, for NOW's heading.
        public var clock: String

        public init(guide: String, personality: String, mood: String, status: String, workingSince: Int64?,
                    clock: String) {
            self.guide = guide
            self.personality = personality
            self.mood = mood
            self.status = status
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
            history(entries, now: now, at: nowMs, status: parts.status, workingSince: parts.workingSince),
            nowSection(now, clock: parts.clock),
        ].joined(separator: "\n\n")
    }

    /// HISTORY, built step by step as §5.3 says.
    public static func history(_ entries: [Transcript.Entry], now: Transcript.Entry, at nowMs: Int64, status: String,
                               workingSince: Int64?) -> String {
        let from = min(nowMs - historyMs, workingSince ?? Int64.max)
        let picked = entries.filter { e in
            guard case .event = e.body else { return false }
            return e.seq < now.seq && e.receivedAtMs >= from
        }.suffix(historyLimit)
        var lines = ["HISTORY (oldest first; indented lines are what Boop did)"]
        for e in picked {
            guard case .event(let event) = e.body else { continue }
            lines.append("\(ago(nowMs - e.receivedAtMs)): \(event.line)")
            for did in didLines(for: e, event: event, in: entries) { lines.append("  " + did) }
        }
        lines.append(status)
        return lines.joined(separator: "\n")
    }

    /// NOW: its heading, its line, and its rule reaction.
    public static func nowSection(_ now: Transcript.Entry, clock: String) -> String {
        guard case .event(let event) = now.body else { return "NOW (\(clock))" }
        return "NOW (\(clock))\n\(event.line)\n\(event.reaction ?? "Boop did nothing on its own.")"
    }

    /// What Boop did about an event: its rule reaction, then the messages of
    /// its successful actions, in order. A forced action, which is for no
    /// event, counts as done about the latest event before it. A started
    /// one is `(in progress)` until it settles, then plain if it was done,
    /// or `(didn't happen: why)`.
    static func didLines(for entry: Transcript.Entry, event: Event, in entries: [Transcript.Entry]) -> [String] {
        var lines = event.reaction.map { [$0] } ?? []
        var latest = true
        /// Started actions shown here: their line's index and message.
        var started: [Int: (index: Int, message: String)] = [:]
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
                case .failed(let why): lines[placed.index] = placed.message + " (didn't happen: \(why))"
                }
            default: break
            }
        }
        return lines
    }

    /// `just now`, `9 min ago`, `2 h ago`.
    public static func ago(_ ms: Int64) -> String {
        ms < 60_000 ? "just now" : ms < 60 * 60_000 ? "\(ms / 60_000) min ago" : "\(ms / 3_600_000) h ago"
    }
}
