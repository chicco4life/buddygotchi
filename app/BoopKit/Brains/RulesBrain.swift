import Foundation

/// No model: answers from the Fallbacks table in `steering.md`, which it reads
/// from the system prompt like any brain would. Always available.
///
/// A row's condition is a trigger (`Turn started`, `Turn finished`, `Turn
/// failed`, `Tap`, `Talk`) with optional qualifiers after commas: `long`
/// (took 5 min or more), `containing "a" or "b"` (talk words), `anything
/// else`. `Anything else` alone matches
/// everything. The row with the most matching qualifiers wins; ties go to the
/// first. A row with a qualifier this brain doesn't know never matches.
public struct RulesBrain: Brain {
    public let id = "rules@1"

    public init() {}

    /// Ignores the history. Leaves out calls to tools that aren't offered or
    /// that the now section names as past a limit (`say limit: …`).
    public func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                         deadline: Duration) async throws -> String {
        let rows = RulesBrain.fallbacks(system)
        guard !rows.isEmpty else { throw BrainError("no Fallbacks table in steering") }
        let now = Prompt.now(in: user)
        let limited = Set(now.components(separatedBy: "\n").compactMap { line in
            line.range(of: " limit: ").map { String(line[..<$0.lowerBound]) }
        })
        let calls = RulesBrain.pick(rows, now: now)
        return Answer.json(calls.filter { call in tools.contains { $0.name == call.name } && !limited.contains(call.name) })
    }

    public struct Row: Equatable, Sendable {
        public var condition: String
        public var calls: [ToolCall]
    }

    /// The table's rows: condition, then calls like `say(feeling: proud, word: finally)`.
    public static func fallbacks(_ steering: String) -> [Row] {
        var rows: [Row] = []
        var inTable = false
        for line in steering.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { inTable = line == "## Fallbacks" }
            guard inTable, line.hasPrefix("|") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 2, cells[0] != "Trigger", !cells[0].hasPrefix("---") else { continue }
            rows.append(Row(condition: cells[0], calls: calls(cells[1])))
        }
        return rows
    }

    /// `` `say(feeling: annoyed)`, `quiet(minutes: 30)` `` → calls; anything else → none.
    static func calls(_ cell: String) -> [ToolCall] {
        cell.components(separatedBy: "`").enumerated().compactMap { i, part in
            guard i % 2 == 1, let open = part.firstIndex(of: "("), part.hasSuffix(")") else { return nil }
            let name = String(part[..<open])
            var args: [String: ToolValue] = [:]
            for pair in part[part.index(after: open)..<part.index(before: part.endIndex)].split(separator: ",") {
                let kv = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                args[kv[0]] = Int(kv[1]).map(ToolValue.number) ?? .string(kv[1])
            }
            return ToolCall(name, args)
        }
    }

    /// What happened, read from the now section of the prompt.
    struct Now {
        var what: String
        var tookMinutes: Int?
        var words: String?

        init(_ now: String) {
            let lines = now.components(separatedBy: "\n")
            let fields = (lines.first ?? "").components(separatedBy: " · ")
            what = fields.first ?? ""
            tookMinutes = fields.first { $0.hasPrefix("took ") }.map { f in
                f.hasSuffix(" min") ? Int(f.dropFirst(5).dropLast(4)) ?? 0 : 0
            }
            words = lines.first { $0.hasPrefix("they said: ") }.map { String($0.dropFirst("they said: ".count)) }
        }

        /// The condition's trigger names this.
        func matches(_ trigger: String) -> Bool {
            switch trigger {
            case "turn started": what == "turn started"
            case "turn finished": what == "turn finished"
            case "turn failed": what == "turn failed"
            case "tap": what == "tapped"
            case "talk": what == "talk"
            case "anything else": true
            default: false
            }
        }
    }

    static let triggers = ["turn started", "turn finished", "turn failed", "tap", "talk", "anything else"]

    /// `Talk containing "a" or "b"` → (`talk`, [`containing "a" or "b"`]);
    /// `Turn finished, long` → (`turn finished`, [`long`]).
    static func parse(_ condition: String) -> (trigger: String, qualifiers: [String])? {
        let lower = condition.lowercased()
        guard let trigger = triggers.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = condition.dropFirst(trigger.count).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        let qualifiers = rest.isEmpty ? [] : rest.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (trigger, qualifiers)
    }

    static func pick(_ rows: [Row], now text: String) -> [ToolCall] {
        let now = Now(text)
        var best: (score: Int, calls: [ToolCall])?
        for row in rows {
            guard let (trigger, qualifiers) = parse(row.condition), now.matches(trigger) else { continue }
            var score = trigger == "anything else" ? 0 : 1
            var fits = true
            for q in qualifiers {
                let lower = q.lowercased()
                if lower == "anything else" {
                    continue
                } else if lower == "long" {
                    fits = (now.tookMinutes ?? 0) >= 5
                } else if lower.hasPrefix("containing ") {
                    let phrases = q.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                    let words = (now.words ?? "").lowercased()
                    fits = !phrases.isEmpty && phrases.contains { words.contains($0.lowercased()) }
                } else {
                    fits = false
                }
                if !fits { break }
                score += 1
            }
            if fits, best == nil || score > best!.score { best = (score, row.calls) }
        }
        return best?.calls ?? []
    }
}
