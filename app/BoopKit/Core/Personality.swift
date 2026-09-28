import Foundation

/// Who Boop is: a file in `plan/steering/personality/`, chosen in Settings
/// (BEHAVIORS.md §6, harness/DECISIONS.md §2.2). Its settings drive the
/// core's rules; its text is the PERSONALITY section of Jev's state.
public enum Personality: String, CaseIterable, Sendable {
    /// The default.
    case boop
    /// For debugging: reacts to everything, over the top.
    case chatter

    /// The settings a personality file's front matter sets for the core.
    public struct Rules: Equatable, Sendable {
        /// Which finished tool calls become events (harness/EVENTS.md §4).
        public enum ToolUses: String, Sendable { case notable, all }

        /// The working heartbeat's wait, in milliseconds, or none
        /// (harness/EVENTS.md §4).
        public var workBeatMs: ClosedRange<Int>?
        public var toolUses: ToolUses

        public init(workBeatMs: ClosedRange<Int>? = 120_000...240_000, toolUses: ToolUses = .notable) {
            self.workBeatMs = workBeatMs
            self.toolUses = toolUses
        }

        /// Reads `working_heartbeat` and `tool_uses` from a front-matter block;
        /// anything missing or unreadable keeps its default.
        public init(frontMatter: String) {
            self.init()
            for line in frontMatter.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "tool_uses": if let t = ToolUses(rawValue: parts[1]) { toolUses = t }
                case "working_heartbeat":
                    if parts[1] == "none" {
                        workBeatMs = nil
                    } else {
                        let bounds = parts[1].split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if bounds.count == 2, bounds[0] > 0, bounds[0] <= bounds[1] {
                            workBeatMs = bounds[0] * 1000...bounds[1] * 1000
                        }
                    }
                default: break
                }
            }
        }
    }
}
