import Foundation

/// Builds Jev's state for one pass (harness/HARNESS.md §5.3, §6): the guide
/// with how to read the rest, PERSONALITY, MOOD, then HISTORY and NOW from
/// the view. A pure function of what it's given: the same inputs always
/// give the same text. It never writes a view event's line or an action's
/// message; it only places them, and marks a started action's progress.
public enum StateText {
    /// HISTORY reaches back this far, or to the oldest turn still working,
    /// whichever is further, and holds at most `historyLimit` events.
    public static let historyMs: Int64 = 10 * 60_000
    public static let historyLimit = 40

    /// The layout part of how to read HISTORY and NOW (§6.1).
    public static let reading = """
        How to read HISTORY and NOW:
        - HISTORY is oldest first. Each line says how long ago it happened.
          Lines indented under it add to it: an agent's last message, then
          what Boop did. A line of what Boop did ending in (in progress)
          hasn't finished yet.
        - NOW is what to react to. Its last line is what Boop already did on
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

    /// The whole state for the pass on the view event `now`, from the view
    /// events before it.
    public static func build(_ events: [ViewEvent], now: ViewEvent, at nowMs: Int64, _ parts: Parts) -> String {
        [
            parts.guide + "\n" + reading + "\n" + EventLine.words,
            parts.personality,
            parts.mood,
            history(events, now: now, at: nowMs, closing: parts.closing, workingSince: parts.workingSince),
            nowSection(events.last { $0.id == now.id } ?? now, clock: parts.clock),
        ].joined(separator: "\n\n")
    }

    /// HISTORY, built step by step as §5.3 says.
    public static func history(_ events: [ViewEvent], now: ViewEvent, at nowMs: Int64, closing: String?,
                               workingSince: Int64?) -> String {
        let from = min(nowMs - historyMs, workingSince ?? Int64.max)
        let inRange = events.filter { $0.id < now.id && $0.ts >= from }
        // The newest 40, and any older one whose started action is still in
        // progress: Boop is still doing it, so a pass must see it.
        let picked = inRange.dropLast(historyLimit).filter { $0.did.contains { $0.state == .inProgress } }
            + inRange.suffix(historyLimit)
        var lines = ["HISTORY (oldest first; indented lines add to the line above)"]
        for e in picked {
            lines.append("\(ago(nowMs - e.ts)): \(e.line)")
            for note in e.notes { lines.append("  " + note) }
            for did in didLines(e) { lines.append("  " + did) }
        }
        if let closing { lines.append(closing) }
        return lines.joined(separator: "\n")
    }

    /// NOW: its heading, its line and notes, and what Boop did by rule.
    public static func nowSection(_ now: ViewEvent, clock: String) -> String {
        let reflex = now.did.filter { $0.by == "rule" }.map(\.message)
        return (["NOW (\(clock))", now.line] + now.notes.map { "  " + $0 }
            + (reflex.isEmpty ? ["Boop did nothing on its own."] : reflex)).joined(separator: "\n")
    }

    /// What Boop did about an event, in order: a started action is `(in
    /// progress)` until it ends. One that didn't happen is already gone.
    static func didLines(_ e: ViewEvent) -> [String] {
        e.did.map { $0.state == .inProgress ? $0.message + " (in progress)" : $0.message }
    }

    /// `just now`, `9 min ago`, `2 h ago`.
    public static func ago(_ ms: Int64) -> String {
        ms < 60_000 ? "just now" : ms < 60 * 60_000 ? "\(ms / 60_000) min ago" : "\(ms / 3_600_000) h ago"
    }
}
