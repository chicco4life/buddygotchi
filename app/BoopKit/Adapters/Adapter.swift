import Foundation
import HookWire

/// Turns a hook line from `boop-hook` into the common event
/// (ADAPTERS.md §3). Everything agent-specific lives here.
public enum Adapter {
    /// Claude Code's hooks and what each becomes.
    static let claude: [String: BoopEvent.Kind] = [
        "SessionStart": .sessionStart,
        "UserPromptSubmit": .turnStart,
        "PreToolUse": .activity,
        "PostToolUse": .activity,
        "PostToolUseFailure": .activity,
        "PermissionRequest": .needsYou,
        "Elicitation": .needsYou,
        "ElicitationResult": .activity,
        "Stop": .turnEnd,
        "StopFailure": .turnFailed,
        "SessionEnd": .sessionEnd,
    ]

    /// Claude's `Notification` types that mean a person is being asked.
    static let askingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]
    /// Claude's `Notification` type for sitting at its prompt for a minute:
    /// whatever turn there was is over, even one that ended without `Stop`.
    static let idleNotification = "idle_prompt"

    /// Codex's hooks. Codex has no failure hook.
    static let codex: [String: BoopEvent.Kind] = [
        "SessionStart": .sessionStart,
        "UserPromptSubmit": .turnStart,
        "PreToolUse": .activity,
        "PostToolUse": .activity,
        "PermissionRequest": .needsYou,
        "Stop": .turnEnd,
        "SessionEnd": .sessionEnd,
    ]

    /// The common event for a hook line, or nil for hooks Boop ignores.
    /// `project` names the line's `cwd`; a line without one is `unknown`,
    /// and the core keeps the session's project.
    public static func event(from line: HookLine, receivedAt: Int64? = nil,
                             project: (String) -> String = { projectName(cwd: $0) }) -> BoopEvent? {
        guard let agent = Agent(hookName: line.agent) else { return nil }
        let kind: BoopEvent.Kind?
        switch agent {
        case .claudeCode:
            if line.hook == "Notification" {
                kind = line.kind.map(askingNotifications.contains) == true ? .needsYou
                    : line.kind == idleNotification ? .turnStopped : nil
            } else if line.interrupt {
                // Esc: Claude sends no `Stop` for a turn you interrupt.
                kind = .turnStopped
            } else {
                kind = claude[line.hook]
            }
        case .codex:
            kind = codex[line.hook]
        }
        guard let kind else { return nil }

        var detail = BoopEvent.Detail()
        switch kind {
        case .activity, .needsYou:
            detail.tool = line.tool
            detail.topic = kind == .activity ? line.topic : nil
            if agent == .claudeCode && !line.interrupt {
                switch line.hook {
                case "PostToolUse": detail.failed = false
                case "PostToolUseFailure": detail.failed = true
                default: break
                }
            }
        case .turnFailed:
            detail.error = line.error.map(errorClass)
        case .turnStopped:
            detail.tool = line.tool  // an interrupted call; Claude's idle notice has none
        default:
            break
        }
        return BoopEvent(agent: agent, session: line.session, subagent: agent == .claudeCode ? line.agentID : nil,
                         project: line.cwd.map(project) ?? "unknown", event: kind, detail: detail,
                         ts: receivedAt ?? line.ts)
    }

    /// A short, fixed error class; anything unfamiliar becomes `other`.
    static func errorClass(_ raw: String) -> String {
        let known = ["rate_limit", "overloaded", "api_error", "auth", "timeout", "network", "context_limit", "billing"]
        let lowered = raw.lowercased()
        return known.first { lowered.contains($0) } ?? "other"
    }

    /// Project names by working directory, so a worktree's `.git` is read
    /// once per folder rather than on every hook. Touch it from one queue.
    public final class ProjectNames {
        var names: [String: String] = [:]
        /// Folders remembered before the cache starts again.
        static let limit = 512

        public init() {}

        public func name(cwd: String) -> String {
            if let name = names[cwd] { return name }
            if names.count >= Self.limit { names.removeAll() }
            let name = Adapter.projectName(cwd: cwd)
            names[cwd] = name
            return name
        }
    }

    /// The last folder of `cwd`. A git worktree maps to its main repository's
    /// name, so `landing` and `landing/.worktrees/fix-nav` both give `landing`.
    public static func projectName(cwd: String, fileManager: FileManager = .default) -> String {
        var path = cwd
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty, path != "/" else { return "unknown" }

        // A linked worktree's `.git` is a file: `gitdir: <repo>/.git/worktrees/<name>`.
        let gitFile = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: gitFile, isDirectory: &isDirectory), !isDirectory.boolValue,
           let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
           let range = text.range(of: "/.git/worktrees/") {
            let prefix = text[..<range.lowerBound]
            let repo = prefix.hasPrefix("gitdir:") ? prefix.dropFirst("gitdir:".count) : prefix
            let name = (repo.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }

        // Common worktree folders, even when the folder itself isn't readable:
        // `<repo>/.worktrees/<name>` and `<repo>/.<tool>/worktrees/<name>`.
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 3 {
            let parent = parts[parts.count - 2]
            if parent == ".worktrees" { return parts[parts.count - 3] }
            if parent == "worktrees", parts.count >= 4, parts[parts.count - 3].hasPrefix(".") {
                return parts[parts.count - 4]
            }
        }
        return parts.last ?? "unknown"
    }
}
