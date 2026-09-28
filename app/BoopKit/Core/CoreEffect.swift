import Foundation

/// What the core decided. The app hands each effect to the part that carries
/// it out: snapshots and the rules' one-shots to the device link, what it
/// did by rule to the transcript, and a new day to the memory store. The
/// core itself never builds speech, writes files or talks to the device:
/// every mumble, and every face but the look and the rules' one-shots, is
/// the brain's (BEHAVIORS.md §1, §3.1).
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// The session list changed but the snapshot didn't, as when a second
    /// idle session starts: only the popover and `debug.jsonl`'s `status`
    /// show it.
    case sessions
    /// What the rules did, as an `action` event for the transcript
    /// (harness/EVENTS.md §2): recorded after the event that caused it.
    case record(Event)
    /// The first activity of a new day: short-term starts fresh.
    case newDay(date: String)
    /// Push-to-talk: turn the Mac's mic on or off, after `by`'s button
    /// (BEHAVIORS.md §3.3).
    case listen(Bool, by: Core.Talker)
    /// A rule's one-shot for the device (BEHAVIORS.md §3.1), after the
    /// snapshot of the same input: `starting`, `stopped`, `error` or
    /// `helper_return`, with no `id`, which no brain waits on.
    case moment(DeviceMoment)

    /// The effect on one line, for `boopdev replay` and debug mode.
    public var summary: String {
        switch self {
        case .state(let s): "state " + s.jsonLine
        case .sessions: "sessions"
        case .record(let e): "record " + e.summary
        case .newDay(let date): "new-day \(date)"
        case .listen(let on, let by): "listen \(on ? "on" : "off") (\(by.rawValue))"
        case .moment(let m): "moment " + m.jsonLine
        }
    }
}
