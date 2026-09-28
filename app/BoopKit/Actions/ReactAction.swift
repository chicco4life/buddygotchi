import Foundation

/// Whether Boop reacts to NOW: with which mood's face, which animation,
/// for how long, and with which real word (harness/DECISIONS.md §5). A
/// reaction is a mood × a visual for a moment: the device draws that
/// mood's design of whatever look is showing, or of the animation picked
/// (the cheer), for a number of its loops (PROTOCOL.md §3). It comes with
/// a Minion line from Voice, and plays once any line or reaction's face
/// playing has finished. It's started, not done, until whoever plays the
/// moment ends its handle.
public final class ReactAction: Action {
    public let name = "react"
    let voice: Voice
    /// Queues a brain moment, which waits its turn behind whatever is
    /// playing, with the handle to end once the device says how it ended,
    /// or once it never will.
    let queue: (DeviceMoment, Pending) -> Void
    /// Why a mumble can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// The time, on the harness's clock.
    let clock: () -> Int64
    /// Each line gets the next seed, so a logged line can be replayed.
    var seed: UInt64 = 0
    /// The last few reactions it started, newest last: each one's face,
    /// animation, word, when, and its handle (DECISIONS.md §5).
    var made: [(face: String, anim: String?, word: String?, at: Int64, pending: Pending)] = []

    public init(voice: Voice, queue: @escaping (DeviceMoment, Pending) -> Void, blocked: @escaping () -> String?,
                clock: @escaping () -> Int64) {
        self.voice = voice
        self.queue = queue
        self.blocked = blocked
        self.clock = clock
    }

    /// Boop's last reaction and how long ago it started, for the line
    /// before the status line that closes HISTORY (harness/HARNESS.md
    /// §5.3): `Boop's last reaction, just now: an excited face and
    /// "…tests!".` One that didn't happen doesn't count; nil before any.
    public func lastLine(at now: Int64) -> String? {
        let happened = made.last { if case .failed = $0.pending.ended { false } else { true } }
        guard let last = happened else { return nil }
        return "Boop's last reaction, \(StateText.ago(now - last.at)): "
            + (last.anim.map { "\(Self.article($0)) \($0) in \(Self.article(last.face)) \(last.face) face" }
                ?? "\(Self.article(last.face)) \(last.face) face")
            + (last.word.map { " and \"…\($0)!\"." } ?? ", with no word.")
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// Each expression: a mood's name, in `MoodAction.moods`' order, and
    /// what the face means for this moment (DECISIONS.md §3). Voice picks
    /// the sound (`Voice.feeling(forMood:)`).
    public static let expressions = [
        Option("happy", "A happy face: pleased, a turn went fine or a small win."),
        Option("excited", "An excited face: something big just went right."),
        Option("proud", "A proud face: something long or hard just finished, or finally worked."),
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

    /// The animations a reaction can play in its face (DECISIONS.md §3):
    /// today only the cheer, the mood's task-complete scene. No rule
    /// cheers, so this is the only way a finish is celebrated.
    public static let animations = [
        Option("cheer", "Something just finished or finally worked, and it stands out.",
               notFor: "A routine finish, a failure, or anything still going."),
    ]

    /// The animation `react.animation` picked, or nil for none, a missing
    /// answer or one the device doesn't play.
    public static func animation(_ answers: Answers) -> String? {
        let pick = answers["react.animation"]?.choice
        return animations.contains { $0.name == pick } ? pick : nil
    }

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
            Question(key: "react.mood", text: "How should Boop react to NOW, if at all? It makes this mood's face for a moment, with a mumble.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face and a mumble, "
                                          + "or HISTORY shows Boop still making the one it calls for (in progress).",
                                      notFor: "Anything PERSONALITY's Examples react to that Boop isn't already doing.")]
                         + Self.expressions),
            Question(key: "react.animation", text: "If Boop reacts, does it play an animation?", about: "the NOW section",
                     judgeBy: byBoth,
                     options: [Option("none", "Just the face, over whatever look is showing: the usual.")] + Self.animations),
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
        // 1. Does Jev want a reaction at all, and with which face?
        guard let choice = answers["react.mood"]?.choice, Self.expressions.contains(where: { $0.name == choice }) else {
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
        let anim = Self.animation(answers)
        let pending = Pending()
        made = made.suffix(4) + [(choice, anim, word, clock(), pending)]
        queue(DeviceMoment(anim: anim, say: line, mood: choice, loops: loops), pending)
        // 5. What it started, as its line in HISTORY: in progress until
        // the device says how the moment ended.
        let did = anim.map { "Boop played \(Self.article($0)) \($0) in \(Self.article(choice)) \(choice) face" }
            ?? "Boop made \(Self.article(choice)) \(choice) face"
        return .started(did + ", held \(Self.holds[loops - 1].name), and mumbled"
                        + (word.map { " \"…\($0)!\"" } ?? "."), pending)
    }
}
