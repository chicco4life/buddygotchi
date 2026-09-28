import Foundation

/// Whether Boop's mood changes, and to what (harness/DECISIONS.md §4). The
/// mood's file becomes MOOD in Jev's state from the next pass, and the
/// device gets it in the next `state`. How long a mood lasts is the
/// steering's to say, not a rule's.
public final class MoodAction: Action {
    public let name = "mood"
    let store: MoodStore
    /// Called with the new mood once it's saved, so the device hears of it.
    let changed: (String) -> Void

    public init(store: MoodStore, changed: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.changed = changed
    }

    /// Each mood and its meaning, the `mood` question's criterion. Each also
    /// has a file in plan/steering/mood/, and a face on the device.
    public static let moods: [Option] = [
        Option("happy", "Good spirits: things are going fine."),
        Option("excited", "Thrilled: things are going right, such as a third clean finish in a row, or a clean turn of 5 minutes or more.",
               notFor: "One or two routine wins."),
        Option("proud", "Something hard-won worked: a fix after a failure, or a turn of 5 minutes or more that fought through failures.",
               notFor: "A routine finish, however long."),
        Option("determined", "Rooting for a retry: something failed and the agent is working on.",
               notFor: "A turn that has ended."),
        Option("grumpy", "Fed up, briefly: a turn failed, 3 or more failures in a row, or poked too much.",
               notFor: "A single failure in a turn still working."),
        Option("sad", "Deflated: a turn of 5 minutes or more ended failing, or was stopped with failures left."),
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
