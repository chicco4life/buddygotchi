import Foundation

/// What plays on the device and until when (ARCHITECTURE.md §3.2). The
/// tap's poke, which the device plays on its own, and the rules'
/// one-shots play at once; a rule's one-shot never cuts a brain moment's
/// line, though. The brain's moments wait
/// their turn: one at a time, each once the line playing has finished, and
/// a reaction's face too unless it's the brain's own, held on for its
/// loops after its take: the next reaction replaces that, so none cuts
/// off a line and a held face doesn't hold up the next reaction. A
/// reaction that plays an animation (the finish) holds the line until it
/// ends, since the next would cut it. One with no animation plays over a
/// poke without cutting it. One that has waited longer
/// than `maxWaitMs` for its turn is dropped, since a late reaction is worse
/// than none, and its handle ends as failed (harness/DECISIONS.md §5).
///
/// The app reckons how long each moment plays at most, as the device times
/// it (PROTOCOL.md §3). A brain moment sent with an `id` holds the line
/// until the device's `ended` says it's over, which is usually sooner (a
/// face ends on a loop boundary), and at most until the
/// app stops waiting for that `ended`, whatever the Mac hears meanwhile of
/// a tap or the link dropping. For the brain's next moment it holds the line
/// only until its take has played (`brainFree`). The schedule also hears what the device
/// does on its own or leaves out: a tap's poke replaces the animation
/// playing, though a line plays on over it,
/// "needs you" starting stops everything, and while something needs you
/// no moment plays.
///
/// Each brain moment goes to the device with an id, and its handle ends
/// when the device says how it ended, or when it can't have played
/// (harness/DECISIONS.md §5).
///
/// On a caller's clock, so the runtime can drive it with a timer and the
/// tests without one. It changes nothing but itself and the handles of
/// its moments.
public struct MomentSchedule {
    /// A brain moment that has waited longer than this for its turn is
    /// dropped (ARCHITECTURE.md §3.2).
    public static let maxWaitMs: Int64 = 5000
    /// How late the pump may run after a moment's turn came and still
    /// count its wait to when the turn came. Later than that, the wait is
    /// counted to now, so a moment held up by a Mac asleep is dropped.
    public static let lateMs: Int64 = 1000
    /// How long past a take's reckoned end it may still be playing on
    /// the device, since every line reaches it a little after it's sent.
    public static let linkSlackMs: Int64 = 500
    /// How long past a moment's expected end the app waits for the
    /// device's `ended` before giving up on it (PROTOCOL.md §6).
    public static let endGraceMs: Int64 = 3000
    /// The largest id a moment goes out with: the device keeps ids in
    /// 32 bits, and JSON readers anywhere take this as a plain int.
    public static let maxId = Int(Int32.max)
    /// Taps in a row, as the device counts them (BEHAVIORS.md §3.3): a tap
    /// within `tapRunMs` of the one before is another in the run, and from
    /// its `tapSpamFrom`-th on the device plays tap_spam instead of poked.
    /// The same numbers as `TranscriptView.Config`'s `inARowMs` and
    /// `answersRunFrom`, and the firmware's `Behaviour::kTapRunMs` and
    /// `kTapSpamFrom`: change them together.
    public static let tapRunMs: Int64 = 3000
    public static let tapSpamFrom = 3

    /// When the animation playing with no line ends: a tap's poke, or a
    /// rule's one-shot.
    public private(set) var animUntil: Int64 = 0
    /// When the line playing ends, and with it a reaction's face, as the
    /// app reckons it; or when the device said the brain's moment ended.
    public private(set) var lineUntil: Int64 = 0
    /// The brain's moment on the device that holds the line until its
    /// `ended` comes: its id, when the app stops waiting for it, and when
    /// its take has played, from which the next brain moment may replace
    /// its face.
    public private(set) var holder: (id: Int, until: Int64, sayUntil: Int64)?
    /// The look and mood of the last `state` sent.
    public var look = "idle"
    public var mood = MoodAction.initial
    /// The last `state` sent said something needs you, so the device plays
    /// no moment (BEHAVIORS.md §1).
    public private(set) var attn = false
    /// The brain's moments waiting, oldest first, each with its handle and
    /// when it arrived.
    public private(set) var waiting: [(moment: DeviceMoment, pending: Pending?, at: Int64)] = []
    /// The taps in the run so far (1 for the first), and when the last came.
    public private(set) var taps = 0
    var lastTap: Int64?
    /// The id the last brain moment went out with. Each launch starts
    /// somewhere random and counts up from there, so a moment an earlier
    /// launch left playing on the device can't share an id with one of
    /// this launch's (PROTOCOL.md §3).
    public private(set) var lastId: Int
    /// The brain's moments on the device, oldest first, each with its id,
    /// its handle and when the app stops waiting for its `ended`.
    public private(set) var playing: [(id: Int, pending: Pending, deadline: Int64)] = []

