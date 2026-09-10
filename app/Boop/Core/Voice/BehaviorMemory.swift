import Foundation

/// Bounded recent outcomes; no identity counters, inferred habits or legacy moments.
struct BehaviorMemory: Sendable {
    struct RememberedMoment: Sendable, Equatable {
        var kind: String
        var day: String
    }
    var moments: [RememberedMoment]

    init(moments: [RememberedMoment] = []) { self.moments = Array(moments.prefix(5)) }

    static func recentMoments(from facts: [StoredFact]) -> [RememberedMoment] {
        facts.sorted { $0.at > $1.at }.compactMap { fact in
            let kind: String
            switch fact.fact {
            case .turnCompleted(let elapsed): kind = "completed_turn_\(Int(max(0, elapsed) / 1000))s"
            case .toolOutcome(let runner, let outcome): kind = "\(runner ?? "tool")_\(outcome.rawValue)"
            case .errorClass(let error): kind = error
            default: return nil
            }
            return RememberedMoment(kind: kind, day: fact.day)
        }.prefix(5).map { $0 }
    }

    var promptFields: [String: Any] {
        ["recent_outcomes": moments.map { ["kind": $0.kind, "day": $0.day] }]
    }
}
