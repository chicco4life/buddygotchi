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
        "SubagentStop": .subagentEnd,
        "SessionEnd": .sessionEnd,
    ]

    /// Claude's `Notification` types that mean a person is being asked.
    static let askingNotifications = ["permission_prompt", "elicitation_dialog"]
    /// Claude's `Notification` type for sitting at its prompt for a minute:
    /// whatever turn there was is over, even one that ended without `Stop`.
    static let idleNotification = "idle_prompt"
    /// Every `Notification` type mapped, in the order the installer's
    /// matcher lists them (ADAPTERS.md §5): Claude runs the hook for no
    /// other. A new order would make every install look outdated.
    static let notificationTypes = askingNotifications + [idleNotification]

    /// Codex's hooks. Codex has no failure hook; `Interrupt` is you
    /// pressing Esc.
    static let codex: [String: BoopEvent.Kind] = [
        "SessionStart": .sessionStart,
        "UserPromptSubmit": .turnStart,
        "PreToolUse": .activity,
        "PostToolUse": .activity,
        "PermissionRequest": .needsYou,
        "Stop": .turnEnd,
        "Interrupt": .turnStopped,
        "SessionEnd": .sessionEnd,
    ]

    /// The common event for a hook line, or nil for hooks Boop ignores.
    /// `place` names the line's `cwd`: its project and workspace. A line
    /// without one is `unknown`, and the core keeps the session's.
    public static func event(from line: HookLine, receivedAt: Int64? = nil,
                             place: (String) -> Place = { place(cwd: $0) }) -> BoopEvent? {
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
        // A subagent's end says which subagent by its `agent_id`; one without
        // it can't answer anyone's request, and mustn't pass for the main agent.
        if kind == .subagentEnd && line.agentID == nil { return nil }

        var detail = BoopEvent.Detail()
        switch kind {
        case .activity, .needsYou:
            detail.tool = line.tool
            detail.toolUseID = line.toolUseID
            detail.topic = kind == .activity ? line.topic : nil
            detail.done = kind == .activity && (line.hook == "PostToolUse" || line.hook == "PostToolUseFailure")
            if agent == .claudeCode && !line.interrupt {
                switch line.hook {
                case "PostToolUse": detail.failed = false
                case "PostToolUseFailure":
                    detail.failed = true
                    detail.toolError = line.toolError ?? "other"
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
        let where_ = line.cwd.map(place)
        return BoopEvent(agent: agent, session: line.session, subagent: agent == .claudeCode ? line.agentID : nil,
                         subagentType: agent == .claudeCode ? line.agentType : nil,
                         project: where_?.project ?? "unknown", workspace: where_?.workspace, event: kind,
                         detail: detail, ts: receivedAt ?? line.ts)
    }

    /// Claude's `StopFailure` errors that don't name their class.
    static let claudeErrors = [
        "server_error": "api_error", "invalid_request": "api_error", "model_not_found": "api_error",
        "max_output_tokens": "context_limit",
        "account_on_hold": "auth", "verification_required": "auth", "cloud_credential_error": "auth",
    ]

    /// A short, fixed error class (ADAPTERS.md §2); anything unfamiliar
    /// becomes `other`.
    static func errorClass(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if let known = claudeErrors[lowered] { return known }
        let classes = ["rate_limit", "overloaded", "api_error", "auth", "timeout", "network", "context_limit", "billing"]
        return classes.first { lowered.contains($0) } ?? "other"
    }

    /// Where a session works: its project, and the workspace that tells two
    /// threads in one project apart.
    public struct Place: Equatable, Sendable {
        public var project: String
        public var workspace: String?
        public init(project: String, workspace: String? = nil) {
            self.project = project
            self.workspace = workspace
        }
    }

    /// Places by working directory, so a folder's `.git` is read once per
    /// folder rather than on every hook. Touch it from one queue.
    public final class Places {
        var places: [String: Place] = [:]
        /// Folders remembered before the cache starts again.
        static let limit = 512

        public init() {}

        public func place(cwd: String) -> Place {
            if let place = places[cwd] { return place }
            if places.count >= Self.limit { places.removeAll() }
            let place = Adapter.place(cwd: cwd)
            places[cwd] = place
            return place
        }
    }

    /// Where `cwd` works (harness/EVENTS.md §3), from one look at its
    /// `.git`. The project is the last folder, except that a git worktree
    /// maps to its main repository's name, so `landing` and
    /// `landing/.worktrees/fix-nav` both give `landing`. The workspace is a
    /// linked worktree's folder name, else the checked-out branch, else nil
    /// (the default branch, a detached head, or no git), cleaned by
    /// `cleanWorkspace`.
    public static func place(cwd: String) -> Place {
        var path = cwd
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty, path != "/" else { return Place(project: "unknown") }

        // Common worktree folders, even when the folder itself isn't readable:
        // `<repo>/.worktrees/<name>` and `<repo>/.<tool>/worktrees/<name>`.
        let parts = path.split(separator: "/").map(String.init)
        let parent = parts.count >= 3 ? parts[parts.count - 2] : nil
        var project = parts.last ?? "unknown"
        if parent == ".worktrees" {
            project = parts[parts.count - 3]
        } else if parent == "worktrees", parts.count >= 4, parts[parts.count - 3].hasPrefix(".") {
            project = parts[parts.count - 4]
        }

        let git = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory) else {
            // A common worktree folder that can't be read still names itself.
            let named = parent == ".worktrees" || parent == "worktrees"
            return Place(project: project, workspace: named ? cleanWorkspace(parts[parts.count - 1]) : nil)
        }
        if !isDirectory.boolValue {
            // A linked worktree: `gitdir: <repo>/.git/worktrees/<name>`.
            guard let text = try? String(contentsOfFile: git, encoding: .utf8),
                  let range = text.range(of: "/.git/worktrees/") else { return Place(project: project) }
            let prefix = text[..<range.lowerBound]
            let repo = prefix.hasPrefix("gitdir:") ? prefix.dropFirst("gitdir:".count) : prefix
            let name = (repo.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
            return Place(project: name.isEmpty ? project : name,
                         workspace: cleanWorkspace(text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let prefix = "ref: refs/heads/"
        guard let head = try? String(contentsOfFile: (git as NSString).appendingPathComponent("HEAD"), encoding: .utf8),
              head.hasPrefix(prefix)
        else { return Place(project: project) }
        let branch = head.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return Place(project: project, workspace: defaultBranches.contains(branch) ? nil : cleanWorkspace(branch))
    }

    static let defaultBranches: Set<String> = ["main", "master", "trunk", "develop"]

    /// An agent chooses its branch names, so a workspace is cleaned before
    /// anything sees it: a leading `word/` and a trailing hash (`-7a22ea`)
    /// go, it's lowercased, only `a-z`, `0-9` and `-` stay, and it's cut to
    /// 40 characters. Nothing left is nil.
    public static func cleanWorkspace(_ raw: String) -> String? {
        var name = raw.lowercased()
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if let range = name.range(of: "-[0-9a-f]{6,}$", options: .regularExpression) { name.removeSubrange(range) }
        name = String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        name = String(name.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return name.isEmpty ? nil : name
    }
}
