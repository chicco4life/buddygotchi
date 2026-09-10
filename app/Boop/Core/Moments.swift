import Foundation

// Historical fact vocabulary only. No named moment detection or presentation.
enum Moment {
    // nthRateLimit is decode-only compatibility for historical stored facts.
    enum Kind: String, Codable, CaseIterable, Sendable { case hardWonPass, redStreakEnded, backAfterAbsence, sameFileAgain, lateNight, nthRateLimit, firstEver }
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
