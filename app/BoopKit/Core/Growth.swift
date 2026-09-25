import Foundation

/// XP, levels, days together and hunger (BEHAVIORS.md §4). Plain rules; the
/// brain can't touch them. The memory store keeps this as the Growth line in
/// `long-term.md`.
public struct Growth: Equatable, Sendable {
    public static let xpPerLevel = 50
    public static let turnXP = 1
    public static let dailyXP = 5

    public enum Hunger: Int, Sendable, Comparable {
        case fed = 0, hungry = 1, starving = 2
        public static func < (a: Hunger, b: Hunger) -> Bool { a.rawValue < b.rawValue }
    }

    public var xp: Int
    /// The day Boop was set up, `yyyy-MM-dd`.
    public var hatched: String
    /// The last day Boop earned XP.
    public var lastFed: String
    /// XP lost to starving since it was last fed.
    public var lost: Int

    public init(xp: Int = 0, hatched: String, lastFed: String? = nil, lost: Int = 0) {
        self.xp = xp
        self.hatched = hatched
        self.lastFed = lastFed ?? hatched
        self.lost = lost
    }

    /// XP ÷ 50, rounded down, plus 1.
    public var level: Int { xp / Growth.xpPerLevel + 1 }
    /// Progress to the next level, 0–100.
    public var progress: Int { (xp % Growth.xpPerLevel) * 100 / Growth.xpPerLevel }

    /// Calendar days together, counting the day of setup as day 1.
    public func days(today: String) -> Int { max(1, LocalTime.daysBetween(hatched, today) + 1) }

    /// Under 2 days since fed: fed; 2–5: hungry; over 5: starving.
    public func hunger(today: String) -> Hunger {
        let days = LocalTime.daysBetween(lastFed, today)
        if days > 5 { return .starving }
        if days >= 2 { return .hungry }
        return .fed
    }

    /// Adds XP and records the meal. Returns whether it crossed into a new level.
    @discardableResult
    public mutating func earn(_ amount: Int, today: String) -> Bool {
        let before = level
        xp += amount
        lastFed = today
        lost = 0
        return level > before
    }

    /// A starving Boop loses 1 XP a day, but never drops below the start of
    /// its current level. Returns whether anything changed.
    @discardableResult
    public mutating func starve(today: String) -> Bool {
        let owed = max(0, LocalTime.daysBetween(lastFed, today) - 5)
        guard owed > lost else { return false }
        let floor = (xp / Growth.xpPerLevel) * Growth.xpPerLevel
        let take = min(owed - lost, xp - floor)
        lost = owed
        xp -= take
        return true
    }
}
