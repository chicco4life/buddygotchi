import Foundation

// MARK: - Activity Kind

enum ActivityKind: String, Encodable, Sendable, Equatable {
    case verify
    case read
    case write
    case shell
    case web
    case work

    /// SF Symbol used for visual decoration in the popover. Output-side concern;
    /// kept here so callers don't have to hardcode the mapping.
    var sfSymbol: String {
        switch self {
        case .verify: "checkmark.seal"
        case .read: "doc.text"
        case .write: "pencil"
        case .shell: "terminal"
        case .web: "globe"
        case .work: "ellipsis.circle"
        }
    }
}

// MARK: - Classifier (pure)

/// Classify a tool + hint pair into an activity kind. Pure function — no IO.
/// Used by both the reducer (when stashing) and any future Heartbeat/UI paths.
func activityKind(tool: String, hint: String) -> ActivityKind {
    switch tool {
    case "Read", "Glob", "Grep", "LSP":
        return .read
    case "WebFetch", "WebSearch":
        return .web
    case "Edit", "Write", "MultiEdit", "NotebookEdit":
        return .write
    case "Bash", "Shell":
        if GoalsReader.runner(hint).map { RunnerLabel.subject($0.runner.name) == "tests" } == true {
            return .verify
        }
        return .shell
    default:
        return .work
    }
}
