import Foundation

/// Whether Boop's mood changes, and to what (harness/DECISIONS.md §4). The
/// mood's file becomes MOOD in Jev's state from the next pass, and the
/// device gets it in the next `state`. How long a mood lasts is the
/// steering's to say, not a rule's.
public final class MoodAction: Action {
    public static let actionName = "mood"
    public let name = MoodAction.actionName
    let store: MoodStore
    /// Called with the new mood once it's saved, so the device hears of it.
    let changed: (String) -> Void
    /// The time, on the harness's clock.
    let clock: () -> Int64
    /// When this action last changed the mood, on `clock`; nil before it
    /// has since launch.
    var changedAt: Int64?

    public init(store: MoodStore, clock: @escaping () -> Int64 = { 0 }, changed: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.clock = clock
        self.changed = changed
    }

    /// How long Boop has been in its mood, for the lines that close HISTORY
    /// (harness/HARNESS.md §5.3): `Boop has been proud for 7 min.`, so
    /// the mood files' minutes need no sums. Nil while happy, where every
    /// mood fades to, and before a change since launch.
    public func sinceLine(at now: Int64) -> String? {
        guard store.current != MoodAction.initial, let at = changedAt else { return nil }
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "Boop has been \(store.current) for \(span)."
    }

    /// Each mood and its meaning, the `mood` question's criterion. Each also
    /// has a file in plan/steering/mood/, and a face on the device.
    public static let moods: [Option] = [
        Option("happy", "Good spirits: things are going fine."),
        Option("excited", "Thrilled: a very long turn finished done.",
               notFor: "A shorter turn finishing, or work still going."),
        Option("proud", "Something hard-won worked: a check passed after failing.",
               notFor: "A turn finishing."),
        Option("determined", "Rooting for a retry: a check failed and the agent is working on.",
               notFor: "A turn that has ended."),
        Option("grumpy", "Fed up, briefly: a turn failed, or Boop was poked again and again.",
               notFor: "A check failing while the agent works on."),
        Option("sad", "Deflated: a very long turn finished failed.",
               notFor: "A shorter turn failing."),
    ]

    /// The mood a new state directory starts in.
    public static let initial = "happy"

    public func questions() -> [Question] {
        [Question(key: "mood", text: "After NOW, what is Boop's mood?", about: "the NOW and HISTORY sections",
                  judgeBy: "the MOOD section, its reason to leave", options: Self.moods)]
    }

    public func run(_ answers: Answers) -> ActionResult? {
        guard let to = answers["mood"]?.choice, to != store.current,
              Self.moods.contains(where: { $0.name == to }) else { return nil }
        return change(to: to)
    }

    /// Changes the mood now, as `run` does for Jev, but with a result for
    /// the current mood or one that isn't a mood: the dashboard sets one
    /// through here.
    public func change(to: String) -> ActionResult {
        guard Self.moods.contains(where: { $0.name == to }) else { return .failed("\(to) isn't a mood") }
        guard to != store.current else { return .failed("already \(to)") }
        let from = store.current
        do {
            try store.set(to)
        } catch {
            return .failed("couldn't save the mood: \(error)")
        }
        changedAt = clock()
        changed(to)
        return .done("Boop's mood changed: \(from) → \(to).")
    }
}

/// The only reader and writer of the state directory's `mood` file: one
/// word. A missing or unknown word reads as `happy`, and so do `cheerful`,
/// happy's old name, and `curious`, which the brain no longer picks.
public final class MoodStore: @unchecked Sendable {
    public static let fileName = "mood"
    let file: URL
    public private(set) var current: String

    public init(stateDir: URL) {
        file = stateDir.appendingPathComponent(Self.fileName)
        let saved = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        current = saved.flatMap { s in MoodAction.moods.contains { $0.name == s } ? s : nil } ?? MoodAction.initial
    }

    public func set(_ mood: String) throws {
        try Data((mood + "\n").utf8).write(to: file, options: .atomic)
        current = mood
    }
}
