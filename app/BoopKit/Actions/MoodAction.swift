import Foundation

/// Whether Boop's mood changes, and to what (harness/DECISIONS.md §4). The
/// mood's file becomes MOOD in Jev's state from the next pass, and the
/// device gets it in the next `state`. Jev can only keep the mood or move
/// it one step along the mood graph (`MoodGraph`); how long a mood lasts,
/// and which move fits NOW, is the steering's to say, not a rule's.
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
    /// the mood files' minutes need no sums. Nil while calm, the resting
    /// mood every other fades toward, and before a change since launch.
    public func sinceLine(at now: Int64) -> String? {
        guard store.current != MoodAction.initial, let at = changedAt else { return nil }
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "Boop has been \(store.current) for \(span)."
    }

    /// Each mood and its meaning, the `mood` question's criterion, in the
    /// device's order (`MoodGraph.moods`). Each also has a file in
    /// plan/steering/mood/, and a set of faces on the device.
    public static let moods: [Option] = [
        Option("happy", "Good spirits: work is going well, or a win just came; or excited or proud cooling down."),
        Option("excited", "Thrilled: a very long turn finished done, or the person thanked the agent.",
               notFor: "A shorter turn finishing, or work still going."),
        Option("proud", "Something hard-won worked: a check passed after failing, or a long turn's last message says hard work is done and working.",
               notFor: "A short turn finishing."),
        Option("curious", "Intrigued: a poke, or something new or puzzling said to Boop.",
               notFor: "A failure, or routine work: a turn starting or finishing, even one asking or answering a question."),
        Option("determined", "Rooting for a retry: a check failed again while the agent works on, the person sounds frustrated, or a very long turn works on. Straining, unlike engaged.",
               notFor: "A turn that has ended."),
        Option("grumpy", "Fed up: a turn failed on top of other trouble, or pokes kept coming. The angriest, past irritated.",
               notFor: "A check failing, the person's frustration, or an agent giving up."),
        Option("sad", "Deflated: the agent says it couldn't do it or is stuck, or a very long turn finished failed.",
               notFor: "A shorter turn that finished failed with an error."),
        Option("calm", "Settled, the resting mood: nothing much is going on, or a mood cooling down once its minutes are up."),
        Option("engaged", "In the flow: following steady work that goes well, or determined easing off. At ease, unlike determined: nothing has failed."),
        Option("annoyed", "Mildly put out: a failure, the person's frustration, or pokes; or grumpy or irritated cooling down. Milder than irritated, and not yet rooting for a retry like determined.",
               notFor: "The agent saying it couldn't do it or is stuck, or a very long turn failing: those make Boop sad."),
        Option("irritated", "Patience fraying: failures or pokes keep coming. More than annoyed, short of grumpy."),
        Option("whiny", "Sorry for itself, asking for sympathy: things keep going wrong. It complains, unlike wounded."),
        Option("wounded", "Hurt: rude words to Boop, or a big failure after a lot of work. It withdraws quietly, unlike whiny."),
    ]

    /// The resting mood: a new state directory starts in it, a saved word
    /// Boop doesn't know reads as it, and every mood fades toward it.
    public static let initial = "calm"

    /// A dramatic move's "not for" (harness/DECISIONS.md §2.3): it's a jump
    /// only a fresh, big event earns.
    public static let jump = "A check failing or passing, routine work, or a fade: this jump needs a fresh, big event in NOW, such as a turn that finished failed, the agent giving up, a barrage of pokes, a long turn finishing, thanks or rude words."

    /// The `mood` question's options for `mood`: stay, then each of its
    /// neighbours with its meaning, the dramatic ones also saying they're a
    /// jump. Nothing else: Jev never sees a move the graph doesn't have.
    public static func options(from mood: String) -> [Option] {
        let meaning = { (name: String) in moods.first { $0.name == name }! }
        let moves = MoodGraph.moves[mood] ?? MoodGraph.moves[initial]!
        return [Option(mood, "Stay \(mood): NOW is no reason MOOD gives to leave it, nor are its minutes up. No change is fine.")]
            + moves.ordinary.map(meaning)
            + moves.dramatic.map(meaning).map { o in
                Option(o.name, o.what, notFor: [o.notFor, jump].compactMap { $0 }.joined(separator: " "))
            }
    }

    /// Built on every pass from the saved mood, so the options are always
    /// that mood's own.
    public func questions() -> [Question] {
        [Question(key: "mood", text: "After NOW, what is Boop's mood?", about: "the NOW and HISTORY sections",
                  judgeBy: "the MOOD section, its reason to leave", options: Self.options(from: store.current))]
    }

    /// Jev's answer: staying, or a move the graph has from the mood as it
    /// is. Anything else changes nothing.
    public func run(_ answers: Answers) -> ActionResult? {
        guard let to = answers["mood"]?.choice, to != store.current, MoodGraph.isMove(from: store.current, to: to) else {
            return nil
        }
        return change(to: to)
    }

    /// Changes the mood now to any of the moods, as `run` does for Jev but
    /// off the graph, with a result for the current mood or one that isn't
    /// a mood: the dashboard sets one through here.
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
/// word. A missing file reads as the resting mood; so does a word that
/// isn't a mood, which is logged; and `cheerful`, happy's old name, reads
/// as happy.
public final class MoodStore: @unchecked Sendable {
    public static let fileName = "mood"
    let file: URL
    public private(set) var current: String

    public init(stateDir: URL, log: (String) -> Void = { _ in }) {
        file = stateDir.appendingPathComponent(Self.fileName)
        let saved = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let word = saved, !word.isEmpty {
            if word == "cheerful" {
                current = "happy"
            } else if MoodAction.moods.contains(where: { $0.name == word }) {
                current = word
            } else {
                current = MoodAction.initial
                log("mood: the mood file says \(word), which isn't a mood; reading it as \(MoodAction.initial)")
            }
        } else {
            current = MoodAction.initial
        }
    }

    public func set(_ mood: String) throws {
        try Data((mood + "\n").utf8).write(to: file, options: .atomic)
        current = mood
    }
}
