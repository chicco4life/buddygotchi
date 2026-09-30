import JHarness
import LinkKit

/// A ready-made JHarness output (jharness/SPEC.md §5): the brain picks one
/// of the device's `do` names, or none, and the device plays it with
/// `play: next`. The options are `none`, then the names the app describes
/// that the device's `hello` says it plays, in the app's order: with no
/// device, or before its `hello`, only `none`. It returns `.started` with a
/// `Pending` the device's `ended` finishes (`DeviceLink.end`), so HISTORY shows
/// it in progress until then.
///
/// Its `run` is called on the harness's queue, which must be the link's.
public final class Play: Action {
    public let name: String
    let link: DeviceLink
    let question: String
    let about: String
    let judgeBy: String
    let none: Option
    let described: [Option]
    let said: (String) -> String
    let clock: () -> Int64

    /// `options` are the names the app describes, with what each means;
    /// `said` is HISTORY's line for a name played; `clock` the link's, in
    /// ms.
    public init(name: String = "play", link: DeviceLink, question: String, about: String = "the NOW section", judgeBy: String,
                none: Option = Option("none", "Play nothing: nothing in NOW is worth it."), options: [Option],
                said: @escaping (String) -> String = { "The device played \($0)." }, clock: @escaping () -> Int64) {
        self.name = name
        self.link = link
        self.question = question
        self.about = about
        self.judgeBy = judgeBy
        self.none = none
        self.described = options
        self.said = said
        self.clock = clock
    }

    /// What the brain is offered now: `none`, then the described names the
    /// device plays.
    public var options: [Option] {
        let does = Set(link.hello?.does ?? [])
        return [none] + described.filter { does.contains($0.name) }
    }

    public func questions(now: Event?, log: LogView) -> [Question] {
        [Question(key: name, text: question, about: about, judgeBy: judgeBy, options: options)]
    }

    /// `none`, or a name it wasn't offered, does nothing.
    public func run(_ answers: Answers, now: Event?, log: LogView) -> ActionResult? {
        guard let pick = answers[name]?.choice, pick != none.name, options.contains(where: { $0.name == pick }) else {
            return nil
        }
        let pending = Pending()
        link.do(pick, play: .next, by: .brain, now: clock(), pending: pending)
        return .started(said(pick), pending)
    }
}
