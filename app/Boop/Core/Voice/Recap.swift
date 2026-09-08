import Foundation

struct Recap: Encodable, Sendable, Equatable {
    var line: String
    var paragraph: String
    var turns: Int = 0
    var tasks: Int = 0
    var biggest: String = "—"
}
struct RecapFacts: Sendable, Equatable {
    var turns: Int = 0
    var tasks: Int = 0
    var biggestMoment: Moment.Kind? = nil
    var openGoals: Int = 0
    var project: String? = nil
    var hours: Double = 0

    static func build(_ facts: [StoredFact]) -> Self {
        var result = Self(), goals: [String: GoalOutcome] = [:]
        var durations: [String: Double] = [:]
        let sessions = Dictionary(grouping: facts, by: \.sessionId)
        for (id, rows) in sessions {
            let turns = rows.compactMap { row -> Double? in if case .turnCompleted(let ms) = row.fact { return ms }; return nil }
            if !turns.isEmpty {
                result.turns += turns.count; durations[id] = turns.reduce(0, +)
            } else if let summary = rows.sorted(by: { $0.at > $1.at }).first(where: { if case .sessionSummary = $0.fact { return true }; return false }),
                      case .sessionSummary(let turns, _, let ms) = summary.fact {
                result.turns += turns; durations[id] = ms
            }
        }
        for row in facts.sorted(by: { $0.at < $1.at }) {
            switch row.fact {
            case .goalOutcome(let key, _, let outcome, _, _):
                goals[row.sessionId + ":" + key] = outcome
                if outcome == .pass { result.tasks += 1 }
            case .moment(let kind):
                if result.biggestMoment == nil || rank(kind) > rank(result.biggestMoment!) { result.biggestMoment = kind }
            default: break
            }
        }
        result.openGoals = goals.values.filter { $0 != .pass }.count
        result.hours = durations.values.reduce(0, +) / 3_600_000
        result.project = Dictionary(grouping: facts.filter { $0.project != "unknown" }, by: \.project)
            .sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }.first?.key
        return result
    }
    private static func rank(_ kind: Moment.Kind) -> Int {
        switch kind { case .hardWonPass: 7; case .redStreakEnded: 6; case .firstEver: 5; case .backAfterAbsence: 4; case .sameFileAgain: 3; case .lateNight: 2; case .nthRateLimit: 1 }
    }
    func projectLabel(language: String, cap: Int) -> String {
        VoiceBanks.sanitizedLabel(project, language: language, cap: cap,
                                  fallback: language == "ko" ? "여기" : "project")
    }
}
