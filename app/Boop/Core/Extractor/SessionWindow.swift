import Foundation

enum GoalOutcome: String, Codable, Sendable { case pass, fail, unknown }
struct GoalTally: Sendable, Equatable {
    var attempts = 0
    var failures = 0
    var consecutiveFailures = 0
    var attemptsWithoutPass = 0
    var lastOutcome: GoalOutcome = .unknown
    var firstAt: Double
    var firstFailureAt: Double?
}
struct SessionWindow: Sendable {
    enum EntryKind: Sendable { case turnStart, toolCall, toolResult, turnEnd, closingMessage }
    struct Entry: Sendable {
        var kind: EntryKind
        var at: Double
        var text: String
    }
    static let entryCap = 400
    static let byteCap = 512 * 1024
    var entries: [Entry] = []
    var byteCount = 0
    var goals: [String: GoalTally] = [:]
    var pending: [(signature: String, runner: String, tool: String, callId: String?)] = []
    var project: String
    var startedAt: Double
    var errors = 0
    var edits: [String: Int] = [:]
    var topics: [String] = []
    mutating func append(_ entry: Entry) {
        var entry = entry
        entry.text = capUTF8(entry.text, Self.byteCap)
        entries.append(entry); byteCount += entry.text.utf8.count
        while entries.count > Self.entryCap || byteCount > Self.byteCap { byteCount -= entries.removeFirst().text.utf8.count }
    }
}
struct Fact: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case goalOutcome, theme, tone, errorClass, sessionSummary }
    var kind: Kind
    var sessionId: String
    var project: String
    var at: Double
    var payload: [String: String]
}
@MainActor protocol FactSink: AnyObject, Sendable { func receive(_ facts: [Fact]) }
@MainActor final class FactRing: FactSink {
    private(set) var facts: [Fact] = []
    func receive(_ incoming: [Fact]) { facts.append(contentsOf: incoming); if facts.count > 500 { facts.removeFirst(facts.count - 500) } }
}
