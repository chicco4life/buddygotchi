import Foundation

/// Whether Boop's mood changes, and to what (harness/DECISIONS.md §4). The
/// mood's file becomes MOOD in Jev's state from the next pass.
public final class MoodAction: Action {
    public let name = "mood"
    let store: MoodStore
    let now: () -> Int64

    public init(store: MoodStore, now: @escaping () -> Int64) {
        self.store = store
        self.now = now
    }

    /// Each mood and its meaning, the `mood` question's criterion. Each also
    /// has a file in plan/steering/mood/.
    public static let moods: [Option] = [
        Option("cheerful", "Good spirits: things are going fine, or a struggle just ended well."),
        Option("grumpy", "Fed up: failures have piled up, or it's been poked too much."),
    ]

    /// The mood changes at most this often, so it doesn't flicker.
    public static let minimumGapMs: Int64 = 10 * 60_000

    public func questions() -> [Question] {
        [Question(key: "mood", text: "After NOW, what is Boop's mood?", about: "the NOW and HISTORY sections",
                  judgeBy: "the MOOD section, its reason to leave", options: Self.moods)]
    }

    public func run(_ answers: Answers) -> ActionResult? {
        guard let to = answers["mood"]?.choice, to != store.current,
              Self.moods.contains(where: { $0.name == to }) else { return nil }
        if let changed = store.changedAtMs, now() - changed < Self.minimumGapMs {
            return .failed("changed \((now() - changed) / 60_000) min ago")
        }
        let from = store.current
        do {
            try store.set(to, at: now())
        } catch {
            return .failed("couldn't save the mood: \(error)")
        }
        return .done("Boop's mood changed: \(from) → \(to).")
    }
}

/// The only reader and writer of the state directory's `mood` file: one
/// word. A missing or unknown word reads as `cheerful`.
public final class MoodStore: @unchecked Sendable {
    public static let fileName = "mood"
    let file: URL
    public private(set) var current: String
    /// When it last changed, in this run: a restart forgets it, so the
    /// first change after one is never held back.
    public private(set) var changedAtMs: Int64?

    public init(stateDir: URL) {
        file = stateDir.appendingPathComponent(Self.fileName)
        let saved = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        current = saved.flatMap { s in MoodAction.moods.contains { $0.name == s } ? s : nil } ?? "cheerful"
    }

    public func set(_ mood: String, at ms: Int64) throws {
        try Data((mood + "\n").utf8).write(to: file, options: .atomic)
        current = mood
        changedAtMs = ms
    }
}
