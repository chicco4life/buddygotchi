import Foundation

/// A trigger for the harness (HARNESS.md §5).
public struct Trigger: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case event, tap, talk, reflect

        /// The tools the harness offers for this trigger.
        public var tools: [String] {
            switch self {
            case .event: ["say", "face", "note"]
            case .tap: ["say", "face"]
            case .talk: ["say", "face", "quiet", "note"]
            case .reflect: ["remember", "forget", "temperament", "moment"]
            }
        }

        /// Milliseconds before a late answer is dropped.
        public var deadlineMs: Int {
            switch self {
            case .event: 5000
            case .tap: 3000
            case .talk: 4000
            case .reflect: 600_000
            }
        }
    }

    public var kind: Kind
    /// What happened, e.g. `turn finished · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday`.
    public var line: String
    /// Only for `talk`: the person's words, dropped after the call.
    public var words: String?
    public var ts: Int64

    public init(kind: Kind, line: String, words: String? = nil, ts: Int64) {
        self.kind = kind
        self.line = line
        self.words = words
        self.ts = ts
    }
}

/// What the core decided. The app hands each effect to the part that carries
/// it out: moments and mumbles to the `face` and `say` actions, snapshots to
/// the device link, triggers to the harness, and the rest to the memory store.
/// The core itself never builds speech, writes files or talks to the device.
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// A rule reaction: play `anim` once (the `face` action).
    case moment(anim: String, size: Int)
    /// A rule mumble (the `say` action).
    case mumble(feeling: String, word: String?)
    case trigger(Trigger)
    /// A line for `short-term.md`'s Happened section.
    case happened(String)
    /// Growth changed; the memory store writes it to `long-term.md`.
    case growth(Growth)
    /// The first activity of a new day: short-term starts fresh.
    case newDay(date: String, firstSeen: String, mood: String)
    /// Push-to-talk: start (true) or stop listening on the Mac's mic.
    case listen(Bool)
}
