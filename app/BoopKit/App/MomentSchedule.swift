import Foundation

/// What plays on the device and until when (ARCHITECTURE.md §3.2). The
/// rules' moments play at once. The brain's wait their turn: one at a time,
/// each after any line playing has finished, so none cuts off a line or
/// another of the brain's. A brain mumble has no animation, so it plays
/// over an animation without cutting it: a proud mumble over the cheer
/// shows the cheer in proud's face. One that has waited longer than
/// `maxWaitMs` is dropped, since a late reaction is worse than none, and
/// its handle ends as failed (harness/DECISIONS.md §5).
///
/// A moment's length depends on the design showing, since the cheer and a
/// reaction's face play loops of it (PROTOCOL.md §3): the look and mood of
/// the last `state`, or the cheer's while one plays.
///
/// On a caller's clock, so the runtime can drive it with a timer and the
/// tests without one. It changes nothing but itself and the handles of
/// the moments it drops.
public struct MomentSchedule {
    /// A brain moment that has waited longer than this is dropped
    /// (ARCHITECTURE.md §3.2).
    public static let maxWaitMs: Int64 = 5000

    /// When the moment playing on the device ends, as the device times it.
    public private(set) var busyUntil: Int64 = 0
    /// When the line playing ends, and with it a reaction's face. An
    /// animation stops a line on the device.
    public private(set) var lineUntil: Int64 = 0
    /// When the rules' cheer playing ends.
    public private(set) var cheerUntil: Int64 = 0
    /// The look and mood of the last `state` sent.
    public var look = "idle"
    public var mood = MoodAction.initial
    /// The brain's moments waiting, oldest first, each with its handle and
    /// when it arrived.
    public private(set) var waiting: [(moment: DeviceMoment, pending: Pending?, at: Int64)] = []

    public init() {}

    /// How long `moment` plays at most if it starts at `now`: on the
    /// cheer's design while one plays, else the look's.
    public func playMs(_ moment: DeviceMoment, now: Int64) -> Int64 {
        moment.playMs(look: now < cheerUntil ? "task_complete" : look, mood: mood)
    }

    /// A rule moment, playing now. Anything waiting waits for it too.
    public mutating func rule(_ moment: DeviceMoment, now: Int64) {
        let ms = playMs(moment, now: now)
        busyUntil = max(busyUntil, now + ms)
        if moment.say != nil {
            lineUntil = now + ms
        } else if moment.anim != nil {
            lineUntil = min(lineUntil, now)
        }
        if let anim = moment.anim { cheerUntil = anim == "cheer" ? now + ms : min(cheerUntil, now) }
    }

    /// "Needs you" shows: the device stops the cheer and any line, and plays
    /// nothing while it shows (BEHAVIORS.md §1), so nothing is timed on
    /// them any more.
    public mutating func attention(now: Int64) {
        busyUntil = min(busyUntil, now)
        lineUntil = min(lineUntil, now)
        cheerUntil = min(cheerUntil, now)
    }

    /// The device says the brain's moment holding the turn is over, which
    /// can be up to a loop sooner than the schedule reckoned (it ends a
    /// face on its design's loop boundary): the turn is free now.
    public mutating func ended(now: Int64) {
        lineUntil = min(lineUntil, now)
        busyUntil = min(busyUntil, max(now, cheerUntil))
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

    /// The brain moment to play now, if one's turn has come (at most one),
    /// with its handle for whoever plays it; the ones dropped as too late,
    /// whose handles end here, whether or not a turn has come; and when to
    /// ask again (nil when nothing waits): when the line ends, or sooner
    /// when the first waiting will have waited too long.
    public mutating func due(now: Int64) -> (play: DeviceMoment?, pending: Pending?, dropped: [DeviceMoment], next: Int64?) {
        var dropped: [DeviceMoment] = []
        var kept: [(moment: DeviceMoment, pending: Pending?, at: Int64)] = []
        for entry in waiting {
            if now - entry.at > Self.maxWaitMs {
                dropped.append(entry.moment)
                entry.pending?.finish(.failed("waited too long"))
            } else {
                kept.append(entry)
            }
        }
        waiting = kept
        guard now >= lineUntil, !waiting.isEmpty else { return (nil, nil, dropped, next) }
        let (moment, pending, _) = waiting.removeFirst()
        let ms = playMs(moment, now: now)
        busyUntil = max(busyUntil, now + ms)
        lineUntil = now + ms
        return (moment, pending, dropped, next)
    }

    /// When to ask `due` again, or nil when nothing waits.
    var next: Int64? {
        waiting.first.map { min(lineUntil, $0.at + Self.maxWaitMs + 1) }
    }
}
