import Foundation

// Migration only: reconstruct XP for old ledger-only databases once.
struct LegacyGrowthFormula: Sendable, Codable, Equatable {
    var turn = 3, task = 8, hardWonPass = 12, activeDay = 10, session = 2, checkIn = 1, tokens = 1
    func awards(_ rows: [LedgerRow], activeDays: [String] = []) -> [(LedgerRow, Int)] {
        var checks: [String: Int] = [:], tokenCounts: [String: Int] = [:], turns: [String: [Double]] = [:]
        var active: Set<String> = [], bonuses: Set<String> = []
        let days = Set(activeDays + rows.filter { $0.source == .activeDay }.map(\.day))
        let explicitBonuses = Set(rows.filter { $0.source == .streakBonus }.map(\.day))
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
            case .activeDay: if active.insert(row.day).inserted { xp = activeDay + (explicitBonuses.contains(row.day) ? 0 : min(10, LegacyStreak.calculate(days: Array(days), through: row.day).current)) }
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
}

struct LegacyStreak: Equatable {
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
