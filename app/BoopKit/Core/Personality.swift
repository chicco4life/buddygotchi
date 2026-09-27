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
        public enum Cheer: String, Sendable {
            /// Every finished turn gets the rule's cheer.
            case every
            /// Only one over a minute (`very long`).
            case long
        }

        public var cheer: Cheer
        /// Working chatter every so many milliseconds, or none.
        public var chatterMs: ClosedRange<Int>?
        public var toolUses: Core.ToolUses

        public init(cheer: Cheer = .every, chatterMs: ClosedRange<Int>? = 120_000...240_000,
                    toolUses: Core.ToolUses = .notable) {
            self.cheer = cheer
            self.chatterMs = chatterMs
            self.toolUses = toolUses
        }

        /// Whether a finished turn of this length gets the rule's cheer.
        public func cheers(lengthMs: Int64) -> Bool {
            cheer == .every || Band.length(ms: lengthMs) == "very long"
        }

        /// Reads `cheer`, `chatter` and `tool_uses` from a front-matter
        /// block; anything missing or unreadable keeps its default.
        public init(frontMatter: String) {
            self.init()
            for line in frontMatter.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "cheer": if let c = Cheer(rawValue: parts[1]) { cheer = c }
                case "tool_uses": if let t = Core.ToolUses(rawValue: parts[1]) { toolUses = t }
                case "chatter":
                    if parts[1] == "none" {
                        chatterMs = nil
                    } else {
                        let bounds = parts[1].split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if bounds.count == 2, bounds[0] > 0, bounds[0] <= bounds[1] {
                            chatterMs = bounds[0] * 1000...bounds[1] * 1000
                        }
                    }
                default: break
                }
            }
        }
    }
}
