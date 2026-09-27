import Foundation

/// Whether Boop mumbles about NOW, in which feeling, and with which real
/// word (harness/DECISIONS.md §5). A mumble is a Minion line from Voice in
/// the feeling's voice, sent as a moment with no animation, so it plays
/// over whatever face is showing, after whatever is playing.
public final class ReactAction: Action {
    public let name = "react"
    let voice: Voice
    /// Queues a brain moment: it waits its turn behind whatever is playing.
    let queue: (DeviceMoment) -> Void
    /// Why a mumble can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// Each line gets the next seed, so a logged line can be replayed.
    var seed: UInt64 = 0

    public init(voice: Voice, queue: @escaping (DeviceMoment) -> Void, blocked: @escaping () -> String?) {
        self.voice = voice
        self.queue = queue
        self.blocked = blocked
    }

    /// Each feeling, its meaning, and the Voice feeling it mumbles in.
    public static let feelings: [(option: Option, voice: Feeling)] = [
        (Option("happy", "Pleased and friendly: a turn went fine, a small win."), .happy),
        (Option("excited", "Thrilled: something big just went right."), .excited),
        (Option("proud", "Something long or hard just finished, or finally worked."), .proud),
        (Option("curious", "Interested or unsure: something new started, or it's not clear how it's going."), .curious),
        (Option("annoyed", "Irritated: a turn failed, tests keep failing, or it's being poked too much."), .annoyed),
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
            Question(key: "react", text: "How should Boop react to NOW, if at all?", about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a mumble.",
                                      notFor: "Anything PERSONALITY's Examples mumble for.")] + Self.feelings.map(\.option)),
            Question(key: "word.feeling", text: "If Boop mumbles, which exclamation fits NOW?", about: "the NOW section",
                     judgeBy: byBoth, options: [Option("none", "No exclamation fits NOW.")] + Self.exclamations),
            Question(key: "word.about", text: "If Boop mumbles, which topic word is NOW about?", about: "the NOW section",
                     judgeBy: "the PERSONALITY section's Examples",
                     options: [Option("none", "No topic word fits NOW.")] + Self.topics),
        ]
    }

    public func run(_ answers: Answers) -> ActionResult? {
        // 1. Does Jev want a mumble at all?
        guard let choice = answers["react"]?.choice,
              let feeling = Self.feelings.first(where: { $0.option.name == choice }) else { return nil }
        // 2. The word: the exclamation if Jev is sure enough, else the topic, else none.
        let word = Self.word(answers)
        // 3. This action's own rules.
        if let why = blocked() { return .failed(why) }
        // 4. The effect.
        seed += 1
        queue(DeviceMoment(say: voice.line(feeling.voice, word: word, seed: seed)))
        // 5. What happened, as its line in HISTORY.
        return .done("Boop mumbled, \(choice)" + (word.map { ": \"…\($0)!\"" } ?? "."))
    }
}
