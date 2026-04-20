import Foundation

private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

enum AgentKind: String, CaseIterable, Identifiable {
    case claudeCode = "claude-code"
    case cursor = "cursor"
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        }
    }

    var configDir: String {
        switch self {
        case .claudeCode: return "\(homeDir)/.claude"
        case .cursor: return "\(homeDir)/.cursor"
        case .codex: return "\(homeDir)/.codex"
        }
    }
}

@MainActor
final class HookInstaller {
    static let shared = HookInstaller()

    private static let stateDir = BuddyConfig.default.stateDir
    private static let hookScriptName = "buddygotchi-hook.sh"

    // MARK: - Claude Code (command hooks — silent when daemon is not running)

    func installClaudeCode() -> Bool {
        let home = homeDir
        let claudeDir = "\(home)/.claude"
        let settingsPath = "\(claudeDir)/settings.json"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        guard installHookScript() else { return false }

        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }

        if containsBuddygotchiNestedHooks(settings["hooks"] as? [String: Any] ?? [:]) { return true }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        hooks = removeLegacyHooks(from: hooks)

        let scriptPath = "\(Self.stateDir)/\(Self.hookScriptName)"
        let cmdHook: [String: Any] = ["type": "command", "command": "\(scriptPath) claude-code", "timeout": 5]

