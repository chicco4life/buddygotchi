import Foundation

/// What the core decided. The app hands each effect to the part that carries
/// it out: moments and mumbles to the `react` action, snapshots to the device
/// link, inputs and asides to the harness, and the rest to the memory store.
/// The core itself never builds speech, writes files or talks to the device.
public enum CoreEffect: Equatable, Sendable {
    /// A new snapshot, sent because something on it changed.
    case state(StateSnapshot)
    /// A rule reaction: play `anim` once (the `react` action's `play`).
    case moment(anim: String)
    /// A rule mumble (a `react` call).
    case mumble(feeling: String, word: String?)
    /// One of the inputs for the brain's pipeline (HARNESS.md §2).
    case input(Input)
    /// Something that happened, for the harness (harness/EVENTS.md).
    case event(Event)
    /// Something only the rules handled, for the brain's transcript: a tap,
    /// or something needing you (HARNESS.md §4).
    case aside(String)
    /// A line for `short-term.md`'s Happened section.
    case happened(String)
    /// The first activity of a new day: short-term starts fresh.
    case newDay(date: String, firstSeen: String)
    /// Push-to-talk: start (true) or stop listening on the Mac's mic.
    case listen(Bool)
    /// Ends the device's `listening` face: the empty moment (PROTOCOL.md §3).
    case endListening

    /// The effect on one line, for `boopdev replay` and debug mode:
    /// `moment cheer`, `mumble curious tests`.
    public var summary: String {
        switch self {
        case .state(let s): "state " + s.jsonLine
        case .moment(let anim): "moment \(anim)"
        case .mumble(let feeling, let word): "mumble \(feeling)" + (word.map { " \($0)" } ?? "")
        case .input(let i): "input " + i.line + (i.words.map { " \"\($0)\"" } ?? "")
        case .aside(let line): "aside " + line
        case .event(let e): "event " + e.summary
        case .happened(let line): "happened \(line)"
        case .newDay(let date, let firstSeen): "new-day \(date) first seen \(firstSeen)"
        case .listen(let on): "listen \(on)"
        case .endListening: "moment empty"
        }
    }
}
