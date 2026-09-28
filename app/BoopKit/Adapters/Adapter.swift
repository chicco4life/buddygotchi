import Foundation
import HookWire

/// Turns a hook line from `boop-hook` into a raw event (ADAPTERS.md §3):
/// its generic type and phase, the hook's own name as `specific_type`,
/// and the type's `data`. Everything agent-specific lives here.
public enum Adapter {
    /// A hook's generic type and phase.
    public typealias Mapping = (type: Event.Kind, phase: Event.Phase?)

    /// Claude Code's hooks and what each becomes. `Notification` and an
    /// interrupted `PostToolUseFailure` depend on what they carry
    /// (`mapping(_:)`).
    static let claude: [String: Mapping] = [
        "SessionStart": (.session, .start),
        "UserPromptSubmit": (.turn, .start),
        "PreToolUse": (.tool, .start),
        "PostToolUse": (.tool, .end),
        "PostToolUseFailure": (.tool, .end),
        "PermissionRequest": (.tool, .wait),
        "Elicitation": (.tool, .wait),
        "ElicitationResult": (.tool, .end),
        "Stop": (.turn, .end),
        "StopFailure": (.turn, .end),
        "SubagentStop": (.subagent, .end),
        "SessionEnd": (.session, .end),
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
    static let codex: [String: Mapping] = [
        "SessionStart": (.session, .start),
        "UserPromptSubmit": (.turn, .start),
        "PreToolUse": (.tool, .start),
        "PostToolUse": (.tool, .end),
        "PermissionRequest": (.tool, .wait),
        "Stop": (.turn, .end),
        "Interrupt": (.turn, .end),
        "SessionEnd": (.session, .end),
    ]

    /// What a hook line becomes, or nil for one Boop ignores.
    public static func mapping(_ line: HookLine) -> Mapping? {
        guard let agent = Agent(hookName: line.agent) else { return nil }
        switch agent {
        case .claudeCode:
            if line.hook == "Notification" {
                if line.kind.map(askingNotifications.contains) == true { return (.tool, .wait) }
                return line.kind == idleNotification ? (.turn, .end) : nil
            }
            // Esc: Claude sends no `Stop` for a turn you interrupt.
            if line.interrupt { return (.turn, .end) }
            return claude[line.hook]
        case .codex:
            return codex[line.hook]
        }
    }

    /// The raw event for a hook line, or nil for hooks Boop ignores. `ts`
    /// is when the app received it, or the line's own time.
    public static func event(from line: HookLine, receivedAt: Int64? = nil) -> Event? {
        guard let agent = Agent(hookName: line.agent), let (type, phase) = mapping(line) else { return nil }
        // A subagent's end says which subagent by its `agent_id`; one without
        // it can't answer anyone's request, and mustn't pass for the main agent.
        if type == .subagent && line.agentID == nil { return nil }
        let claude = agent == .claudeCode
        var data: [String: JSONValue] = [:]
        func put(_ key: String, _ value: String?) { if let value { data[key] = .string(value) } }
        if claude { put("agent_type", line.agentType) }
        switch (type, phase) {
        case (.turn, .start?):
            put("prompt", line.prompt)
        case (.tool, .start?):
            put("tool", line.tool)
            put("tool_use_id", line.toolUseID)
            put("topic", line.topic)
        case (.tool, .wait?):
            put("tool", line.tool)
            put("tool_use_id", line.toolUseID)
            let kind = line.hook == "Notification" ? line.kind : nil
            put("notice", kind)
            let forInput = line.hook == "Elicitation" || kind == "elicitation_dialog"
            data["for"] = .string(forInput ? "input" : "permission")
            put("name", line.name)
        case (.tool, .end?):
            put("tool", line.tool)
            put("tool_use_id", line.toolUseID)
            put("topic", line.topic)
            if claude && line.tool != nil {
                // Claude says whether a call failed; Codex doesn't.
                let failed = line.hook == "PostToolUseFailure"
                data["failed"] = .bool(failed)
                if failed { data["error"] = .string(line.toolError ?? "other") }
            }
        case (.turn, .end?):
            if line.hook == "StopFailure" {
                data["outcome"] = "failed"
                put("error", line.error.map(errorClass))
            } else if line.hook == "Stop" {
                data["outcome"] = "done"
                put("message", line.message)
            } else {
                // Esc, Codex's `Interrupt` or Claude's idle notice: over
                // without finishing.
                data["outcome"] = "stopped"
                put("tool", line.tool)  // an interrupted call; the idle notice has none
                put("notice", line.hook == "Notification" ? line.kind : nil)
            }
        default:
            break
        }
        return Event(ts: receivedAt ?? line.ts, source: Event.source(agent), type: type, phase: phase,
                     specificType: line.hook, session: line.session, subagent: claude ? line.agentID : nil,
                     cwd: line.cwd, data: data)
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
