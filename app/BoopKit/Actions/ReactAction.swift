import Foundation

/// Whether Boop reacts to NOW, with which face, for how long, and with
/// which real word (harness/DECISIONS.md §5). The face is one of the seven
/// moods': the device borrows that mood's design of whatever look is
/// showing, for a number of its loops (PROTOCOL.md §3). It comes with a
/// Minion line from Voice, and goes as a moment with no animation, so it
/// plays over whatever is showing once any line playing has finished. It's
/// started, not done, until whoever plays the moment ends its handle.
public final class ReactAction: Action {
    public let name = "react"
    let voice: Voice
    /// Queues a brain moment, which waits its turn behind whatever is
    /// playing, with the handle to end once the device says how it ended,
    /// or once it never will.
    let queue: (DeviceMoment, Pending) -> Void
    /// Why a mumble can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// Each line gets the next seed, so a logged line can be replayed.
    var seed: UInt64 = 0

    public init(voice: Voice, queue: @escaping (DeviceMoment, Pending) -> Void, blocked: @escaping () -> String?) {
        self.voice = voice
        self.queue = queue
        self.blocked = blocked
    }

    /// Each expression: a mood's name, in `MoodAction.moods`' order, and
    /// what the face means for this moment (DECISIONS.md §3). Voice picks
    /// the sound (`Voice.feeling(forMood:)`).
    public static let expressions = [
        Option("happy", "A happy face: pleased, a turn went fine or a small win."),
        Option("excited", "An excited face: something big just went right."),
        Option("proud", "A proud face: something long or hard just finished, or finally worked."),
        Option("curious", "A curious face: something new started, or it's not clear how it's going."),
        Option("determined", "A determined face: something failed and the agent is trying again.",
               notFor: "A turn that has ended, or the same failure 3 or more times in a row."),
        Option("grumpy", "A grumpy face: a turn failed, the same thing keeps failing, or Boop is poked too much."),
        Option("sad", "A sad face: a turn of 10 minutes or more ended failing, or was stopped with failures left.",
               notFor: "A short turn failing, or a single failure."),
    ]

    public static let exclamations = [
        Option("finally", "Something worked after failing.", notFor: "A first try."),
        Option("yay", "A win."),
        Option("oops", "Something just failed, once.", notFor: "A failure that keeps repeating."),
        Option("again", "The same thing failed again.", notFor: "A first failure."),
        Option("ugh", "Frustration: things keep going badly."),
        Option("nope", "Poked too much, or refusing."),
        Option("hmm", "Unsure, or something new."),
    ]

    public static let topics = [
        Option("tests", "NOW is about tests.", notFor: "A build or a deploy."),
        Option("build", "NOW is about a build.", notFor: "Tests."),
        Option("deploy", "NOW is about a deploy."),
        Option("docs", "NOW is about docs."),
    ]

    /// How long the face holds, in loops of the design it's drawn in: the
    /// first holds once, and each one after a loop more (DECISIONS.md §5).
    public static let holds = [
        Option("once", "A small moment: the usual."),
        Option("twice", "A moment that stands out.", notFor: "Routine work."),
        Option("three times", "A big moment, such as a comeback."),
        Option("four times", "The biggest moments: a hard-won finish, or a failure that keeps coming back.",
               notFor: "A single win or failure."),
    ]

    /// How many loops the face holds: `react.loops`' pick, or once when
    /// it's missing.
    public static func loops(_ answers: Answers) -> Int {
        (holds.firstIndex { $0.name == answers["react.loops"]?.choice } ?? 0) + 1
    }

    /// Below this, Jev is guessing, and no word beats a guessed one
    /// (DECISIONS.md §5).
    public static let wordFloor = 0.35

    /// The mumble's word (DECISIONS.md §5): `word.feeling`'s pick if it
    /// isn't `none` and reaches the floor, else `word.about`'s, else none.
    public static func word(_ answers: Answers) -> String? {
        ["word.feeling", "word.about"].compactMap { answers[$0] }
            .first { $0.choice != "none" && $0.p >= wordFloor }?.choice
    }

    public func questions() -> [Question] {
        let byBoth = "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"
        return [
            Question(key: "react", text: "How should Boop react to NOW, if at all? It makes this face for a moment, with a mumble.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face and a mumble.",
                                      notFor: "Anything PERSONALITY's Examples react to.")] + Self.expressions),
            Question(key: "react.loops", text: "If Boop reacts, how long does it hold the face?", about: "the NOW section",
                     judgeBy: byBoth, options: Self.holds),
            Question(key: "word.feeling", text: "If Boop mumbles, which exclamation fits NOW?", about: "the NOW section",
                     judgeBy: byBoth, options: [Option("none", "No exclamation fits NOW.")] + Self.exclamations),
            Question(key: "word.about", text: "If Boop mumbles, which topic word is NOW about?", about: "the NOW section",
                     judgeBy: "the PERSONALITY section's Examples",
                     options: [Option("none", "No topic word fits NOW.")] + Self.topics),
        ]
    }

    public func run(_ answers: Answers) -> ActionResult? {
        // 1. Does Jev want a reaction at all?
        guard let choice = answers["react"]?.choice, Self.expressions.contains(where: { $0.name == choice }) else {
            return nil
        }
        // 2. The word: the exclamation if Jev is sure enough, else the topic, else none.
        let word = Self.word(answers)
        // 3. This action's own rules.
        if let why = blocked() { return .failed(why) }
        // 4. The effect.
        seed += 1
        // The face holds its loops, and at least as long as the line plays.
        let line = voice.line(Voice.feeling(forMood: choice), word: word, seed: seed)
        let loops = Self.loops(answers)
        let pending = Pending()
        queue(DeviceMoment(say: line, mood: choice, loops: loops), pending)
        // 5. What it started, as its line in HISTORY: in progress until
        // the device says how the moment ended.
        let article = "aeiou".contains(choice.first!) ? "an" : "a"
        return .started("Boop made \(article) \(choice) face, held \(Self.holds[loops - 1].name), and mumbled"
                        + (word.map { " \"…\($0)!\"" } ?? "."), pending)
    }
}
