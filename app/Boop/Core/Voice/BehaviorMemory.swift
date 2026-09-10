import Foundation

/// A bounded projection for model context, not the underlying memory archive.
/// No project paths, approval decisions, old drawings or raw tool output.
struct BehaviorMemory: Sendable {
    struct RememberedMoment: Sendable, Equatable {
        var kind: String
        var day: String
    }
    var completedTurns: Int
    var lifetimeSessions: Int
    var knownProjects: Int
    var currentHourIsTypical: Bool?
    var moments: [RememberedMoment]

    init(memory: PetMemory, moments: [RememberedMoment] = [], at: Double) {
        completedTurns = max(0, memory.completedTurns)
        lifetimeSessions = max(0, memory.lifetimeSessions)
        knownProjects = memory.projects.count
        currentHourIsTypical = memory.circadianReady(at: at)
            ? memory.isTypicalHour(PetMemory.utcHour(ofMs: at)) : nil
        self.moments = Array(moments.filter { $0.kind != "nthRateLimit" }.prefix(5))
    }

    static func recentMoments(from facts: [StoredFact]) -> [RememberedMoment] {
        facts.sorted { $0.at > $1.at }.compactMap { fact in
            let kind: String
            switch fact.fact {
            case .turnCompleted(let elapsed): kind = "completed_turn_\(Int(max(0, elapsed) / 1000))s"
            case .toolOutcome(let runner, let outcome): kind = "\(runner ?? "tool")_\(outcome.rawValue)"
            case .errorClass(let error): kind = error
            case .moment(let old) where old != .nthRateLimit: kind = old.rawValue
            default: return nil
            }
            return RememberedMoment(kind: kind, day: fact.day)
        }.prefix(5).map { $0 }
    }

    var promptFields: [String: Any] {
        var result: [String: Any] = [
            "completed_turns": completedTurns, "lifetime_sessions": lifetimeSessions,
            "known_project_count": knownProjects,
            "recent_moments": moments.map { ["kind": $0.kind, "day": $0.day] }
        ]
        if let currentHourIsTypical { result["current_hour_is_typical"] = currentHourIsTypical }
        return result
    }
}
