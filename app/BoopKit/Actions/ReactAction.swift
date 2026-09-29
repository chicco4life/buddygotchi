import Foundation

/// Whether Boop reacts to NOW: with which mood's face, which animation,
/// for how long, and what it says (harness/DECISIONS.md §5). A reaction
/// is a mood × a visual for a moment: the device draws that mood's design
/// of whatever look is showing, or of the animation picked (a turn's
/// finish: task_complete for its outcome, or reply_ready), for a number of
/// its loops (PROTOCOL.md §3). Jev picks what Boop says as a meaning and a
/// kind, and Voice finds a recorded take of it in the face's mood, or none,
/// and then the face plays in silence. It plays once any line or
/// reaction's face playing has finished. It's started, not done, until
/// whoever plays the moment ends its handle.
public final class ReactAction: Action {
    public let name = "react"
    let voice: Voice
    /// Queues a brain moment, which waits its turn behind whatever is
    /// playing, with the handle to end once the device says how it ended,
    /// or once it never will.
    let queue: (DeviceMoment, Pending) -> Void
    /// Why a reaction can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// The agent and thread NOW is about, or nil (a poke, an idle
    /// heartbeat): a finish names it on the device.
    let who: () -> DeviceMoment.Who?
    /// Picks among the takes that fit, and remembers the last one said,
    /// which isn't said again while another fits.
    var takes = SplitMix64(seed: 0x7A4E)
    var lastTake: String?
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
    /// moment's face only, never the lasting mood. What it says is a take
    /// performed in that mood (`Voice`).
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

    /// What a reaction can mean, in the order `say.meaning` offers them
    /// (DECISIONS.md §3). Voice's takes each have one; a meaning with no
    /// take isn't offered, and a test checks every take's has its words
    /// here.
    public static let meanings = [
        Option("begin", "A turn starting: off it goes.", notFor: "Work going on, or a turn that finished."),
        Option("work", "Steady work going on, going well.", notFor: "A failure, or a turn that finished."),
        Option("effort", "Straining: long or hard work going on.", notFor: "A turn that finished."),
        Option("ponder", "Puzzled or curious: a question, or something new or confusing.", notFor: "A failure."),
        Option("success", "A turn finished, done and working.", notFor: "Anything but a success."),
        Option("celebrate", "A big win: a long or very long turn done, or thanks.", notFor: "A short turn done, or anything but a win."),
        Option("relief", "Relief: it worked in the end.", notFor: "Anything but a success, or a first try."),
        Option("pride", "Smug: something long or hard finished well.", notFor: "Anything but a success, or a small win."),
        Option("delight", "Tickled: a win, a poke or kind words.", notFor: "A failure."),
        Option("frustration", "Something failed or keeps failing: a check, a turn, or the agent giving up.", notFor: "A win."),
        Option("retry", "The same thing again: a retry, or the person saying it's still broken.", notFor: "A first failure."),
    ]

    /// How a reaction says its meaning (DECISIONS.md §3), plainest first:
    /// with none of the kind asked for, Voice steps down to a plainer one.
    public static let kinds = [
        Option("sound", "A noise with no word: a huff, a grunt, a gasp. The usual."),
        Option("word", "One word that names the moment.", notFor: "A routine check-in."),
        Option("phrase", "A little catchphrase, for a moment worth remembering, now and then.",
               notFor: "Routine work, or a small win or failure."),
        Option("swear", "A swear, at a failure that really stings.",
               notFor: "A win, a poke, words to Boop, or anything about the person."),
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

    /// Below this, Jev is guessing, and silence beats a guessed meaning
    /// (DECISIONS.md §5).
    public static let sayFloor = 0.35

    /// What the reaction means (DECISIONS.md §5): `say.meaning`'s pick if
    /// it isn't `none` and reaches the floor, else nil.
    public static func meaning(_ answers: Answers) -> String? {
        guard let a = answers["say.meaning"], a.choice != "none", a.p >= sayFloor,
              meanings.contains(where: { $0.name == a.choice }) else { return nil }
        return a.choice
    }

    /// How it says it: `say.kind`'s pick, or a sound when it's missing.
    public static func kind(_ answers: Answers) -> Take.Kind {
        answers["say.kind"].flatMap { Take.Kind(rawValue: $0.choice) } ?? .sound
    }

    /// `say.meaning`'s options: `none`, then each meaning Voice has a take
    /// of, naming the faces that can say it, so Jev can pick a face and a
    /// meaning that go together.
    func meaningOptions() -> [Option] {
        let have = voice.meanings
        return [Option("none", "Say nothing: nothing in NOW is worth a word or a sound.")]
            + Self.meanings.filter { have.contains($0.name) }.map { m in
                let faces = voice.faces(saying: m.name, in: MoodAction.moods.map(\.name)).joined(separator: ", ")
                return Option(m.name, m.what + " Only these faces can say it: \(faces).", notFor: m.notFor)
            }
    }

    public func questions() -> [Question] {
        let byBoth = "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"
        return [
            Question(key: "react.mood", text: "How should Boop react to NOW, if at all? It makes this mood's face for a moment, and may say something.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face, "
                                          + "or HISTORY shows Boop still making the one it calls for (in progress).",
                                      notFor: "Anything PERSONALITY's Examples react to that Boop isn't already doing.")]
                         + Self.expressions),
            Question(key: "react.animation", text: "If Boop reacts and NOW's line is a turn that finished, how did the turn end?",
                     about: "the NOW section", judgeBy: "NOW's line and the agent's last message under it",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed. A turn starting, a check passing or failing (tests, a build, a deploy), a poke, a check-in, words to Boop and a stopped turn all get none.")]
                         + Self.animations),
            Question(key: "react.loops", text: "If Boop reacts, how long does it hold the face?", about: "the NOW section",
                     judgeBy: byBoth, options: Self.holds),
            Question(key: "say.meaning", text: "If Boop reacts, what does it say about NOW? It says it in its face's mood.",
                     about: "the NOW section", judgeBy: byBoth, options: meaningOptions()),
            Question(key: "say.kind", text: "If Boop says something, how does it say it?", about: "the NOW section",
                     judgeBy: byBoth, options: Self.kinds),
        ]
    }

    public func run(_ answers: Answers) -> ActionResult? {
        // 1. Does Jev want a reaction at all, and with which face?
        guard let choice = answers["react.mood"]?.choice, Self.expressions.contains(where: { $0.name == choice }) else {
            return nil
        }
        // 2. This action's own rules.
        if let why = blocked() { return .failed(why) }
        // 3. The effect: the face, and the take it says, if Voice has one
        // for the meaning in this face's mood and the turn's finish.
        let loops = Self.loops(answers)
        let pick = Self.animation(answers)
        let take = Self.meaning(answers).flatMap {
            voice.take(meaning: $0, kind: Self.kind(answers), face: choice, finish: pick, avoiding: lastTake, rng: &takes)
        }
        if let take { lastTake = take.id }
        var moment = DeviceMoment(say: DeviceMoment.Say(take: take), mood: choice, loops: loops)
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
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the moment ended.
        let did = pick.map { "Boop played \(Self.article($0)) \($0) in \(Self.article(choice)) \(choice) face" }
            ?? "Boop made \(Self.article(choice)) \(choice) face"
        return .started(did + ", held \(Self.holds[loops - 1].name)" + (take.map { ", and said \"\($0.text)\"." } ?? "."), pending)
    }
}
