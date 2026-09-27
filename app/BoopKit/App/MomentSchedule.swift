import Foundation

/// What plays on the device and until when (ARCHITECTURE.md §3.2). The
/// rules' moments play at once. The brain's wait their turn: one at a time,
/// each once the line playing has finished, and a reaction's face too
/// unless it's the brain's own, held on for its loops after its mumble:
/// the next reaction replaces that, so none cuts off a line and a held face
/// doesn't hold up the next reaction. A brain mumble has no animation,
/// so it plays over an animation without cutting it: a proud mumble over
/// the cheer shows the cheer in proud's face. One that has waited longer
/// than `maxWaitMs` for its turn is dropped, since a late reaction is worse
/// than none, and its handle ends as failed (harness/DECISIONS.md §5).
///
/// The app reckons how long each moment plays at most, as the device times
/// it (PROTOCOL.md §3). A brain moment sent with an `id` holds the line
/// until the device's `ended` says it's over, which is usually sooner (a
/// face ends on a loop boundary, or a tap cuts it), and at most until the
/// app stops waiting for that `ended`, whatever the Mac hears meanwhile of
/// a tap or the link dropping. For the brain's next moment it holds the line
/// only until its mumble has played (`brainFree`). The schedule also hears what the device
/// does on its own or leaves out: a tap's wiggle cuts whatever else plays,
/// "needs you" starting stops everything, and while something needs you
/// no moment plays.
///
/// On a caller's clock, so the runtime can drive it with a timer and the
/// tests without one. It changes nothing but itself and the handles of
/// the moments it drops.
public struct MomentSchedule {
    /// A brain moment that has waited longer than this for its turn is
    /// dropped (ARCHITECTURE.md §3.2).
    public static let maxWaitMs: Int64 = 5000
    /// How late the pump may run after a moment's turn came and still
    /// count its wait to when the turn came. Later than that, the wait is
    /// counted to now, so a moment held up by a Mac asleep is dropped.
    public static let lateMs: Int64 = 1000
    /// How long past the cheer's reckoned end it may still be playing on
    /// the device, since every line reaches it a little after it's sent.
    public static let linkSlackMs: Int64 = 500

    /// When the rules' animation playing ends.
    public private(set) var animUntil: Int64 = 0
    /// When the line playing ends, and with it a reaction's face, as the
    /// app reckons it; or when the device said the brain's moment ended.
    public private(set) var lineUntil: Int64 = 0
    /// The brain's moment on the device that holds the line until its
    /// `ended` comes: its id, when the app stops waiting for it, and when
    /// its mumble has played, from which the next brain moment may replace
    /// its face.
    public private(set) var holder: (id: Int, until: Int64, sayUntil: Int64)?
    /// When the rules' cheer playing ends; nil before the first.
    public private(set) var cheerUntil: Int64?
    /// The look and mood of the last `state` sent.
    public var look = "idle"
    public var mood = MoodAction.initial
    /// The last `state` sent said something needs you, so the device plays
    /// no moment (BEHAVIORS.md §1).
    public private(set) var attn = false
    /// The brain's moments waiting, oldest first, each with its handle and
    /// when it arrived.
    public private(set) var waiting: [(moment: DeviceMoment, pending: Pending?, at: Int64)] = []

    public init() {}

    /// When the line is free: at its holder's `ended`, or when the app
    /// stops waiting for it; with no holder, at `lineUntil`.
    public var lineFree: Int64 { holder?.until ?? lineUntil }

    /// When the line is free for the brain's next moment: once its holder's
    /// mumble has played on the device, give or take the link
    /// (`linkSlackMs`), or at its `ended` if that's sooner; with no holder,
    /// at `lineUntil` (harness/DECISIONS.md §5).
    public var brainFree: Int64 { holder?.sayUntil ?? lineUntil }

    /// When the moment playing on the device ends: its animation, and its
    /// line or face.
    public var busyUntil: Int64 { max(animUntil, lineFree) }

    /// How long `moment` plays at most if it starts at `now`, in the design
    /// showing: the look's, or, while a cheer may be playing, the longer of
    /// the look's and the cheer's. The device may time it by either: a tap
    /// the app hasn't heard of yet may have ended the cheer, or the line
    /// may reach the device just after the cheer ends there.
    public func playMs(_ moment: DeviceMoment, now: Int64) -> Int64 {
        let ms = moment.playMs(look: look, mood: mood)
        guard let cheerUntil, now < cheerUntil + Self.linkSlackMs else { return ms }
        return max(ms, moment.playMs(look: "task_complete", mood: mood))
    }

    /// A rule moment, playing now. An animation replaces the one playing
    /// and stops the line, and with it the brain's moment; a line replaces
    /// the line. Anything waiting waits for a new line too. While
    /// something needs you, the device plays none of it.
    public mutating func rule(_ moment: DeviceMoment, now: Int64) {
        guard !attn else { return }
        let ms = playMs(moment, now: now)
        if let anim = moment.anim, DeviceMoment.anims.contains(anim) {
            animUntil = now + ms
            lineUntil = moment.say != nil ? now + ms : now
            holder = nil
            cheerUntil = anim == "cheer" ? now + ms : cheerUntil.map { min($0, now) }
        } else if moment.say != nil {
            lineUntil = now + ms
            holder = nil
        }
    }

    /// The device's own wiggle, at a tap: it cuts whatever plays, as a
    /// rule's wiggle does, unless something needs you (BEHAVIORS.md §3.3).
    /// Except a brain moment that holds the line: the app hears the tap
    /// after sending what it thought was playing, so the moment may have
    /// reached the device after the tap and play on. Its `ended` frees the
    /// line, which the device sends at once for a moment its tap cut.
    public mutating func tapped(now: Int64) {
        let held = holder
        rule(DeviceMoment(anim: "wiggle"), now: now)
        if !attn { holder = held }
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
        cheerUntil = cheerUntil.map { min($0, now) }
        holder = nil
    }

    /// The brain moment `due` just handed out at `now` went to the device
    /// as `id`: the line waits for its `ended` until `until` at the latest,
    /// and the next brain moment until its mumble has played.
    public mutating func hold(id: Int, _ moment: DeviceMoment, now: Int64, until: Int64) {
        holder = (id, until, min(until, now + moment.sayMs + Self.linkSlackMs))
    }

    /// The device said the brain moment `id` ended. If it holds the line,
    /// the line is free from `now`.
    public mutating func ended(id: Int, now: Int64) {
        guard holder?.id == id else { return }
        holder = nil
        lineUntil = now
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
    /// mumble, which the device counts as done (PROTOCOL.md §4). A
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
            lineUntil = now + playMs(moment, now: now)
            holder = nil  // its face is replaced; the device still says how it ended
            return (moment, pending, dropped, next)
        }
        return (nil, nil, dropped, nil)
    }
}
