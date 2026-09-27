import Foundation

/// A failed tool call's error as a short class (harness/EVENTS.md §4):
/// `boop-hook` reads the error's text in memory and keeps only this.
public enum ToolError {
    public static func classify(_ text: String?) -> String {
        guard let text = text?.lowercased(), !text.isEmpty else { return "other" }
        if text.contains("timed out") || text.contains("timeout") { return "timeout" }
        if ["denied", "not allowed", "rejected", "permission"].contains(where: text.contains) { return "denied" }
        if ["exit code", "exited", "non-zero", "status code"].contains(where: text.contains) { return "exit_code" }
        return "other"
    }
}
