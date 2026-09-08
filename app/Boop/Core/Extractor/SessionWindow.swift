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
    var sawTool = false
}
enum ToneClass: String, Codable, Sendable { case question, negative, positive, neutral }
enum Fact: Codable, Sendable, Equatable {
    case turnCompleted(elapsedMs: Double)
    case goalOutcome(goalKey: String, runner: String, outcome: GoalOutcome, attempts: Int, elapsedMs: Double)
    case tokens(output: Int)
    case moment(Moment.Kind)
    case activity(hour: Int, tool: String?, firstGoal: String?)
    case checkIn(collected: Bool)
    case greet
    case denial
    case project(id: String)
    case topics([String])
    case tone(ToneClass)
    case errorClass(String)
    case sessionSummary(turns: Int, tasks: Int, elapsedMs: Double)
    var kind: String {
        switch self {
        case .turnCompleted: "turnCompleted"
        case .goalOutcome: "goalOutcome"
        case .tokens: "tokens"
        case .moment: "moment"
        case .activity: "activity"
        case .checkIn: "checkIn"
        case .greet: "greet"
        case .denial: "denial"
        case .project: "project"
        case .topics: "topics"
        case .tone: "tone"
        case .errorClass: "errorClass"
        case .sessionSummary: "sessionSummary"
        }
    }
}
