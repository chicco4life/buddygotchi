import Foundation
import CryptoKit

struct Runner: Decodable, Sendable {
    let name: String
    let match: String
    let passPatterns: [String]?
    let failPatterns: [String]?
}
enum GoalsReader {
    struct Compiled: Sendable {
        let runner: Runner
        let match: NSRegularExpression
        let pass: [NSRegularExpression]
        let fail: [NSRegularExpression]
    }
    static let defaultPass = ["\\b[1-9][0-9]* (?:passed)\\b", "\\b(?:BUILD SUCCESSFUL|BUILD SUCCESS|Build complete)\\b", "Test Suite .* passed", "\\bTests?:.*\\bpassed\\b"]
    static let defaultFail = ["\\b[1-9][0-9]* (?:failed|failures|errors)\\b", "\\b(?:FAIL|FAILURE|error:)\\b", "(?:^|\\n)FAILED\\b", "BUILD FAILED", "\\*\\* TEST FAILED \\*\\*"]
    static let runners: [Compiled] = {
        guard let url = Bundle.module.url(forResource: "runners", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Runner].self, from: data) else { return [] }
        return entries.compactMap { r in
            guard let match = try? NSRegularExpression(pattern: r.match) else { return nil }
            return Compiled(runner: r, match: match, pass: (r.passPatterns ?? defaultPass).compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }, fail: (r.failPatterns ?? defaultFail).compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) })
        }
    }()
    static let byName = Dictionary(uniqueKeysWithValues: runners.map { ($0.runner.name, $0) })
    static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool { regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    static func runner(_ command: String) -> Compiled? { runners.first { matches($0.match, command) } }
    static func command(_ input: String?, dictionary: [String: Any]? = nil) -> String? {
        guard let input else { return nil }
        if let d = dictionary ?? input.data(using: .utf8).flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }) { return d["command"] as? String ?? d["cmd"] as? String }
        return input
    }
    private static let volatile = try! NSRegularExpression(pattern: #"(?:2>&1|--(?:timestamp|output|log-file|color|seed)(?:=|\s+)\S+|--no-color|\b\d{4}-\d{2}-\d{2}T\S+)"#)
    static func signature(_ command: String) -> String {
        let cleaned = volatile.stringByReplacingMatches(in: command, range: NSRange(command.startIndex..., in: command), withTemplate: "")
        let normalized = cleaned.split(whereSeparator: { $0.isWhitespace }).map { token in
            token.contains("/") ? (String(token) as NSString).lastPathComponent : String(token)
        }.joined(separator: " ")
        return SHA256.hash(data: Data(normalized.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    static func outcome(_ payload: RawHookPayload, runner: Compiled, output: String? = nil) -> GoalOutcome {
        if let status = payload.exitStatus { return status == 0 ? .pass : .fail }
        let output = output ?? (payload.outputHead ?? "") + "\n" + (payload.outputTail ?? "")
        if runner.fail.contains(where: { matches($0, output) }) { return .fail }
        if runner.pass.contains(where: { matches($0, output) }) { return .pass }
        return .unknown
    }
}
enum EffortReader {
    static func read(_ w: SessionWindow, at: Double, thresholds: MomentThresholds = .defaults) -> EffortTier {
        let attempts = w.goals.values.map(\.attemptsWithoutPass).max() ?? 0
        if attempts >= thresholds.effortGrindingAttempts || w.errors >= thresholds.effortGrindingErrors || at - w.startedAt >= PetTuning.effortGrindingMinMs { return .grinding }
        if attempts >= thresholds.effortHardAttempts || w.errors >= thresholds.effortHardErrors || at - w.startedAt >= PetTuning.effortHardMinMs { return .hard }
        return .light
    }
}
enum GlossWriter {
    static func read(tool: String, input: String, dictionary: [String: Any]? = nil) -> String {
        let s = input.lowercased()
        if CardStakesPolicy.destructiveLiterals.contains(where: s.contains) || tool.lowercased().contains("delete") { return "deletes files in this folder" }
        if s.contains("install") || s.contains(" add ") { return "installs packages" }
        if s.contains("curl ") || s.contains("wget ") || s.contains("https://") { return "reaches the internet" }
        if activityKind(tool: tool, hint: input) == .write { return "edits " + (ThemeReader.path(input, dictionary: dictionary) ?? "file") }
        if activityKind(tool: tool, hint: input) == .read { return "reads files" }
        return "runs a command"
    }
}
enum StakesReader {
    static func read(tool: String, input: String, dictionary: [String: Any]? = nil) -> (Stakes, String) {
        let parsed = dictionary ?? input.data(using: .utf8).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let command = GoalsReader.command(input, dictionary: parsed) ?? input
        return (cardStakes(tool: tool, hint: command), GlossWriter.read(tool: tool, input: input, dictionary: parsed))
    }
}
enum ThemeReader {
    static func project(cwd: String?) -> String {
        guard let cwd else { return "unknown" }
        let root = URL(fileURLWithPath: cwd)
        var git = root.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: git, encoding: .utf8), pointer.hasPrefix("gitdir: ") {
            git = URL(fileURLWithPath: pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root).standardizedFileURL
        }
        if let common = try? String(contentsOf: git.appendingPathComponent("commondir"), encoding: .utf8) { git = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git).standardizedFileURL }
        guard let config = try? String(contentsOf: git.appendingPathComponent("config"), encoding: .utf8) else { return cwdLabel(cwd) ?? "unknown" }
        var inRemote = false
        for line in config.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inRemote = line.hasPrefix("[remote ") }
            if inRemote && line.hasPrefix("url"), let split = line.firstIndex(of: "=") {
                let remote = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
                let digest = stableHashCwd(remote)
                return (cwdLabel(cwd) ?? "unknown") + "-" + digest
            }
        }
        return cwdLabel(cwd) ?? "unknown"
    }
    static func path(_ input: String, dictionary: [String: Any]? = nil) -> String? {
        guard let d = dictionary ?? input.data(using: .utf8).flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }), let p = d["file_path"] as? String ?? d["path"] as? String else { return nil }
        return (p as NSString).lastPathComponent
    }
    static func tone(_ prompt: String) -> ToneClass {
        let s = prompt.lowercased()
        if s.contains("?") { return .question }
        if ["hate", "broken", "frustrat"].contains(where: s.contains) { return .negative }
        if ["love", "great", "thanks"].contains(where: s.contains) { return .positive }
        return .neutral
    }
    // A fixed vocabulary prevents arbitrary prompt content becoming durable facts.
    static func topics(_ prompt: String) -> [String] { let lower = prompt.lowercased(); return ["test", "build", "lint", "swift", "python", "auth", "ui", "docs"].filter { lower.contains($0) }.prefix(3).map { $0 } }
}
