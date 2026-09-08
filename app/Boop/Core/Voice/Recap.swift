import Foundation

struct Recap: Encodable, Sendable, Equatable {
    var line: String
    var paragraph: String
}
struct RecapFacts: Sendable, Equatable {
    var turns: Int = 0
    var tasks: Int = 0
    var biggestMoment: Moment? = nil
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
                let moment = Moment(kind: kind, facts: [:])
                if result.biggestMoment == nil || rank(kind) > rank(result.biggestMoment!.kind) { result.biggestMoment = moment }
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
    func paragraph(language: String) -> String {
        let time = String(format: "%.1f", hours)
        let label = project.flatMap { value -> String? in
            guard value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }) else { return nil }
            return VoiceFilter.check(value, language: language, byteCap: 48)
        }
        let location = label.map { language == "ko" ? "주로 " + $0 + "에서 " : "mostly in " + $0 + ", " } ?? ""
        let moment: String
        if language == "ko" {
            switch biggestMoment?.kind {
            case .hardWonPass: moment = "여러 번 끝에 초록이 왔어요."
            case .redStreakEnded: moment = "빨간 줄이 끝났어요."
            case .firstEver: moment = "첫 기쁨도 생겼어요."
            case .backAfterAbsence: moment = "익숙한 곳에 돌아왔어요."
            case .sameFileAgain: moment = "같은 파일에 자주 들렀어요."
            case .lateNight: moment = "늦은 시간도 함께했어요."
            case .nthRateLimit: moment = "문 앞에서 여러 번 기다렸어요."
            case nil: moment = "조용히 곁에 있었어요."
            }
            return "\(location)오늘 \(turns)번 마치고 \(tasks)개 통과했어요, 함께한 시간은 \(time)시간이에요. \(moment) 아직 열린 일은 \(openGoals)개예요."
        }
        switch biggestMoment?.kind {
        case .hardWonPass: moment = "a hard-won green stood out."
        case .redStreakEnded: moment = "the red streak ended."
        case .firstEver: moment = "our first win found a place."
        case .backAfterAbsence: moment = "a familiar place came back."
        case .sameFileAgain: moment = "one file had plenty of company."
        case .lateNight: moment = "the late hours had company."
        case .nthRateLimit: moment = "the gate kept us waiting."
        case nil: moment = "a quiet day to keep."
        }
        return "\(location)\(turns) turns and \(tasks) passes over \(time) hours. \(moment) \(openGoals) goals are still open."
    }
}