        let plainEvents = [
            "SessionStart", "UserPromptSubmit",
            "Stop", "StopFailure", "SessionEnd",
            "PermissionRequest", "PostToolUse",
            "Elicitation", "ElicitationResult",
        ]
        for event in plainEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.append(["hooks": [cmdHook]])
            hooks[event] = eventHooks
        }

        let notificationMatchers = ["permission_prompt", "idle_prompt", "elicitation_dialog"]
        var notifHooks = hooks["Notification"] as? [[String: Any]] ?? []
        for matcher in notificationMatchers {
            notifHooks.append(["matcher": matcher, "hooks": [cmdHook]])
        }
        hooks["Notification"] = notifHooks

        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        guard fm.createFile(atPath: settingsPath, contents: data) else { return false }
        return true
    }

    func isClaudeCodeInstalled() -> Bool {
        let home = homeDir
        let settingsPath = "\(home)/.claude/settings.json"
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        return containsBuddygotchiNestedHooks(hooks)
    }

    // MARK: - Convenience Dispatchers

    func install(agent: AgentKind) -> Bool {
        switch agent {
        case .claudeCode: return installClaudeCode()
        case .cursor: return installCursor()
        case .codex: return installCodex()
        }
    }

    func isInstalled(agent: AgentKind) -> Bool {
        switch agent {
        case .claudeCode: return isClaudeCodeInstalled()
        case .cursor: return isCursorInstalled()
        case .codex: return isCodexInstalled()
        }
    }

    func uninstall(agent: AgentKind) {
        switch agent {
        case .claudeCode: uninstallClaudeCode()
        case .cursor: uninstallCursor()
        case .codex: uninstallCodex()
        }
    }

    func detectInstalledAgents() -> [AgentKind: Bool] {
        var result: [AgentKind: Bool] = [:]
        let fm = FileManager.default
        for agent in AgentKind.allCases {
            var isDir: ObjCBool = false
            result[agent] = fm.fileExists(atPath: agent.configDir, isDirectory: &isDir) && isDir.boolValue
        }
        return result
    }

    // MARK: - Cursor (direct file install)

    func installCursor() -> Bool {
        let home = homeDir
        let cursorDir = "\(home)/.cursor"
        let hooksPath = "\(cursorDir)/hooks.json"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        guard installHookScript() else { return false }

        var root: [String: Any] = [:]
        if let data = fm.contents(atPath: hooksPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }

        if isBuddygotchiInCursorHooks(root) { return true }

        root = removeBuddygotchiFromCursorHooks(root)
        root["version"] = 1

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let signalPath = signalCLIPath()
        let hookEntry: [String: Any] = ["command": "\(signalPath) --agent cursor"]

        let events = [
            "sessionStart", "sessionEnd", "beforeSubmitPrompt", "stop",
            "beforeShellExecution", "beforeMCPExecution",
            "afterShellExecution", "afterMCPExecution",
        ]
        for event in events {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        root["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        guard fm.createFile(atPath: hooksPath, contents: data) else { return false }

        return true
    }

    func isCursorInstalled() -> Bool {
        let home = homeDir
        let hooksPath = "\(home)/.cursor/hooks.json"
        guard let data = FileManager.default.contents(atPath: hooksPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return isBuddygotchiInCursorHooks(root)
    }

    private func uninstallCursor() {
        let home = homeDir
        let hooksPath = "\(home)/.cursor/hooks.json"
        let fm = FileManager.default
        guard let data = fm.contents(atPath: hooksPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        root = removeBuddygotchiFromCursorHooks(root)
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: hooksPath, contents: data)
        }
    }

    private func isBuddygotchiInCursorHooks(_ root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                if let cmd = entry["command"] as? String, cmd.contains("buddygotchi") || cmd.contains("BuddygotchiSignal") {
                    return true
                }
            }
        }
        return false
    }

    private func removeBuddygotchiFromCursorHooks(_ root: [String: Any]) -> [String: Any] {
        var cleaned = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                if let cmd = entry["command"] as? String {
                    return cmd.contains("buddygotchi") || cmd.contains("BuddygotchiSignal")
                }
                return false
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
        cleaned["hooks"] = hooks
        return cleaned
    }

    // MARK: - Codex (direct file install)

    func installCodex() -> Bool {
        let home = homeDir
        let codexDir = "\(home)/.codex"
        let hooksPath = "\(codexDir)/hooks.json"
        let tomlPath = "\(codexDir)/config.toml"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: codexDir, withIntermediateDirectories: true)
        guard installHookScript() else { return false }

        // Install hooks.json (same nested schema as Claude Code)
        var root: [String: Any] = [:]
        if let data = fm.contents(atPath: hooksPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }

        if !containsBuddygotchiNestedHooks(root["hooks"] as? [String: Any] ?? [:]) {
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            hooks = removeLegacyHooks(from: hooks)

            let scriptPath = "\(Self.stateDir)/\(Self.hookScriptName)"
            let cmdHook: [String: Any] = ["type": "command", "command": "\(scriptPath) codex"]

            let events: [(String, String?)] = [
                ("SessionStart", "startup|resume"),
                ("UserPromptSubmit", nil),
                ("PermissionRequest", nil),
                ("PreToolUse", nil),
                ("PostToolUse", nil),
                ("Stop", nil),
            ]
            for (event, matcher) in events {
                var eventHooks = hooks[event] as? [[String: Any]] ?? []
                var group: [String: Any] = ["hooks": [cmdHook]]
                if let matcher { group["matcher"] = matcher }
                eventHooks.append(group)
                hooks[event] = eventHooks
            }

            root["hooks"] = hooks

            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
                return false
            }
            guard fm.createFile(atPath: hooksPath, contents: data) else { return false }
        }

        // Enable feature flag in config.toml
        var toml = (try? String(contentsOfFile: tomlPath, encoding: .utf8)) ?? ""
        if !toml.contains("codex_hooks = true") {
            if let range = toml.range(of: "[features]") {
                let insertPos = toml[range.upperBound...].firstIndex(of: "\n").map { toml.index(after: $0) } ?? toml.endIndex
                toml.insert(contentsOf: "codex_hooks = true\n", at: insertPos)
            } else {
                if !toml.isEmpty && !toml.hasSuffix("\n") { toml += "\n" }
                toml += "\n[features]\ncodex_hooks = true\n"
            }
            try? toml.write(toFile: tomlPath, atomically: true, encoding: .utf8)
        }


        return true
    }

    func isCodexInstalled() -> Bool {
        let home = homeDir
        let hooksPath = "\(home)/.codex/hooks.json"
        guard let data = FileManager.default.contents(atPath: hooksPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return containsBuddygotchiNestedHooks(root["hooks"] as? [String: Any] ?? [:])
    }

    private func uninstallCodex() {
        let home = homeDir
        let hooksPath = "\(home)/.codex/hooks.json"
        let tomlPath = "\(home)/.codex/config.toml"
        let fm = FileManager.default

        if let data = fm.contents(atPath: hooksPath),
           var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            hooks = removeLegacyHooks(from: hooks)
            root["hooks"] = hooks
            if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
                fm.createFile(atPath: hooksPath, contents: data)
            }
        }

        if var toml = try? String(contentsOfFile: tomlPath, encoding: .utf8) {
            toml = toml.replacingOccurrences(of: "codex_hooks = true\n", with: "")
            toml = toml.replacingOccurrences(of: "codex_hooks = true", with: "")
            try? toml.write(toFile: tomlPath, atomically: true, encoding: .utf8)
        }
    }

    private func containsBuddygotchiNestedHooks(_ hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    for entry in innerHooks {
                        if let cmd = entry["command"] as? String, cmd.contains("buddygotchi") {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func uninstallClaudeCode() {
        let home = homeDir
        let settingsPath = "\(home)/.claude/settings.json"
        let fm = FileManager.default
        guard let data = fm.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks = removeLegacyHooks(from: hooks)
        settings["hooks"] = hooks
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: settingsPath, contents: data)
        }
    }

    // MARK: - Private

    private static let hookScriptContent = """
        #!/bin/bash
        SOURCE="${1:-claude-code}"
        CFG="$HOME/.buddygotchi/config.json"
        PORT=$(grep -o '"port" *: *[0-9]*' "$CFG" 2>/dev/null | grep -o '[0-9]*')
        curl -s -o /dev/null --noproxy '*' \\
          -X POST "http://127.0.0.1:${PORT}/hook/event?source=${SOURCE}&pid=$$" \\
          -H "Content-Type: application/json" \\
          -d "$(cat)" \\
          --connect-timeout 1 2>/dev/null || true
        exit 0
        """

    private func installHookScript() -> Bool {
        let fm = FileManager.default
        let destDir = Self.stateDir
        let destPath = "\(destDir)/\(Self.hookScriptName)"

        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        do {
            try Self.hookScriptContent.write(toFile: destPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            return true
        } catch {
            return false
        }
    }

    private func signalCLIPath() -> String {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("BuddygotchiSignal").path
            ?? "buddygotchi-signal"
    }

    private func removeLegacyHooks(from hooks: [String: Any]) -> [String: Any] {
        var cleaned = hooks
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { group in
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    return innerHooks.contains { entry in
                        if let cmd = entry["command"] as? String {
                            return cmd.contains("BuddygotchiHook") || cmd.contains("BuddygotchiSignal") || cmd.contains("buddygotchi")
                        }
                        if let url = entry["url"] as? String {
                            return url.contains("/claude-code/event")
                        }
                        return false
                    }
                }
                if let cmd = group["command"] as? String {
                    return cmd.contains("buddygotchi")
                }
                return false
            }
            if groups.isEmpty {
                cleaned.removeValue(forKey: event)
            } else {
                cleaned[event] = groups
            }
        }
        return cleaned
    }
}