    /// A launch's ids start after `lastId`, somewhere random by default.
    public init(lastId: Int = Int.random(in: 0..<MomentSchedule.maxId)) {
        self.lastId = lastId
    }

    /// The id after `id`, back to 1 past `maxId`.
    static func nextId(after id: Int) -> Int { id >= maxId ? 1 : id + 1 }

    /// When the line is free: at its holder's `ended`, or when the app
    /// stops waiting for it; with no holder, at `lineUntil`.
    public var lineFree: Int64 { holder?.until ?? lineUntil }

    /// When the line is free for the brain's next moment: once its holder's
    /// take has played on the device, give or take the link
    /// (`linkSlackMs`), or at its `ended` if that's sooner; with no holder,
    /// at `lineUntil` (harness/DECISIONS.md §5).
    public var brainFree: Int64 { holder?.sayUntil ?? lineUntil }

    /// When the moment playing on the device ends: its animation, and its
    /// line or face.
    public var busyUntil: Int64 { max(animUntil, lineFree) }

    /// How long `moment` plays at most, in the look and mood showing.
    public func playMs(_ moment: DeviceMoment) -> Int64 {
        moment.playMs(look: look, mood: mood)
    }

    /// Whether a rule's one-shot may play at `now` (BEHAVIORS.md §3): not
    /// while something needs you, and not while a brain moment's line
    /// plays, which it would cut. A face held on after its line may go:
    /// the device ends that moment as done (PROTOCOL.md §4).
    public func rulePlays(now: Int64) -> Bool {
        !attn && now >= brainFree
    }

    /// A rule's one-shot went to the device at `now`: it replaces the
    /// animation playing, as a tap's poke does, and a brain moment plays
    /// over it without waiting, as over a poke (ARCHITECTURE.md §3.2).
    public mutating func rule(_ moment: DeviceMoment, now: Int64) {
        animUntil = now + playMs(moment)
    }

    /// The device's own poke, at a tap: poked in Boop's mood, or tap_spam
    /// from the run's third tap, which replaces the animation playing,
    /// unless something needs you or `listening` shows, when the tap only
    /// dips the face (BEHAVIORS.md §3.3). Every tap counts in the run, as
    /// on the device. The line plays on over the poke, so it stays busy
    /// until it would have ended anyway.
    public mutating func tapped(now: Int64, listening: Bool = false) {
        taps = lastTap.map { now - $0 < Self.tapRunMs } == true ? taps + 1 : 1
        lastTap = now
        guard !attn && !listening else { return }
        animUntil = now + DeviceMoment.tapMs(mood: mood, run: taps)
    }

    /// A `state` sent: its look and mood time what plays next, and "needs
    /// you" starting stops everything playing (PROTOCOL.md §3).
    public mutating func show(look: String, mood: String, attn: Bool, now: Int64) {
        if attn && !self.attn { stop(now: now) }
        self.look = look
        self.mood = mood
        self.attn = attn
    }

    /// Nothing plays from `now`: a reaction's turn came with no device
    /// connected, or "needs you" stopped it all.
    public mutating func stop(now: Int64) {
        animUntil = min(animUntil, now)
        lineUntil = min(lineUntil, now)
        holder = nil
    }

    /// The brain moment `due` just handed out at `now` went to the device
    /// as `id`: the line waits for its `ended` until `until` at the latest,
    /// and the next brain moment until its take has played (a silent
    /// face, as long as a bubble would show), or, when it
    /// plays an animation, which the next would cut, until its `ended` too.
    public mutating func hold(id: Int, _ moment: DeviceMoment, now: Int64, until: Int64) {
        let free = moment.anim == nil ? min(until, now + moment.faceFirstMs + Self.linkSlackMs) : until
        holder = (id, until, free)
    }

    /// The device said the brain moment `id` ended. If it holds the line,
    /// the line is free from `now`.
    public mutating func ended(id: Int, now: Int64) {
        guard holder?.id == id else { return }
        holder = nil
        lineUntil = now
    }

    /// Drops every brain moment waiting, ending each handle as failed: the
    /// mic went on, and a reaction would end `listening` (BEHAVIORS.md §3.3).
    public mutating func dropWaiting() -> [DeviceMoment] {
        let dropped = waiting
        waiting = []
        for (_, pending, _) in dropped { pending?.finish(.failed("the mic went on")) }
        return dropped.map(\.moment)
    }

