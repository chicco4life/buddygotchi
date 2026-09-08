import Foundation
import CryptoKit

struct Runner: Decodable, Sendable {
    let name: String
    let kind: String
    let match: String
    let passPatterns: [String]
    let failPatterns: [String]
}
enum GoalsReader {
    struct Compiled: Sendable {
        let runner: Runner
        let match: NSRegularExpression
        let pass: [NSRegularExpression]
        let fail: [NSRegularExpression]
    }
    static let runners: [Compiled] = {
        guard let url = Bundle.module.url(forResource: "runners", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Runner].self, from: data) else { return [] }
        return entries.compactMap { r in
            guard let match = try? NSRegularExpression(pattern: r.match) else { return nil }
            return Compiled(runner: r, match: match, pass: r.passPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }, fail: r.failPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) })
        }
    }()
    static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool { regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    static func runner(_ command: String) -> Compiled? { runners.first { matches($0.match, command) } }
    static func command(_ input: String?) -> String? {
        guard let input else { return nil }
        if let data = input.data(using: .utf8), let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return d["command"] as? String ?? d["cmd"] as? String }
        return input
    }
    private static let volatile = try! NSRegularExpression(pattern: #"(?:2>&1|--(?:timestamp|output|log-file|color|seed)(?:=|\s+)\S+|--no-color|\b\d{4}-\d{2}-\d{2}T\S+)"#)
    static func signature(_ command: String, project: String) -> String {
        let cleaned = volatile.stringByReplacingMatches(in: command, range: NSRange(command.startIndex..., in: command), withTemplate: "")
        let normalized = cleaned.split(whereSeparator: { $0.isWhitespace }).map { token in
            token.contains("/") ? (String(token) as NSString).lastPathComponent : String(token)
        }.joined(separator: " ")
        return project + "|" + normalized
    }
    static func outcome(_ payload: RawHookPayload, runner: Compiled) -> GoalOutcome {
        if let status = payload.exitStatus { return status == 0 ? .pass : .fail }
        let output = (payload.outputHead ?? "") + "\n" + (payload.outputTail ?? "")
        if runner.fail.contains(where: { matches($0, output) }) { return .fail }
        if runner.pass.contains(where: { matches($0, output) }) { return .pass }
        return .unknown
    }
}
enum LifecycleReader {
    static func read(_ p: RawHookPayload) -> [BuddyEvent] {
        switch p.kind {
        case .sessionStart: return [.sessionStarted(at: p.timestamp, sessionId: p.sessionId, source: p.source, cwd: p.cwd)]
        case .sessionEnd: return [.sessionEnded(at: p.timestamp, sessionId: p.sessionId)]
        case .turnStart: return [.turnStarted(at: p.timestamp, sessionId: p.sessionId, source: p.source)]
        case .turnEnd: return p.closingOnly ? [] : [.turnEnded(at: p.timestamp, sessionId: p.sessionId, source: p.source, outcome: p.errorClass.map { .failed(errorClass: $0) } ?? .completed)]
        default: return []
        }
    }
}
enum EffortReader {
    static func read(_ w: SessionWindow, at: Double, reported: EffortTier? = nil) -> EffortTier {
        if let reported { return reported }
        let attempts = w.goals.values.map(\.attemptsWithoutPass).max() ?? 0
        if attempts >= 6 || w.errors >= 3 || at - w.startedAt >= PetTuning.effortGrindingMinMs { return .grinding }
        if attempts >= 3 || w.errors >= 2 || at - w.startedAt >= PetTuning.effortHardMinMs { return .hard }
        return .light
    }
}
enum GlossWriter {
    static func read(tool: String, input: String) -> String {
        let s = input.lowercased()
        if s.contains("rm ") || tool.lowercased().contains("delete") { return "deletes files in this folder" }
        if s.contains("install") || s.contains(" add ") { return "installs packages" }
        if s.contains("curl ") || s.contains("wget ") || s.contains("https://") { return "reaches the internet" }
        if tool.lowercased().contains("edit") || tool.lowercased().contains("write") { return "edits " + (ThemeReader.path(input) ?? "file") }
        if ["read", "glob", "grep"].contains(tool.lowercased()) { return "reads files" }
        return "runs a command"
    }
}
enum StakesReader {
    static func read(tool: String, input: String) -> (Stakes, String) {
        let command = GoalsReader.command(input) ?? input
        return (cardStakes(tool: tool, hint: command), GlossWriter.read(tool: tool, input: input))
    }
}
enum ThemeReader {
    static func project(cwd: String?) -> String { cwd.map { ($0 as NSString).lastPathComponent } ?? "unknown" }
    static func projectIdentity(cwd: String?) -> String {
        guard let cwd else { return "unknown" }
        let root = URL(fileURLWithPath: cwd)
        var git = root.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: git, encoding: .utf8), pointer.hasPrefix("gitdir: ") {
            git = URL(fileURLWithPath: pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root).standardizedFileURL
        }
        if let common = try? String(contentsOf: git.appendingPathComponent("commondir"), encoding: .utf8) { git = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git).standardizedFileURL }
        guard let config = try? String(contentsOf: git.appendingPathComponent("config"), encoding: .utf8) else { return project(cwd: cwd) }
        var inRemote = false
        for line in config.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inRemote = line.hasPrefix("[remote ") }
            if inRemote && line.hasPrefix("url"), let split = line.firstIndex(of: "=") {
                let remote = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
                let digest = SHA256.hash(data: Data(remote.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
                return project(cwd: cwd) + "-" + digest
            }
        }
        return project(cwd: cwd)
    }
    static func path(_ input: String) -> String? {
        guard let data = input.data(using: .utf8), let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let p = d["file_path"] as? String ?? d["path"] as? String else { return nil }
        return (p as NSString).lastPathComponent
    }
    static func tone(_ prompt: String) -> String {
        let s = prompt.lowercased()
        if s.contains("?") { return "question" }
        if ["hate", "broken", "frustrat"].contains(where: s.contains) { return "negative" }
        if ["love", "great", "thanks"].contains(where: s.contains) { return "positive" }
        return "neutral"
    }
    // A fixed vocabulary prevents arbitrary prompt content becoming durable facts.
    static func topics(_ prompt: String) -> [String] { ["test", "build", "lint", "swift", "python", "auth", "ui", "docs"].filter { prompt.lowercased().contains($0) }.prefix(3).map { $0 } }
}
enum ClosingLineReader {
    static func read(_ text: String) -> String { String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(120)) }
}
