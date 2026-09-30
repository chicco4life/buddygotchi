import Foundation

/// When the brain's moments play on the device (ARCHITECTURE.md §3.2).
/// The tap's poke, which the device plays on its own, and the rules'
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
/// only until its take has played (`brainFree`). The schedule also hears
/// "needs you" starting, which stops everything on the device, and while
/// something needs you no moment plays. It needn't hear taps: a tap's
/// poke replaces only an animation, and a line plays on over it.
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
    public private(set) var waiting: [(moment: DeviceMoment, pending: Pending, at: Int64)] = []
    /// The id the last brain moment went out with. Each launch starts
    /// somewhere random and counts up from there, so a moment an earlier
    /// launch left playing on the device can't share an id with one of
    /// this launch's (PROTOCOL.md §3).
    public private(set) var lastId: Int
    /// The brain's moments on the device, oldest first, each with its id,
    /// its handle, when the app stops waiting for its `ended`, and for a
    /// finish, the thread a tap on it opens.
    public private(set) var playing: [(id: Int, pending: Pending, deadline: Int64, opens: ThreadRef?)] = []

    /// A launch's ids start after `lastId`, somewhere random by default.
    public init(lastId: Int = Int.random(in: 0..<MomentSchedule.maxId)) {
        self.lastId = lastId
    }

    /// The id after `id`, back to 1 past `maxId`.
    static func nextId(after id: Int) -> Int { id >= maxId ? 1 : id + 1 }

    /// When the line is free for the brain's next moment: once its holder's
    /// take has played on the device, give or take the link
    /// (`linkSlackMs`), or at its `ended` if that's sooner; with no holder,
    /// at `lineUntil` (harness/DECISIONS.md §5).
    public var brainFree: Int64 { holder?.sayUntil ?? lineUntil }

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
        lineUntil = min(lineUntil, now)
        holder = nil
    }

    /// Drops every brain moment waiting, ending each handle as failed: the
    /// mic went on, and a reaction would end `listening` (BEHAVIORS.md §3.3).
    public mutating func dropWaiting() -> [DeviceMoment] {
        let dropped = waiting
        waiting = []
        for (_, pending, _) in dropped { pending.finish(.failed("the mic went on")) }
        return dropped.map(\.moment)
    }

    /// The device's `ended` at `now`: frees the line from `now` if the
    /// moment holds it, and ends its handle. An id the app isn't waiting
    /// on (one it gave up on) is ignored.
    public mutating func ended(_ ended: MomentEnded, now: Int64) {
        if holder?.id == ended.id {
            holder = nil
            lineUntil = now
        }
        guard let i = playing.firstIndex(where: { $0.id == ended.id }) else { return }
        playing.remove(at: i).pending.finish(Self.end(ended))
    }

    /// The thread a tap on the finish `id` opens: the device said the tap
    /// landed on it (BEHAVIORS.md §3.3). Nil once the app gave up on it.
    public func opens(finish id: Int) -> ThreadRef? {
        playing.first { $0.id == id }?.opens
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
        guard !playing.isEmpty else { return }
        var late: [Pending] = []
        playing.removeAll { moment in
            guard now >= moment.deadline else { return false }
            late.append(moment.pending)
            return true
        }
        for pending in late { pending.finish(.failed("the device never said it ended")) }
    }

    /// Ends every moment on the device as failed, with why. The line stays
    /// held: the device plays on.
    public mutating func failAll(_ why: String) {
        let all = playing
        playing = []
        for moment in all { moment.pending.finish(.failed(why)) }
    }

    /// A moment from the brain, to play when its turn comes, and the handle
    /// whoever plays it ends once it knows how the moment went.
    public mutating func brain(_ moment: DeviceMoment, _ pending: Pending, now: Int64) {
        waiting.append((moment, pending, now))
    }

    /// When to ask `due` again: when the line is free for it, or when the
    /// oldest moment waiting will have waited too long, whichever comes
    /// first; nil when nothing waits.
    public var next: Int64? {
        waiting.first.map { min(brainFree, $0.at + Self.maxWaitMs + 1) }
    }

    /// The brain moment to send to the device now, if one's turn has come
    /// (at most one), and the ones dropped as too late on the way, whose
    /// handles end here. Its turn comes when the line is free for it
    /// (`brainFree`): it replaces a brain moment's face held on after its
    /// take, which the device counts as done (PROTOCOL.md §4). A moment's
    /// wait is counted to when its turn came: when the line was free, or
    /// when it arrived if that was later. One still waiting that has
    /// already waited too long is dropped at once. With no device
    /// connected nothing holds the line and its handle ends at once, as
    /// failed. One for the device goes with the next id, and it, its handle
    /// and the line wait for the device's `ended` until its length at most,
    /// and the grace, have passed; the next brain moment waits until its
    /// take has played (a silent face, as long as a bubble would show),
    /// or, when it plays an animation, which the next would cut, until its
    /// `ended` too.
    public mutating func due(now: Int64, connected: Bool) -> (play: DeviceMoment?, dropped: [DeviceMoment]) {
        if let held = holder, now >= held.until {
            // No `ended` came in time: the line was free from then.
            holder = nil
            lineUntil = held.until
        }
        var dropped: [DeviceMoment] = []
        func drop(_ moment: DeviceMoment, _ pending: Pending) {
            dropped.append(moment)
            pending.finish(.failed("waited too long"))
        }
        let free = brainFree
        guard now >= free else {
            let late = waiting.filter { now - $0.at > Self.maxWaitMs }
            waiting.removeAll { now - $0.at > Self.maxWaitMs }
            for (moment, pending, _) in late { drop(moment, pending) }
            return (nil, dropped)
        }
        let turn = now - free > Self.lateMs ? now : free
        while !waiting.isEmpty {
            var (moment, pending, at) = waiting.removeFirst()
            if max(turn, at) - at > Self.maxWaitMs {
                drop(moment, pending)
                continue
            }
            lineUntil = now + playMs(moment)
            guard connected else {
                stop(now: now)
                pending.finish(.failed("no device connected"))
                return (moment, dropped)
            }
            // It replaces the face held; the device still says how that ended.
            lastId = Self.nextId(after: lastId)
            moment.id = lastId
            let deadline = now + playMs(moment) + Self.endGraceMs
            playing.append((lastId, pending, deadline, moment.who?.opens))
            holder = (lastId, deadline, moment.anim == nil ? min(deadline, now + moment.faceFirstMs + Self.linkSlackMs) : deadline)
            return (moment, dropped)
        }
        return (nil, dropped)
    }
}