    /// A brain moment `due` just handed out going to the device at `now`:
    /// it gets the next id, and its handle, and the line, wait for the
    /// device's `ended` until its length at most, and the grace, have
    /// passed.
    public mutating func send(_ moment: inout DeviceMoment, _ pending: Pending, now: Int64) {
        lastId = Self.nextId(after: lastId)
        moment.id = lastId
        let deadline = now + playMs(moment) + Self.endGraceMs
        playing.append((lastId, pending, deadline))
        hold(id: lastId, moment, now: now, until: deadline)
    }

    /// The device's `ended` at `now`: frees the line if the moment holds
    /// it, and ends its handle. An id the app isn't waiting on (one it
    /// gave up on) is ignored.
    public mutating func ended(_ ended: MomentEnded, now: Int64) {
        self.ended(id: ended.id, now: now)
        guard let i = playing.firstIndex(where: { $0.id == ended.id }) else { return }
        playing.remove(at: i).pending.finish(Self.end(ended))
    }

    /// How a reaction ended, from the device's `ended`
    /// (harness/DECISIONS.md §5).
    static func end(_ ended: MomentEnded) -> Pending.End {
        switch ended.how {
        case .done: .done
        case .cut where ended.why == "tap": .failed(TranscriptView.cutByTap)
        case .cut: .failed("cut short" + (ended.why.flatMap { cutBy[$0] }.map { ": " + $0 } ?? ""))
        case .skipped: .failed("something needed you")
        }
    }

    /// What cut a moment short, as its end says it; a tap's is
    /// `TranscriptView.cutByTap`, and `reset` is a tool's.
    static let cutBy = ["moment": "something newer played",
                        "needs_you": "something needed you"]

    /// Gives up on each moment whose `ended` hasn't come by its deadline:
    /// the device lost the line, or its firmware doesn't send one.
    public mutating func overdue(now: Int64) {
        let late = playing.filter { now >= $0.deadline }
        playing.removeAll { now >= $0.deadline }
        for moment in late { moment.pending.finish(.failed("the device never said it ended")) }
    }

    /// Ends every moment on the device as failed, with why. The line stays
    /// held: the device plays on.
    public mutating func failAll(_ why: String) {
        let all = playing
        playing = []
        for moment in all { moment.pending.finish(.failed(why)) }
    }

    /// Nothing is playing and no brain moment is waiting its turn.
    public func idle(now: Int64) -> Bool {
        now >= busyUntil && waiting.isEmpty
    }

    /// A moment from the brain, to play when its turn comes, and the handle
    /// whoever plays it ends once it knows how the moment went.
    public mutating func brain(_ moment: DeviceMoment, _ pending: Pending? = nil, now: Int64) {
        waiting.append((moment, pending, now))
    }

    /// When to ask `due` again: when the line is free for it, or when the
    /// oldest moment waiting will have waited too long, whichever comes
    /// first; nil when nothing waits.
    public var next: Int64? {
        waiting.first.map { min(brainFree, $0.at + Self.maxWaitMs + 1) }
    }

    /// The brain moment to play now, if one's turn has come (at most one),
    /// with its handle for whoever plays it; the ones dropped as too late
    /// on the way, whose handles end here; and when to ask again (nil when
    /// nothing waits). Its turn comes when the line is free for it
    /// (`brainFree`): it replaces a brain moment's face held on after its
    /// take, which the device counts as done (PROTOCOL.md §4). A
    /// moment's wait is counted to when its turn came:
    /// when the line was free, or when it arrived if that was later. One
    /// still waiting that has already waited too long is dropped at once.
    public mutating func due(now: Int64) -> (play: DeviceMoment?, pending: Pending?, dropped: [DeviceMoment], next: Int64?) {
        if let held = holder, now >= held.until {
            // No `ended` came in time: the line was free from then.
            holder = nil
            lineUntil = held.until
        }
        var dropped: [DeviceMoment] = []
        func drop(_ moment: DeviceMoment, _ pending: Pending?) {
            dropped.append(moment)
            pending?.finish(.failed("waited too long"))
        }
        let free = brainFree
        guard now >= free else {
            let late = waiting.filter { now - $0.at > Self.maxWaitMs }
            waiting.removeAll { now - $0.at > Self.maxWaitMs }
            for (moment, pending, _) in late { drop(moment, pending) }
            return (nil, nil, dropped, next)
        }
        let turn = now - free > Self.lateMs ? now : free
        while !waiting.isEmpty {
            let (moment, pending, at) = waiting.removeFirst()
            if max(turn, at) - at > Self.maxWaitMs {
                drop(moment, pending)
                continue
            }
            lineUntil = now + playMs(moment)
            holder = nil  // its face is replaced; the device still says how it ended
            return (moment, pending, dropped, next)
        }
        return (nil, nil, dropped, nil)
    }
}
