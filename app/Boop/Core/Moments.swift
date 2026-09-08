import Foundation

struct Moment: Encodable, Sendable, Equatable {
    enum Kind: String, Encodable, Sendable { case hardWonPass, redStreakEnded, backAfterAbsence, sameFileAgain, lateNight, nthRateLimit, firstEver }
    var kind: Kind
    var facts: [String: String]
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
    var effortHardAttempts = 3
    var effortGrindingAttempts = 6
    var effortHardErrors = 2
    var effortGrindingErrors = 3
    static let defaults = Self()
}
enum MomentLines {
    static func line(_ m: Moment) -> String {
        switch m.kind {
        case .hardWonPass:
            let label = RunnerLabel.subject(m.facts["runner"] ?? "")
            return "\(m.facts["attempts"] ?? "0") tries. nice job" + (label.map { " on the " + $0 } ?? "") + "."
        case .redStreakEnded: return "green at last."
        case .backAfterAbsence: return "back at it: \(m.facts["project"] ?? "project")"
        case .sameFileAgain: return "\(m.facts["path"] ?? "file") again."
        case .lateNight: return "late one."
        case .nthRateLimit: return "hungry again (\(m.facts["n"] ?? "3"))."
        case .firstEver: return "first one!"
        }
    }
}

extension CheerSize {
    static func `for`(moment: Moment?, thresholds: CheerThresholds, errors: Int, span: Double, effort: EffortTier) -> CheerSize? {
        switch moment?.kind {
        case .nthRateLimit: return nil
        case .hardWonPass, .redStreakEnded: return .dance
        default: return thresholds.size(errors: errors, span: span, effort: effort)
        }
    }
}

// Display vocabulary shared by activity classification and authored moment lines.
enum RunnerLabel {
    static func subject(_ name: String) -> String? {
        if name.contains("test") || ["jest", "mocha", "rspec", "cargo-bench"].contains(name) { return "tests" }
        if name.contains("build") || ["gradle", "mvn"].contains(name) { return "build" }
        if name.contains("lint") || ["eslint", "ruff", "cargo-clippy", "go-vet"].contains(name) { return "lint" }
        return nil
    }
}
