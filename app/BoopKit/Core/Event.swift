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
    /// The thread it's about, as the core keys its sessions, for tests;
    /// the harness never reads it. Nil for pokes, taps and idle heartbeats.
    public var about: String?
    public var facts: [String: JSONValue]

    public init(_ kind: Kind, at ms: Int64, line: String, reaction: String? = nil, wakesBrain: Bool,
                about: String? = nil, facts: [String: JSONValue] = [:]) {
        self.kind = kind
        self.receivedAtMs = ms
        self.line = line
        self.reaction = reaction
        self.wakesBrain = wakesBrain
        self.about = about
        self.facts = facts
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
    /// A turn's length or a tool call's time, as the moods read it: short
    /// under a minute, long under 5 minutes, very long past that.
    public static func length(ms: Int64) -> String {
        ms < 60_000 ? "short" : ms < 5 * 60_000 ? "long" : "very long"
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

    public static func turnStart(agent: String, turn: Int, thread: String) -> String {
        "\(agent) started turn \(turn) on \(thread)."
    }

    /// `claude finished turn 7 on "fix-nav" (landing): done, a very long
    /// turn.`: the outcome and the length band, nothing else.
    public static func turnEnd(agent: String, turn: Int, thread: String, outcome: String, lengthMs: Int64) -> String {
        let how = outcome == "failed" || outcome == "stopped" ? outcome : "done"
        return "\(agent) finished turn \(turn) on \(thread): \(how), a \(Band.length(ms: lengthMs)) turn."
    }

    /// A tool use that woke the brain: a check that failed, or passed after
    /// failing.
    public static func check(agent: String, topic: String, thread: String, failed: Bool) -> String {
        "\(agent)'s \(topic) \(failed ? "failed" : "passed") on \(thread)\(failed ? "" : " after failing")."
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

    public static let pokes = "You poked Boop again and again."

    public static func heartbeat(hours: Int) -> String {
        "Nothing has happened for \(hours) hour\(hours == 1 ? "" : "s")."
    }

    /// The working heartbeat: `claude is still working on "fix-nav"
    /// (landing), a long turn.`, the band of the turn so far.
    public static func working(agent: String, thread: String, ms: Int64) -> String {
        "\(agent) is still working on \(thread), a \(Band.length(ms: ms)) turn."
    }

    /// The words the lines use, as the guide explains them after how to
    /// read the layout (EVENTS.md §8.1). Kept here, next to the lines.
    public static let words = """
        - claude and codex are the person's coding agents.
        - A thread is one conversation with an agent, named after its workspace:
          "fix-nav" (landing) is the thread fix-nav in the project landing.
        - A turn is one request to a thread. It ends done, failed or stopped.
        - Tests, build, deploy and docs are what a command was about; failed
          means it ended with an error.
        - Turns are short (under a minute), long (under 5 minutes) or very
          long (5 minutes or more).
        """

    public static let tap = "You tapped Boop."

    public static func needsYou(agent: String, thread: String) -> String {
        "\(agent) needs you on \(thread)."
    }

    public static let wiggled = "Boop wiggled on its own."

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
