import Foundation

enum Reflection {
    static func candidates(day: [StoredFact], history: [StoredFact], localDay: String) -> [String] {
        guard !day.isEmpty else { return [] }
        var lines: [String] = []
        let sessions = Dictionary(grouping: day, by: \.sessionId).filter { !$0.key.isEmpty }
        let startsWithTests = sessions.values.filter { facts in
            let first = facts.sorted { $0.at < $1.at }.compactMap { f -> String? in
                if case .activity(_, _, let runner) = f.fact { return runner }
                return nil
            }.first
            return first.map { RunnerLabel.subject($0) == "tests" } ?? false
        }.count
        if !sessions.isEmpty, Double(startsWithTests) / Double(sessions.count) >= 0.6 { lines.append("tests first, usually") }
        let ordinal = CivilDay.ordinal(localDay) ?? 0
        let fortnight = history.filter { let d = CivilDay.ordinal($0.day) ?? 0; return d <= ordinal && d > ordinal - 14 }
        if fortnight.filter({ $0.fact == .moment(.lateNight) }).count >= 3 { lines.append("works late") }
        var runners: [String: Int] = [:]
        for f in day { if case .goalOutcome(_, let runner, _, _, _) = f.fact { runners[runner,default:0] += 1 } }
        if let dominant = runners.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first,
           dominant.value * 2 > runners.values.reduce(0,+) { lines.append("reaches for \(dominant.key)") }
        let byProject = Dictionary(grouping: history, by: \.project)
        for project in Set(day.map(\.project)).sorted() where project != "unknown" {
            if Set((byProject[project] ?? []).map(\.day)).count >= 5 { lines.append("keeps coming back to \(project)") }
        }
        return Array(lines.prefix(5))
    }
}
enum DailyDrift {
    static func calculate(_ facts: [StoredFact], history: [StoredFact]) -> [String: Int] {
        var energy = 0, cheek = 0, warmth = 0, curiosity = 0, tools: Set<String> = []
        for f in facts {
            switch f.fact {
            case .activity(let hour, let tool, _):
                if tool == nil && (5..<12).contains(hour) { energy += 1 }
                if let tool { tools.insert(tool) }
            case .sessionSummary(let turns, _, let elapsed):
                if turns >= 20 { energy += 1 }
                if turns <= 1 && elapsed >= 3_600_000 { cheek -= 1 }
            case .moment(.lateNight): energy -= 1
            case .moment(.nthRateLimit), .denial: cheek += 1
            case .checkIn, .greet: warmth += 1
            default: break
            }
        }
        let firstDay = facts.map(\.day).min() ?? ""
        let known = Set(history.filter { $0.day < firstDay }.map(\.project))
        curiosity += Set(facts.map(\.project)).subtracting(known).subtracting(["unknown"]).count
        if tools.count >= 5 { curiosity += 1 }
        return ["energy":energy,"cheek":cheek,"warmth":warmth,"curiosity":curiosity].mapValues { min(3,max(-3,$0)) }
    }
}
