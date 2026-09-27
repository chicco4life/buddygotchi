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
/// On a caller's clock, so the runtime can drive it with a timer and the
/// tests without one. It changes nothing but itself and the handles of
/// the moments it drops.
public struct MomentSchedule {
    /// A brain moment that has waited longer than this is dropped
    /// (ARCHITECTURE.md §3.2).
    public static let maxWaitMs: Int64 = 5000

    /// When the moment playing on the device ends, as the device times it.
    public private(set) var busyUntil: Int64 = 0
    /// When the line playing ends. An animation stops a line on the device.
    public private(set) var lineUntil: Int64 = 0
    /// The brain's moments waiting, oldest first, each with its handle and
    /// when it arrived.
    public private(set) var waiting: [(moment: DeviceMoment, pending: Pending?, at: Int64)] = []

    public init() {}

    /// A rule moment, playing now. Anything waiting waits for it too.
    public mutating func rule(_ moment: DeviceMoment, now: Int64) {
        busyUntil = max(busyUntil, now + moment.playMs)
        if moment.say != nil {
            lineUntil = now + moment.playMs
        } else if moment.anim != nil {
            lineUntil = min(lineUntil, now)
        }
    }

    /// Nothing is playing and no brain moment is waiting its turn.
    public func idle(now: Int64) -> Bool {
        now >= busyUntil && waiting.isEmpty
    }

    /// A moment from the brain, to play when its turn comes, and the handle
    /// that says when it has played.
    public mutating func brain(_ moment: DeviceMoment, _ pending: Pending? = nil, now: Int64) {
        waiting.append((moment, pending, now))
    }

    /// The brain moment to play now, if one's turn has come (at most one),
    /// with its handle for whoever plays it; the ones dropped as too late
    /// on the way, whose handles end here; and when to ask again (nil when
    /// nothing waits).
    public mutating func due(now: Int64) -> (play: DeviceMoment?, pending: Pending?, dropped: [DeviceMoment], next: Int64?) {
        var dropped: [DeviceMoment] = []
        guard now >= lineUntil else { return (nil, nil, dropped, waiting.isEmpty ? nil : lineUntil) }
        while !waiting.isEmpty {
            let (moment, pending, at) = waiting.removeFirst()
            if now - at > Self.maxWaitMs {
                dropped.append(moment)
                pending?.finish(.failed("waited too long"))
                continue
            }
            busyUntil = max(busyUntil, now + moment.playMs)
            lineUntil = now + moment.playMs
            return (moment, pending, dropped, waiting.isEmpty ? nil : lineUntil)
        }
        return (nil, nil, dropped, nil)
    }
}
