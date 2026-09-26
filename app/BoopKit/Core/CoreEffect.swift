import Foundation

/// A trigger for the harness (HARNESS.md §5).
public struct Trigger: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case event, tap, talk, reflect

        /// Event, tap and talk share one conversation with the brain
        /// (HARNESS.md §4). Reflection is one call on its own.
        public var converses: Bool { self != .reflect }

        /// The tools a call for this trigger may use. Conversation calls are
        /// offered every conversing kind's tools, the same list each time,
        /// and one outside this list is shown as a limit (HARNESS.md §5).
        public var tools: [String] {
            switch self {
            case .event: ["say", "face"]
            case .tap: ["say", "face"]
            case .talk: ["say", "face", "quiet", "note"]
            // Not `forget`: Apple's model deleted true facts with it
            // (ARCHITECTURE.md §11). Reflection only adds.
            case .reflect: ["remember", "temperament", "moment"]
            }
        }

        /// The tools offered: every conversing kind's for a conversation call,
        /// so the list never changes within a conversation; reflection's own.
        public var offered: [String] {
            guard converses else { return tools }
            var names: [String] = []
            for kind in Kind.allCases where kind.converses {
                for tool in kind.tools where !names.contains(tool) { names.append(tool) }
            }
            return names
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

        /// How often a tool may run for this trigger (HARNESS.md §5). Past its
        /// limit the prompt says so and the harness drops a call to it, so
        /// Boop stays quiet most of the time whatever the brain would answer.
        public var limits: [ToolLimit] {
            switch self {
            case .event: [ToolLimit("say", everyMs: 600_000, neverOn: ["turn started"])]
            case .tap: [ToolLimit("say", everyMs: 300_000)]
            case .talk, .reflect: []
            }
        }
    }

    public var kind: Kind
    /// What happened, e.g. `turn finished · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday`.
    public var line: String
    /// Only for `talk`: the person's words. Kept in the brain's conversation
    /// until it starts over, in memory only.
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
