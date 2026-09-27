import Foundation

/// What plays on the device and until when (ARCHITECTURE.md §3.2). The
/// rules' moments play at once. The brain's wait their turn: one at a time,
/// each after whatever is playing has finished, so none cuts off a rule
/// moment or another of the brain's. One that has waited longer than
/// `maxWaitMs` is dropped, since a late reaction is worse than none.
///
/// Pure and on a caller's clock, so the runtime can drive it with a timer
/// and the tests without one.
public struct MomentSchedule {
    /// A brain moment that has waited longer than this is dropped
    /// (ARCHITECTURE.md §3.2).
    public static let maxWaitMs: Int64 = 5000

    /// When the moment playing on the device ends, as the device times it.
    public private(set) var busyUntil: Int64 = 0
    /// The brain's moments waiting, oldest first, with when each arrived.
    public private(set) var waiting: [(moment: DeviceMoment, at: Int64)] = []

    public init() {}

    /// A rule moment, playing now. Anything waiting waits for it too.
    public mutating func rule(_ moment: DeviceMoment, now: Int64) {
        busyUntil = max(busyUntil, now + moment.playMs)
    }

    /// Nothing is playing and no brain moment is waiting its turn.
    public func idle(now: Int64) -> Bool {
        now >= busyUntil && waiting.isEmpty
    }

    /// A moment from the brain, to play when its turn comes.
    public mutating func brain(_ moment: DeviceMoment, now: Int64) {
        waiting.append((moment, now))
    }

    /// The brain moment to play now, if one's turn has come (at most one),
    /// the ones dropped as too late on the way, and when to ask again (nil
    /// when nothing waits).
    public mutating func due(now: Int64) -> (play: DeviceMoment?, dropped: [DeviceMoment], next: Int64?) {
        var dropped: [DeviceMoment] = []
        guard now >= busyUntil else { return (nil, dropped, waiting.isEmpty ? nil : busyUntil) }
        while !waiting.isEmpty {
            let (moment, at) = waiting.removeFirst()
            if now - at > Self.maxWaitMs {
                dropped.append(moment)
                continue
            }
            busyUntil = now + moment.playMs
            return (moment, dropped, waiting.isEmpty ? nil : busyUntil)
        }
        return (nil, dropped, nil)
    }
}
