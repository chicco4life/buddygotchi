import Foundation

enum XPSource: String, Codable, Sendable, CaseIterable {
    case turn, task, hardWonPass, activeDay, streakBonus, session, checkIn, tokens
}
struct LedgerRow: Codable, Sendable, Equatable {
    var at: Double
    var source: XPSource
    /// Source units, not precomputed XP. Token rows contain output token counts.
    var amount: Int = 1
    var sessionId: String = ""
    var day: String
}
struct GrowthSnapshot: Codable, Sendable, Equatable {
    var level = 1, xp = 0, xpNext = 150, streak = 0, bestStreak = 0, restDays = 0
    var daysTogether = 0, tasks = 0, today = 0
    var biggest: CheerSize = .hop
}
struct GrowthFormula: Sendable {
    var turn = 3, task = 8, hardWonPass = 12, activeDay = 10, session = 2, checkIn = 1, tokens = 1
    static func threshold(_ level: Int) -> Int { let l = max(1, level); return 100 * (l - 1) * l / 2 + 50 * (l - 1) }
    func level(for xp: Int) -> Int {
        var low = 1, high = 2
        while Self.threshold(high) <= xp { high *= 2 }
        while low + 1 < high { let mid = (low + high) / 2; if Self.threshold(mid) <= xp { low = mid } else { high = mid } }
        return low
    }
    func xpToNext(for xp: Int) -> Int { Self.threshold(level(for: xp) + 1) - max(0, xp) }
    func awards(_ rows: [LedgerRow]) -> [(LedgerRow, Int)] {
        var checks: [String: Int] = [:], tokenCounts: [String: Int] = [:], turns: [String: [Double]] = [:]
        var active: Set<String> = [], bonuses: Set<String> = []
        return rows.sorted { $0.at < $1.at }.map { row in
            let units = max(0, row.amount)
            var xp = 0
            switch row.source {
            case .turn:
                var recent = turns[row.sessionId, default: []].filter { $0 > row.at - 3_600_000 }
                let count = min(units, max(0, 60 - recent.count))
                recent += Array(repeating: row.at, count: count); turns[row.sessionId] = recent; xp = count * turn
            case .task: xp = units * task
            case .hardWonPass: xp = units * hardWonPass
            case .session: xp = units * session
            case .activeDay: if active.insert(row.day).inserted { xp = activeDay }
            case .streakBonus: if bonuses.insert(row.day).inserted { xp = min(10, units) }
            case .checkIn:
                let count = min(units, max(0, 20 - checks[row.day, default: 0]))
                checks[row.day, default: 0] += count; xp = count * checkIn
            case .tokens:
                let old = tokenCounts[row.day, default: 0]
                let next = min(1_000_000, old + min(1_000_000, units))
                tokenCounts[row.day] = next; xp = (next / 100_000 - old / 100_000) * tokens
            }
            return (row, xp)
        }
    }
    func snapshot(_ rows: [LedgerRow], localDay: String, biggest: CheerSize = .hop) -> GrowthSnapshot {
        let awards = awards(rows), xp = awards.reduce(0) { $0 + $1.1 }
        let days = Set(rows.filter { $0.source == .activeDay }.map(\.day)).sorted()
        let streak = Streak.calculate(days: days, through: localDay)
        return GrowthSnapshot(level: level(for: xp), xp: xp, xpNext: xpToNext(for: xp), streak: streak.current,
            bestStreak: streak.best, restDays: streak.rest, daysTogether: days.count,
            tasks: rows.filter { $0.source == .task }.reduce(0) { $0 + $1.amount },
            today: awards.filter { $0.0.day == localDay }.reduce(0) { $0 + $1.1 }, biggest: biggest)
    }
}
/// Civil date arithmetic only: UTC is a fixed arithmetic reference, never the machine's time zone.
enum CivilDay {
    static func ordinal(_ text: String) -> Int? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return Int(date.timeIntervalSince1970 / 86_400)
    }
}
struct Streak: Equatable {
    var current = 0, best = 0, rest = 0
    static func calculate(days: [String], through: String) -> Self {
        let active = Set(days.compactMap(CivilDay.ordinal))
        guard let first = active.min(), let end = CivilDay.ordinal(through), first <= end else { return Self() }
        var s = Self(), lifetimeActive = 0
        for day in first...end {
            if active.contains(day) {
                s.current += 1; lifetimeActive += 1; s.best = max(s.best, s.current)
                if lifetimeActive % 7 == 0 { s.rest = min(3, s.rest + 1) }
            } else if day < end { // Today isn't missed until tomorrow.
                if s.rest > 0 { s.rest -= 1 } else { s.current = 0 }
            }
        }
        return s
    }
}
struct EquippedCosmetic: Codable, Sendable, Equatable {
    var skin = "default", accessory = "none", silhouette = "default"
}
struct CosmeticUnlock: Sendable {
    var level: Int, kind: String, name: String
    static let schedule: [Self] = [
        .init(level: 1, kind: "skin", name: "default"), .init(level: 1, kind: "accessory", name: "none"), .init(level: 1, kind: "silhouette", name: "default"),
        .init(level: 2, kind: "skin", name: "sky"), .init(level: 3, kind: "animation", name: "happy-wiggle"),
        .init(level: 5, kind: "skin", name: "mint"), .init(level: 5, kind: "expression", name: "sulk"),
        .init(level: 8, kind: "accessory", name: "sprout"), .init(level: 10, kind: "silhouette", name: "round"), .init(level: 10, kind: "sound", name: "hop"),
        .init(level: 15, kind: "skin", name: "ember"), .init(level: 15, kind: "animation", name: "big-dance"),
        .init(level: 20, kind: "accessory", name: "scarf"), .init(level: 20, kind: "silhouette", name: "tall"),
        .init(level: 30, kind: "skin", name: "midnight"), .init(level: 30, kind: "accessory", name: "crown")]
}
