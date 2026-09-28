import Foundation

/// Whether Boop reacts to NOW: with which mood's face, which animation,
/// for how long, and with which real word (harness/DECISIONS.md §5). A
/// reaction is a mood × a visual for a moment: the device draws that
/// mood's design of whatever look is showing, or of the animation picked
/// (a turn's finish: task_complete for its outcome, or reply_ready), for
/// a number of its loops (PROTOCOL.md §3). It comes with a Minion line
/// from Voice, and plays once any line or reaction's face playing has
/// finished. It's started, not done, until whoever plays the moment ends
/// its handle.
public final class ReactAction: Action {
    public let name = "react"
    let voice: Voice
    /// Queues a brain moment, which waits its turn behind whatever is
    /// playing, with the handle to end once the device says how it ended,
    /// or once it never will.
    let queue: (DeviceMoment, Pending) -> Void
    /// Why a mumble can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// The agent and thread NOW is about, or nil (a poke, an idle
    /// heartbeat): a finish names it on the device.
    let who: () -> DeviceMoment.Who?
    /// Each line gets the next seed, so a logged line can be replayed.
    var seed: UInt64 = 0
    /// Picks each finish's variation, never the last one of its animation
    /// (BEHAVIORS.md §5).
    var variants = SplitMix64(seed: 0xB00B)
    var lastVariant: [String: Int] = [:]

