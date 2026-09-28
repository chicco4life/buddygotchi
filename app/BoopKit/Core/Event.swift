import Foundation

/// Something that happened, as the core hands it to the harness
/// (harness/HARNESS.md §3): its line, what Boop already did about it by
/// rule, and whether it wakes the brain. Its facts are for logs and evals;
/// the harness never reads them. The kinds, their facts and their lines are
/// harness/EVENTS.md's.
public struct Event: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case turnStart = "turn_start"
        case turnEnd = "turn_end"
        case toolUse = "tool_use"
        case pokes
        case heartbeat
        case tap
        case needsYou = "needs_you"
    }

    public var kind: Kind
    public var receivedAtMs: Int64
    /// What happened, as HISTORY and NOW show it (EVENTS.md §8).
    public var line: String
    /// What Boop already did by rule, as its line; nil for nothing.
    public var reaction: String?
    public var wakesBrain: Bool
    /// The thread it's about, opaque to the harness, which only hands it
    /// back when it asks for the status line; nil for pokes, taps and
    /// heartbeats.
    public var about: String?
    public var facts: [String: JSONValue]
    /// The actions that sit this event's pass out, by name, as the core
    /// decides: their questions aren't asked and they don't run (a poke
    /// streak leaves the mood alone, EVENTS.md §6). The harness honours it
    /// without knowing why.
    public var sitsOut: Set<String>

    public init(_ kind: Kind, at ms: Int64, line: String, reaction: String? = nil, wakesBrain: Bool,
                about: String? = nil, facts: [String: JSONValue] = [:], sitsOut: Set<String> = []) {
        self.kind = kind
        self.receivedAtMs = ms
        self.line = line
        self.reaction = reaction
        self.wakesBrain = wakesBrain
        self.about = about
        self.facts = facts
        self.sitsOut = sitsOut
    }

    /// The event as one JSON object, for `debug.jsonl`.
    public var json: [String: Any] {
        var o: [String: Any] = ["kind": kind.rawValue, "line": line, "wakes_brain": wakesBrain,
                                "facts": facts.mapValues(\.foundation)]
        o["reaction"] = reaction ?? NSNull()
        return o
    }

    /// `turn_end · claude finished …`, for debug mode.
    public var summary: String {
        "\(kind.rawValue)\(wakesBrain ? "" : " (no pass)") · \(line)" + (reaction.map { " · \($0)" } ?? "")
    }
}

/// Numbers named, so no brain has to compare them (EVENTS.md §5).
public enum Band {
    /// A turn's length or a tool call's time: short under 15 s, long up to a
    /// minute, very long past it.
    public static func length(ms: Int64) -> String {
        ms < 15_000 ? "short" : ms <= 60_000 ? "long" : "very long"
    }

    /// The gap before a turn start or a poke streak: right after under 2
    /// minutes, a while under an hour, a long break past it.
    public static func gap(ms: Int64) -> String {
        ms < 2 * 60_000 ? "right after" : ms < 60 * 60_000 ? "a while" : "a long break"
    }

    /// `18 min`, `8 s`, `2 h`: a duration as a line says it.
    public static func took(_ ms: Int64) -> String {
        ms < 60_000 ? "\(ms / 1000) s" : ms < 2 * 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
    }
}

/// The lines events and rule reactions are written as (EVENTS.md §8). Only
/// facts shown to Jev reach them.
public enum EventLine {
    /// A thread as the lines name it: `"fix-nav" (landing)`, or just
    /// `"landing"` when the name is the project.
    public static func thread(name: String, project: String) -> String {
        name == project ? "\"\(name)\"" : "\"\(name)\" (\(project))"
    }

    public static func turnStart(agent: String, turn: Int, thread: String, gap: String?) -> String {
        let when = switch gap {
        case "right after": ", right after its last one"
        case "a while": ", a while after its last one"
        case "a long break": ", after a long break"
        default: ""
        }
        return "\(agent) started turn \(turn) on \(thread)\(when)."
    }

