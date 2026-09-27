import Foundation

/// What the core decided. The app hands each effect to the part that carries
/// it out: snapshots, moments and mumbles (built by Voice) to the device
/// link, events to the harness, and a new day to the memory store. The
/// core itself never builds speech, writes files or talks to the device.
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// A rule reaction: play `anim`, `loops` times (PROTOCOL.md §3).
    case moment(anim: String, loops: Int)
    /// Working chatter: a rule mumble.
    case mumble(feeling: String, word: String?)
    /// Something that happened, for the harness (harness/EVENTS.md).
    case event(Event)
    /// The first activity of a new day: short-term starts fresh.
    case newDay(date: String)

    /// The effect on one line, for `boopdev replay` and debug mode:
    /// `moment cheer`, `moment cheer ×2`, `mumble curious tests`.
    public var summary: String {
        switch self {
        case .state(let s): "state " + s.jsonLine
        case .moment(let anim, let loops): "moment \(anim)" + (loops == 1 ? "" : " ×\(loops)")
        case .mumble(let feeling, let word): "mumble \(feeling)" + (word.map { " \($0)" } ?? "")
        case .event(let e): "event " + e.summary
        case .newDay(let date): "new-day \(date)"
        }
    }
}