    public init(voice: Voice, queue: @escaping (DeviceMoment, Pending) -> Void, blocked: @escaping () -> String?,
                who: @escaping () -> DeviceMoment.Who? = { nil }) {
        self.voice = voice
        self.queue = queue
        self.blocked = blocked
        self.who = who
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// Each expression: a mood's name, in `MoodAction.moods`' order, and
    /// what the face means for this moment (DECISIONS.md §3). It's the
    /// moment's face only, never the lasting mood. Voice picks the sound
    /// (`Voice.feeling(forMood:)`).
    public static let expressions = [
        Option("happy", "A happy face: pleased, a turn went fine or a small win."),
        Option("excited", "An excited face: something big just went right."),
        Option("proud", "A proud face: something long or hard just finished, or finally worked."),
        Option("curious", "A curious face: a poke, a question, or something new or puzzling.",
               notFor: "A failure."),
        Option("determined", "A determined face: a check failed and the agent is trying again, or long work goes on.",
               notFor: "A turn that has ended."),
        Option("grumpy", "A grumpy face: a turn failed, or Boop is poked three or more times in a row.",
               notFor: "An agent giving up."),
        Option("sad", "A sad face: a very long turn ended failed, or the agent gave up, stuck.",
               notFor: "A shorter turn failing with an error, or a check failing."),
        Option("calm", "A calm face: all is well, and nothing stands out."),
        Option("engaged", "An engaged face: following work that's going well.", notFor: "A failure."),
        Option("annoyed", "An annoyed face: a small failure, or poked twice in a row, a little miffed."),
        Option("irritated", "An irritated face: failures or pokes that keep coming."),
        Option("whiny", "A whiny face: things keep going wrong, and Boop feels sorry for itself."),
        Option("wounded", "A wounded face: rude words to Boop, or a big failure after a lot of work."),
    ]

    public static let exclamations = [
        Option("finally", "Something worked after failing.", notFor: "A first try."),
        Option("yay", "A big win: a very long turn done.", notFor: "A shorter turn done."),
        Option("nice", "A solid win: a long turn done.", notFor: "A short or very long turn, or a turn ending just after its fix."),
        Option("oops", "Something just failed, once.", notFor: "A failure that keeps repeating."),
        Option("again", "The same thing failed again.", notFor: "A first failure."),
        Option("ugh", "Frustration: things keep going badly."),
        Option("nope", "Poked three or more times in a row, or refusing."),
        Option("hmm", "Unsure, something new, or a little miffed."),
    ]

    public static let topics = [
        Option("tests", "NOW is about tests.", notFor: "A build or a deploy."),
        Option("build", "NOW is about a build.", notFor: "Tests."),
        Option("deploy", "NOW is about a deploy."),
        Option("docs", "NOW is about docs."),
        Option("bug", "NOW is about a bug: your prompt or the agent's last message says one was hunted or fixed.",
               notFor: "A failed check or turn with no word of a bug."),
        Option("merge", "NOW is git work: a commit, merge, push or pull request, as your prompt or the agent's last message says."),
        Option("review", "NOW is a review of code or a pull request, as your prompt or the agent's last message says."),
        Option("claude", "NOW is a claude turn ending (done, stopped or failed) that isn't about any other topic word: its name, only as a filler.",
               notFor: "claude still working (a check-in), codex's work, a poke, or words about a bug, git work, a review or any other topic: that topic's word wins."),
        Option("codex", "NOW is a codex turn ending (done, stopped or failed) that isn't about any other topic word: its name, only as a filler.",
               notFor: "codex still working (a check-in), claude's work, a poke, or words about a bug, git work, a review or any other topic: that topic's word wins."),
    ]

    /// The animations a reaction can play in its face (DECISIONS.md §3): a
    /// turn's finish, judged from what NOW says. No rule plays a finish,
    /// so the brain judges each one's outcome.
    public static let animations = [
        Option("success", "NOW's line says a turn finished, done, and its last message, if any, says the work is done and working.",
               notFor: "A check that passed while the turn goes on, a turn that finished failed, a message saying it couldn't finish or something is broken, or only an answer or a question back."),
        Option("failure", "NOW's line says a turn finished, failed; or finished done, but its last message says the agent couldn't finish or something is broken.",
               notFor: "A check that failed while the turn goes on, or a turn done whose message says the work is working."),
        Option("reply", "NOW's line says a turn finished, done, and its last message only answers something or asks something back, often with no tool calls: no task finished.",
               notFor: "Work done, a turn that finished failed, or anything but a turn that finished."),
    ]

    /// The animation `react.animation` picked, or nil for none, a missing
    /// answer or one the device doesn't play.
    public static func animation(_ answers: Answers) -> String? {
        let pick = answers["react.animation"]?.choice
        return animations.contains { $0.name == pick } ? pick : nil
    }

    /// What the device plays for an animation pick (PROTOCOL.md §3): the
    /// face's task_complete scene for a success or a failure, with that
    /// outcome, and its reply_ready for a reply.
    public static func finish(_ pick: String) -> (anim: String, outcome: String?) {
        switch pick {
        case "success", "failure": ("task_complete", pick)
        default: ("reply_ready", nil)
        }
    }

    /// How long the face holds, in loops of the design it's drawn in: the
    /// first holds once, and each one after a loop more (DECISIONS.md §5).
    public static let holds = [
        Option("once", "A small moment: the usual."),
        Option("twice", "A moment that stands out.", notFor: "Routine work."),
        Option("three times", "A big moment, such as a check passing after failing."),
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
            Question(key: "react.animation", text: "If Boop reacts and NOW's line is a turn that finished, how did the turn end?",
                     about: "the NOW section", judgeBy: "NOW's line and the agent's last message under it",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed. A turn starting, a check passing or failing (tests, a build, a deploy), a poke, a check-in, words to Boop and a stopped turn all get none.")]
                         + Self.animations),
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
        let pick = Self.animation(answers)
        var moment = DeviceMoment(say: line, mood: choice, loops: loops)
        if let pick {
            // A finish: its scene, a variation of it for its outcome in the
            // face's design (never the last one), and whose turn it was.
            let (anim, outcome) = Self.finish(pick)
            let variant = Core.pickVariant(mood: choice, state: anim, outcome: outcome, avoiding: lastVariant[anim], &variants)
            lastVariant[anim] = variant
            moment.anim = anim
            moment.outcome = outcome
            moment.variant = variant
            moment.who = who()
        }
        let pending = Pending()
        queue(moment, pending)
        // 5. What it started, as its line in HISTORY: in progress until
        // the device says how the moment ended.
        let did = pick.map { "Boop played \(Self.article($0)) \($0) in \(Self.article(choice)) \(choice) face" }
            ?? "Boop made \(Self.article(choice)) \(choice) face"
        return .started(did + ", held \(Self.holds[loops - 1].name), and mumbled"
                        + (word.map { " \"…\($0)!\"" } ?? "."), pending)
    }
}
