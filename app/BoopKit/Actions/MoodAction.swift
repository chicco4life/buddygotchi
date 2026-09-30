import Foundation

/// Boop's mood (harness/DECISIONS.md §4): the brain kit's `Choice`
/// (kit/BRAIN-KIT.md §6), its value the latest change in the log. MOOD in
/// Jev's state is the mood's file from the next pass, and the device gets
/// it in the next `state` (the runtime's rule on the change). Jev can only
/// keep the mood or move it one step along the mood graph (`MoodGraph`):
/// those are all it's offered. How long a mood lasts, and which move fits
/// NOW, is the steering's to say, not a rule's.
public enum MoodAction {
    public static let actionName = "mood"

    /// How long Boop has been in its mood, for the line that closes HISTORY
    /// (harness/HARNESS.md §5.3): `Boop has been proud for 7 min.`, so
    /// the mood files' minutes need no sums. Nil while calm, the resting
    /// mood every other fades toward, and before any change in the log.
    public static func sinceLine(_ mood: Choice, _ log: LogView, at now: Int64) -> String? {
        let current = value(mood, log)
        guard current != initial, let at = mood.since(log) else { return nil }
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "Boop has been \(current) for \(span)."
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
        Option("sad", "Deflated: the agent says it couldn't do it or is stuck, a very long turn finished failed, or the person shared sad news.",
               notFor: "A shorter turn that finished failed with an error."),
        Option("calm", "Settled, the resting mood: nothing much is going on, a mood cooling down once its minutes are up, or the person took back what upset Boop."),
        Option("engaged", "In the flow: following steady work that goes well, or determined easing off. At ease, unlike determined: nothing has failed."),
        Option("annoyed", "Mildly put out: a failure, the person's frustration, or pokes; or grumpy or irritated cooling down or softening at an apology. Milder than irritated, and not yet rooting for a retry like determined.",
               notFor: "The agent saying it couldn't do it or is stuck, or a very long turn failing: those make Boop sad."),
        Option("irritated", "Patience fraying: failures or pokes keep coming; or grumpy softening at an apology. More than annoyed, short of grumpy."),
        Option("whiny", "Sorry for itself, asking for sympathy: things keep going wrong. It complains, unlike wounded."),
        Option("wounded", "Hurt: rude words to Boop, or a big failure after a lot of work. It withdraws quietly, unlike whiny."),
    ]

    /// The resting mood: a new state directory starts in it, a saved word
    /// Boop doesn't know reads as it, and every mood fades toward it.
    public static let initial = "calm"

    /// A dramatic move's "not for" (harness/DECISIONS.md §2.3): it's a jump
    /// only a fresh, big event earns.
    public static let jump = "A check failing or passing, routine work, or a fade: this jump needs a fresh, big event in NOW, such as a turn that finished failed, the agent giving up, a barrage of pokes, a long turn finishing, thanks, rude words or sad news."

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

    /// Boop's mood as the kit's `Choice`: its question, offered stay and
    /// the mood graph's moves from the mood it has (`options(from:)`), and
    /// the line a change shows.
    public static func choice() -> Choice {
        Choice(name: actionName, start: initial, question: "After NOW, what is Boop's mood?",
               about: "the NOW and HISTORY sections", judgeBy: "the MOOD section, its reason to leave",
               said: { from, to in "Boop's mood changed: \(from) → \(to)." },
               options: { current, _, _ in options(from: known(current)) })
    }

    /// The mood as the log has it: the choice's value, read as the resting
    /// mood if it isn't one of the moods.
    public static func value(_ mood: Choice, _ log: LogView) -> String { known(mood.value(log)) }

    static func known(_ word: String) -> String { moods.contains { $0.name == word } ? word : initial }

    /// Changes the mood now to any of the moods, off the graph, with a
    /// result for the current mood or one that isn't a mood: the dashboard
    /// sets one through here.
    public static func change(_ mood: Choice, to: String, log: LogView) -> ActionResult {
        guard moods.contains(where: { $0.name == to }) else { return .failed("\(to) isn't a mood") }
        let from = value(mood, log)
        guard to != from else { return .failed("already \(to)") }
        return mood.set(to, log: log) ?? .failed("already \(to)")
    }
}
