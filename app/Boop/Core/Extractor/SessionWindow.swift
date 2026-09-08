import Foundation

enum GoalOutcome: String, Codable, Sendable { case pass, fail, unknown }
struct GoalTally: Sendable, Equatable {
    var attempts = 0
    var attemptsWithoutPass = 0
    var firstFailureAt: Double?
    var lastOutcome: GoalOutcome = .unknown

    mutating func record(_ outcome: GoalOutcome, at: Double) {
        attempts += 1
        switch outcome {
        case .pass: attemptsWithoutPass = 0; firstFailureAt = nil
        case .fail:
            attemptsWithoutPass += 1
            if firstFailureAt == nil { firstFailureAt = at }
        case .unknown: attemptsWithoutPass = 0; firstFailureAt = nil
        }
        lastOutcome = outcome
    }
}
struct SessionWindow: Sendable {
    static let pendingCap = 400
    var goals: [String: GoalTally] = [:]
    var pending: [(goalKey: String, runner: String, tool: String, callId: String?)] = []
    var project: String
    var startedAt: Double
    var errors = 0
    var edits: [String: Int] = [:]
    var closingLine: String?
    var lastEffort: EffortTier = .light
    var turns = 0
    var tasks = 0
}
enum ToneClass: String, Encodable, Sendable { case question, negative, positive, neutral }
enum Fact: Encodable, Sendable, Equatable {
    case goalOutcome(goalKey: String, runner: String, outcome: GoalOutcome, attempts: Int, elapsedMs: Double)
    case project(id: String)
    case topics([String])
    case tone(ToneClass)
    case errorClass(String)
    case sessionSummary(turns: Int, tasks: Int, elapsedMs: Double)
}
@MainActor final class FactRing {
    private(set) var facts: [Fact] = []
    func receive(_ incoming: [Fact]) { facts.append(contentsOf: incoming); if facts.count > 500 { facts.removeFirst(facts.count - 500) } }
}