    public static func turnEnd(agent: String, turn: Int, thread: String, outcome: String, error: String?,
                               lengthMs: Int64, tools: Int, toolsFailed: Int, topics: [(String, String)],
                               comeback: String?) -> String {
        let how = switch outcome {
        case "failed": "failed" + (error.map { " (\($0.replacingOccurrences(of: "_", with: " ")))" } ?? "")
        case "stopped": "stopped"
        default: "done"
        }
        var line = "\(agent) finished turn \(turn) on \(thread): \(how) after \(Band.took(lengthMs)), "
            + "a \(Band.length(ms: lengthMs)) turn, \(tools) tool\(tools == 1 ? "" : "s")"
            + (toolsFailed > 0 ? " (\(toolsFailed) failed)." : ".")
        if !topics.isEmpty {
            let states = topics.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
            line += " " + states.prefix(1).uppercased() + states.dropFirst() + "."
        }
        if let comeback { line += " A comeback on \(comeback)." }
        return line
    }

    /// A tool use that woke the brain: a check that failed, or passed after
    /// failing.
    public static func check(agent: String, topic: String, thread: String, failed: Bool, failedBefore: Int,
                             error: String?) -> String {
        let bracket = error.flatMap { $0 == "exit_code" ? nil : " (\(errorWords($0)))" } ?? ""
        if !failed {
            return "\(agent)'s \(topic) passed on \(thread) after \(failedBefore) failure\(failedBefore == 1 ? "" : "s") in a row."
        }
        if failedBefore == 0 { return "\(agent)'s \(topic) failed on \(thread)\(bracket)." }
        return "\(agent)'s \(topic) failed again on \(thread)\(bracket), \(failedBefore + 1) in a row."
    }

    /// Any other tool use, with the personality's `tool_uses: all`.
    public static func routine(agent: String, category: String, thread: String, failed: Bool?) -> String {
        let what = switch category {
        case "shell": "ran a command"
        case "edit": "edited a file"
        case "read": "read a file"
        case "search": "searched"
        case "web": "looked something up on the web"
        case "subagent": "started a subagent"
        default: "used a tool"
        }
        return "\(agent) \(what) on \(thread)." + (failed == true ? " It failed." : "")
    }

    public static func pokes(count: Int, seconds: Int, sinceLast: String?) -> String {
        let again = switch sinceLast {
        case "right after": ", again right after the last time"
        case "a while": ", again a while after the last time"
        case "a long break": ", again after a long break"
        default: ""
        }
        return "You poked Boop \(count) times in \(seconds) s\(again)."
    }

    public static func heartbeat(hours: Int) -> String {
        "Nothing has happened for \(hours) hour\(hours == 1 ? "" : "s")."
    }

    /// The working heartbeat: `claude has been working on "fix-nav"
    /// (landing) for 6 min, on tests.`, the topic only when there is one.
    public static func working(agent: String, thread: String, ms: Int64, topic: String?) -> String {
        "\(agent) has been working on \(thread) for \(Band.took(ms))" + (topic.map { ", on \($0)" } ?? "") + "."
    }

    /// The words the lines use, as the guide explains them after how to
    /// read the layout (EVENTS.md §8.1). Kept here, next to the lines.
    public static let words = """
        - claude and codex are the person's coding agents.
        - A thread is one conversation with an agent, named after its workspace:
          "fix-nav" (landing) is the thread fix-nav in the project landing.
        - A turn is one request to a thread. It ends done, failed or stopped.
        - Tests, build, deploy and docs are what a command was about; failed
          means it ended with an error. A comeback passed after failing.
        - Turns are short (under 15 s), long (under a minute) or very long.
        """

    public static let tap = "You tapped Boop."

    public static func needsYou(agent: String, thread: String) -> String {
        "\(agent) needs you on \(thread)."
    }

    public static let wiggled = "Boop wiggled on its own."

    static func errorWords(_ error: String) -> String {
        switch error {
        case "timeout": "timed out"
        case "denied": "denied"
        default: "error"
        }
    }

    /// The tool's category (EVENTS.md §4).
    public static func category(tool: String?) -> String {
        guard let tool else { return "other" }
        if tool.hasPrefix("mcp__") { return "mcp" }
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell": return "shell"
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": return "edit"
        case "Read": return "read"
        case "Grep", "Glob", "LS": return "search"
        case "WebFetch", "WebSearch": return "web"
        case "Task", "Agent": return "subagent"
        default: return "other"
        }
    }
}
