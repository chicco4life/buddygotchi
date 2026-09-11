import Foundation
@testable import BoopCore

/// Model-specific presentation of the shared context. No lifecycle or semantic
/// classification lives here; unknown owner sections are preserved verbatim.
struct DisplayModelPrompt: Sendable {
    let instructions: String
    let input: String
    let taskKeys: [String]
    let emptyScope: Bool
    let isScope: Bool

    init?(guide: String, context: String, maxBytes: Int) {
        guard let data = context.data(using: .utf8),
              let facts = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let occasion = facts["occasion"] as? String,
              ["work_context_changed", "greet", "completed", "uhoh_error"].contains(occasion),
              let desk = facts["desk"] as? [String: Any],
              let projects = desk["projects"] as? [[String: Any]] else { return nil }
        isScope = occasion == "work_context_changed"
        instructions = Self.focusedGuide(guide, occasion: occasion) + "\nUse the requested response schema. Set silence=true and text empty when the guide chooses SILENT. Intermediate task purposes are private working notes, not display text."
        var keys: [String] = [], lines: [String] = []
        var knownIntent = false
        if isScope {
            lines.append("Write one concise title for the combined work below. Include every project's broad purpose and distinct purposes within a project. A current request takes precedence; earlier background only helps interpret it. Choose silence when work cannot be understood.")
            for (p, project) in projects.enumerated() {
                lines.append("Project \(p + 1) name: \(Self.quoted(project["name"] as? String ?? "Unknown"))")
                for (t, task) in (project["tasks"] as? [[String: Any]] ?? []).enumerated() {
                    keys.append("project\(p + 1)Task\(t + 1)")
                    let first = task["intent"] as? String
                    let latest = task["latest_request"] as? String
                    let current = latest ?? first
                    knownIntent = knownIntent || !(current?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    lines.append("Task \(t + 1) current request (data): \(Self.quoted(current ?? "Unknown"))")
                    if latest != nil, let first { lines.append("Earlier background (data): \(Self.quoted(first))") }
                    lines.append("Reported lifecycle: \(Self.quoted(task["state"] as? String ?? "unknown"))")
                }
            }
            // Keep coverage and comparison context; task intent is represented above.
            var other = facts
            other["desk"] = desk.filter { $0.key != "projects" }
            lines.append("Other context (data): " + Self.json(DisplayPrivacy.redacted(other)))
        } else {
            lines.append("Choose whether this occasion has a useful brief remark under the guide. Silence is valid. A turn end is not verified success; an error does not establish its cause; a return does not establish resumed work.")
            lines.append("Current context (data): " + Self.json(DisplayPrivacy.redacted(facts)))
        }
        lines.append("Return the response for \(occasion), within \(maxBytes) UTF-8 bytes. No advice, questions or unsupported accomplishment claims.")
        input = lines.joined(separator: "\n")
        taskKeys = keys
        emptyScope = isScope && !knownIntent
    }

    static func focusedGuide(_ guide: String, occasion: String) -> String {
        let aliases: Set<String> = ["work_context_changed", "result_observed", "completed", "uhoh_error", "returned", "greet", "reflection", "profileline", "periodic"]
        let active = occasion == "greet" ? Set(["greet", "returned"]) : Set([occasion.lowercased()])
        var keep = true, result: [String] = []
        for line in guide.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3)).lowercased()
                let name = heading.components(separatedBy: " — ")[0]
                let names = Set(name.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) })
                if heading == "private legacy operations" { keep = false }
                else if names.isSubset(of: aliases) { keep = !names.isDisjoint(with: active) }
                else { keep = true }
            }
            if keep { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    private static func quoted(_ value: String) -> String { json(DisplayPrivacy.redacted(value)) }
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
