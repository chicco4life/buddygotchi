import Foundation

enum GoalOutcome: String, Codable, Sendable { case pass, fail, unknown }
struct SessionWindow: Sendable {
    static let pendingCap = 400
    var pending: [(runner: String, tool: String, callId: String?)] = []
    var project: String
    var startedAt: Double
    var closingLine: String?
    var turns = 0
    var completedTurns = 0
    var workActive = false
    var sawTool = false
}
enum ToneClass: String, Codable, Sendable { case question, negative, positive, neutral }
enum Fact: Codable, Sendable, Equatable {
    case toolOutcome(runner: String?, outcome: GoalOutcome)
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
        case .toolOutcome: "toolOutcome"
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
