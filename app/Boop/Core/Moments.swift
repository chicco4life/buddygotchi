import Foundation

struct Moment: Encodable, Sendable, Equatable {
    enum Kind: String, Encodable, Sendable { case hardWonPass, redStreakEnded, backAfterAbsence, sameFileAgain, lateNight, nthRateLimit, firstEver }
    var kind: Kind
    var facts: [String: String]
    var dances: Bool { kind == .hardWonPass || kind == .redStreakEnded }
}
struct MomentThresholds: Sendable, Equatable {
    var hardWonFailures = 5
    var redStreakFailures = 3
    var redStreakMs: Double = 600_000
    var absenceDays = 14
    var sameFileEdits = 20
    var lateNightStart = 0
    var lateNightEnd = 5 // exclusive
    var rateLimits = 3
    var stuckAttempts = 6
    static let defaults = Self()
}
enum MomentLines {
    static func line(_ m: Moment) -> String {
        switch m.kind {
        case .hardWonPass: return "\(m.facts["attempts"] ?? "0") tries. nice job on the tests."
        case .redStreakEnded: return "green at last."
        case .backAfterAbsence: return "back at it: \(m.facts["project"] ?? "project")"
        case .sameFileAgain: return "\(m.facts["path"] ?? "file") again."
        case .lateNight: return "late one."
        case .nthRateLimit: return "hungry again (\(m.facts["n"] ?? "3"))."
        case .firstEver: return "first one!"
        }
    }
}
