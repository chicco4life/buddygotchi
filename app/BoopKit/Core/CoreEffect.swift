import Foundation

/// What the core decided. The app hands each effect to the part that carries
/// it out: snapshots to the device link, events to the harness, and a new
/// day to the memory store. The core itself never builds speech, writes
/// files or talks to the device, and makes no moment: every mumble and
/// face is the brain's (BEHAVIORS.md §1).
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// The session list changed but the snapshot didn't, as when a second
    /// idle session starts: only the popover and `debug.jsonl`'s `status`
    /// show it.
    case sessions
    /// Something that happened, for the harness (harness/EVENTS.md).
    case event(Event)
    /// The first activity of a new day: short-term starts fresh.
    case newDay(date: String)

    /// The effect on one line, for `boopdev replay` and debug mode.
    public var summary: String {
        switch self {
        case .state(let s): "state " + s.jsonLine
        case .sessions: "sessions"
        case .event(let e): "event " + e.summary
        case .newDay(let date): "new-day \(date)"
        }
    }
}
