import Foundation

private let defaultHomeDir = FileManager.default.homeDirectoryForCurrentUser.path

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
}

enum HookHealthReason {
    static let settingsNotJSON = "settings.json is not valid JSON"
    static let hooksNotJSON = "hooks.json is not valid JSON"
    static let configNotJSON = "config.json is not valid JSON"
    static let hookScriptNotReadable = "hook script not readable"

    static let nonRepairableReasons: Set<String> = [
        settingsNotJSON,
        hooksNotJSON,
        hookScriptNotReadable,
    ]
}

enum HookHealth: Equatable {
    case notInstalled
    case installed
    case outdated(installed: Int, current: Int)
    case corrupted(reason: String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var repairable: Bool {
        switch self {
        case .outdated:
            return true
        case .corrupted(let reason):
            return !HookHealthReason.nonRepairableReasons.contains(reason)
        case .notInstalled, .installed:
            return false
        }
    }
}

enum UninstallOutcome: Equatable {
    case removed
    case nothingInstalled
    case failed(reason: String)
}

enum HookInstallError: Error, LocalizedError {
    case cantWriteScript(path: String)
    case cantWriteConfig(path: String)
    case cantWriteHelper(path: String)
    case configUnreadable(agent: AgentKind, path: String)
    case helperMissing(path: String)
    case serializationFailed(agent: AgentKind)

    var errorDescription: String? {
        switch self {
        case .cantWriteScript(let path):
            return "Could not write the hook script at \(path)."
        case .cantWriteConfig(let path):
            return "Could not write \(path)."
        case .cantWriteHelper(let path):
            return "Could not install the Cursor helper at \(path)."
        case .configUnreadable(let agent, let path):
            return "\(agent.displayName) config is not valid JSON: \(path)."
        case .helperMissing(let path):
            return "BoopSignal was not found at \(path)."
        case .serializationFailed(let agent):
            return "Could not serialize \(agent.displayName) hook configuration."
        }
    }
}

@MainActor
final class HookInstaller {
    static let shared = HookInstaller()

    static let hookSchemaVersion = 4

    private static let hookScriptName = "boop-hook.sh"

    private let homeDir: String
    private let stateDir: String
    private let bundledSignalURL: URL?
    private let fm: FileManager
    private let userDefaults: UserDefaults

    init(
        homeDir: String = defaultHomeDir,
        stateDir: String = BuddyConfig.default.stateDir,
        bundledSignalURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.homeDir = homeDir
        self.stateDir = stateDir
        self.bundledSignalURL = bundledSignalURL
        self.fm = fileManager
        self.userDefaults = userDefaults
    }

    // MARK: - Public API

    func installClaudeCode() -> Bool {
        install(agent: .claudeCode)
    }

    func isClaudeCodeInstalled() -> Bool {
        isInstalled(agent: .claudeCode)
    }

    func installCursor() -> Bool {
        install(agent: .cursor)
    }

    func isCursorInstalled() -> Bool {
        isInstalled(agent: .cursor)
    }

    func installCodex() -> Bool {
        install(agent: .codex)
    }

    func isCodexInstalled() -> Bool {
        isInstalled(agent: .codex)
    }

    func install(agent: AgentKind) -> Bool {
        do {
            try installOrThrow(agent: agent)
            rememberInstalled(agent)
            return true
        } catch {
            return false
        }
    }

    func installOrThrow(agent: AgentKind) throws {
        try createStateDirectories()
        try installHookScript()
        if agent == .cursor {
            try installManagedSignal()
        }

        switch agent {
        case .claudeCode:
            try installClaudeCodeOrThrow()
        case .cursor:
            try installCursorOrThrow()
        case .codex:
            try installCodexOrThrow()
        }
        rememberInstalled(agent)
    }

    func isInstalled(agent: AgentKind) -> Bool {
        verify(agent: agent).isInstalled
    }

    func verify(agent: AgentKind) -> HookHealth {
        let agentHealth: HookHealth
        switch agent {
        case .claudeCode:
            agentHealth = verifyClaudeCode()
        case .cursor:
            agentHealth = verifyCursor()
        case .codex:
            agentHealth = verifyCodex()
        }

        guard agentHealth == .installed else { return agentHealth }
        return verifyCommon(agent: agent)
    }

    func repair(agent: AgentKind) throws {
        uninstall(agent: agent)
        try installOrThrow(agent: agent)
    }

    @discardableResult
    func uninstall(agent: AgentKind) -> UninstallOutcome {
        let outcome: UninstallOutcome = switch agent {
        case .claudeCode: uninstallClaudeCode()
        case .cursor: uninstallCursor()
        case .codex: uninstallCodex()
        }
        if case .failed = outcome {
            return outcome
        }
        forgetInstalled(agent)
        return outcome
    }

    func detectInstalledAgents() -> [AgentKind: Bool] {
        var result: [AgentKind: Bool] = [:]
        for agent in AgentKind.allCases {
            var isDir: ObjCBool = false
            result[agent] = fm.fileExists(atPath: configDir(for: agent).path, isDirectory: &isDir) && isDir.boolValue
        }
        return result
    }

    func previouslyInstalledAgents() -> [AgentKind] {
        let stored = userDefaults.stringArray(forKey: DefaultsKey.installedAgents) ?? []
        return stored.compactMap(AgentKind.init(rawValue:))
    }

    // MARK: - Installers

    private func installClaudeCodeOrThrow() throws {
        let claudeDir = configDir(for: .claudeCode)
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        var settings = try readJSONObject(at: settingsURL, agent: .claudeCode)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks = removeLegacyHooks(from: hooks)

        let cmdHook = commandHook(command: scriptCommand(for: .claudeCode), timeout: 5)
        let approvalHook = commandHook(command: scriptCommand(for: .claudeCode), timeout: 310)

        for event in Self.claudePlainEvents {
            hooks[event] = addingNestedHook(to: hooks[event], matcher: nil, hook: cmdHook)
        }
        hooks["PermissionRequest"] = addingNestedHook(to: hooks["PermissionRequest"], matcher: nil, hook: approvalHook)
        for matcher in Self.claudeNotificationMatchers {
            hooks["Notification"] = addingNestedHook(to: hooks["Notification"], matcher: matcher, hook: cmdHook)
        }

        settings["hooks"] = hooks
        try writeJSONObject(settings, to: settingsURL, agent: .claudeCode)
    }

    private func installCursorOrThrow() throws {
        let cursorDir = configDir(for: .cursor)
        let hooksURL = cursorDir.appendingPathComponent("hooks.json")
        try fm.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        var root = try readJSONObject(at: hooksURL, agent: .cursor)
        root = removeBoopFromCursorHooks(root)
        root["version"] = 1

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let hookEntry: [String: Any] = ["command": cursorCommand()]
        for event in Self.cursorEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }
        root["hooks"] = hooks

        try writeJSONObject(root, to: hooksURL, agent: .cursor)
    }

    private func installCodexOrThrow() throws {
        let codexDir = configDir(for: .codex)
        let hooksURL = codexDir.appendingPathComponent("hooks.json")
        let tomlURL = codexDir.appendingPathComponent("config.toml")
        try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)

        var root = try readJSONObject(at: hooksURL, agent: .codex)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removeLegacyHooks(from: hooks)

        let cmdHook = commandHook(command: scriptCommand(for: .codex), timeout: 5)
        let approvalHook = commandHook(command: scriptCommand(for: .codex), timeout: 310)
        for spec in Self.codexEvents {
            hooks[spec.event] = addingNestedHook(
                to: hooks[spec.event],
                matcher: spec.matcher,
                hook: spec.isApproval ? approvalHook : cmdHook
            )
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksURL, agent: .codex)

        let toml = (try? String(contentsOf: tomlURL, encoding: .utf8)) ?? ""
        if !codexHooksEnabled(in: toml) {
            try writeString(Self.enablingCodexHooks(in: toml), to: tomlURL, agent: .codex)
            userDefaults.set(true, forKey: Self.codexHooksAddedKey)
        }
    }

    /// Marks that WE turned `codex_hooks` on, so uninstall only takes it back
    /// out if the user hadn't set it themselves.
    static let codexHooksAddedKey = "codexHooksAddedByBoop"

    /// Return `toml` with our `codex_hooks` line removed, leaving the rest of
    /// the file (including an empty `[features]` table) untouched.
    nonisolated static func removingCodexHooks(from toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        var inFeatures = false
        lines.removeAll { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { return false }
            if t.hasPrefix("[") && t.hasSuffix("]") {
                inFeatures = (t == "[features]")
                return false
            }
            guard inFeatures, let (key, value) = tomlKeyValue(t) else { return false }
            return key == "codex_hooks" && value == "true"
        }
        return lines.joined(separator: "\n")
    }

    /// Return `toml` with `codex_hooks = true` added under `[features]`.
    ///
    /// Line-based on purpose. The old version searched for the substring
    /// "[features]" and inserted after the next newline, which broke two ways:
    /// a file ENDING in `[features]` with no trailing newline produced
    /// `[features]codex_hooks = true` on one line (invalid TOML), and a
    /// comment merely mentioning `[features]` hijacked the insertion point so
    /// the key landed in whatever table happened to precede it.
    nonisolated static func enablingCodexHooks(in toml: String) -> String {
        var lines = toml.isEmpty ? [] : toml.components(separatedBy: "\n")
        // A real table header, not a mention inside a comment or a string.
        let headerIndex = lines.firstIndex { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t == "[features]"
        }
        if let i = headerIndex {
            lines.insert("codex_hooks = true", at: i + 1)
            return lines.joined(separator: "\n")
        }
        var out = toml
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty { out += "\n" }
        out += "[features]\ncodex_hooks = true\n"
        return out
    }

    // MARK: - Verification

    private func verifyClaudeCode() -> HookHealth {
        let settingsURL = configDir(for: .claudeCode).appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: settingsURL.path) else { return .notInstalled }
        let root: [String: Any]
        do {
            root = try readJSONObject(at: settingsURL, agent: .claudeCode)
        } catch {
            return .corrupted(reason: HookHealthReason.settingsNotJSON)
        }
        guard let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        if !containsBoopNestedHooks(hooks) { return .notInstalled }

        for event in Self.claudePlainEvents {
            if let health = verifyNestedHook(event: event, matcher: nil, hooks: hooks, command: scriptCommand(for: .claudeCode)) {
                return health
            }
        }
        if let health = verifyNestedHook(event: "PermissionRequest", matcher: nil, hooks: hooks, command: scriptCommand(for: .claudeCode)) {
            return health
        }
        for matcher in Self.claudeNotificationMatchers {
            if let health = verifyNestedHook(event: "Notification", matcher: matcher, hooks: hooks, command: scriptCommand(for: .claudeCode)) {
                return health
            }
        }
        return .installed
    }

    private func verifyCursor() -> HookHealth {
        let hooksURL = configDir(for: .cursor).appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath: hooksURL.path) else { return .notInstalled }
        let root: [String: Any]
        do {
            root = try readJSONObject(at: hooksURL, agent: .cursor)
        } catch {
            return .corrupted(reason: HookHealthReason.hooksNotJSON)
        }
        guard let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        if !isBoopInCursorHooks(root) { return .notInstalled }

        for event in Self.cursorEvents {
            guard let entries = hooks[event] as? [[String: Any]] else {
                return .corrupted(reason: "missing hooks: \(event)")
            }
            let buddyEntries = entries.filter { entry in
                (entry["command"] as? String).map(isBuddyCommand(_:)) ?? false
            }
            if buddyEntries.isEmpty { return .corrupted(reason: "missing hooks: \(event)") }
            if buddyEntries.count > 1 { return .corrupted(reason: "duplicate hooks") }
            if buddyEntries.first?["command"] as? String != cursorCommand() {
                return .corrupted(reason: "Cursor hook command is not managed")
            }
        }

        guard isExecutable(managedSignalURL()) else {
            return .corrupted(reason: "Cursor helper binary missing")
        }
        return .installed
    }

    private func verifyCodex() -> HookHealth {
        let codexDir = configDir(for: .codex)
        let hooksURL = codexDir.appendingPathComponent("hooks.json")
        let tomlURL = codexDir.appendingPathComponent("config.toml")
        guard fm.fileExists(atPath: hooksURL.path) else { return .notInstalled }
        let root: [String: Any]
        do {
            root = try readJSONObject(at: hooksURL, agent: .codex)
        } catch {
            return .corrupted(reason: HookHealthReason.hooksNotJSON)
        }
        guard let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        if !containsBoopNestedHooks(hooks) { return .notInstalled }

        for spec in Self.codexEvents {
            if let health = verifyNestedHook(event: spec.event, matcher: spec.matcher, hooks: hooks, command: scriptCommand(for: .codex)) {
                return health
            }
        }

        let toml = (try? String(contentsOf: tomlURL, encoding: .utf8)) ?? ""
        guard codexHooksEnabled(in: toml) else {
            return .corrupted(reason: "codex_hooks is not enabled")
        }
        return .installed
    }

    private func verifyCommon(agent: AgentKind) -> HookHealth {
        let configURL = URL(fileURLWithPath: stateDir).appendingPathComponent("config.json")
        guard fm.fileExists(atPath: configURL.path),
              let data = fm.contents(atPath: configURL.path),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return .corrupted(reason: HookHealthReason.configNotJSON)
        }

        let scriptURL = hookScriptURL()
        guard fm.fileExists(atPath: scriptURL.path) else {
            return .corrupted(reason: "hook script missing")
        }
        guard isExecutable(scriptURL) else {
            return .corrupted(reason: "hook script is not executable")
        }
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return .corrupted(reason: HookHealthReason.hookScriptNotReadable)
        }
        if script != Self.hookScriptContent {
            if let installed = hookSchemaVersion(in: script), installed < Self.hookSchemaVersion {
                return .outdated(installed: installed, current: Self.hookSchemaVersion)
            }
            return .corrupted(reason: "hook script does not match Boop")
        }
        if agent == .cursor, !isExecutable(managedSignalURL()) {
            return .corrupted(reason: "Cursor helper binary missing")
        }
        return .installed
    }

    private func verifyNestedHook(event: String, matcher: String?, hooks: [String: Any], command: String) -> HookHealth? {
        guard let groups = hooks[event] as? [[String: Any]] else {
            return .corrupted(reason: "missing hooks: \(event)")
        }
        let matchingGroups = groups.filter { group in
            if let matcher {
                return group["matcher"] as? String == matcher
            }
            return group["matcher"] == nil
        }

        var buddyCommands: [String] = []
        for group in matchingGroups {
            guard let innerHooks = group["hooks"] as? [[String: Any]] else { continue }
            for entry in innerHooks {
                if let cmd = entry["command"] as? String, isBuddyCommand(cmd) {
                    buddyCommands.append(cmd)
                }
            }
        }
        if buddyCommands.isEmpty {
            return .corrupted(reason: "missing hooks: \(event)")
        }
        if buddyCommands.count > 1 {
            return .corrupted(reason: "duplicate hooks")
        }
        if buddyCommands[0] != command {
            return .corrupted(reason: "hook command is not managed")
        }
        return nil
    }

    // MARK: - Uninstall

    private func uninstallClaudeCode() -> UninstallOutcome {
        let settingsURL = configDir(for: .claudeCode).appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: settingsURL.path) else { return .nothingInstalled }
        guard let data = fm.contents(atPath: settingsURL.path),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(reason: uninstallJSONFailureReason(path: settingsURL.path))
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hadBuddyHooks = containsBoopNestedHooks(hooks)
        hooks = removeLegacyHooks(from: hooks)
        settings["hooks"] = hooks
        do {
            try writeJSONObject(settings, to: settingsURL, agent: .claudeCode)
        } catch {
            return .failed(reason: "Could not write \(settingsURL.path) after removing Boop entries")
        }
        return hadBuddyHooks ? .removed : .nothingInstalled
    }

    private func uninstallCursor() -> UninstallOutcome {
        let hooksURL = configDir(for: .cursor).appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath: hooksURL.path) else { return .nothingInstalled }
        guard let data = fm.contents(atPath: hooksURL.path),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(reason: uninstallJSONFailureReason(path: hooksURL.path))
        }
        let hadBuddyHooks = isBoopInCursorHooks(root)
        root = removeBoopFromCursorHooks(root)
        do {
            try writeJSONObject(root, to: hooksURL, agent: .cursor)
        } catch {
            return .failed(reason: "Could not write \(hooksURL.path) after removing Boop entries")
        }
        return hadBuddyHooks ? .removed : .nothingInstalled
    }

    private func uninstallCodex() -> UninstallOutcome {
        let codexDir = configDir(for: .codex)
        let hooksURL = codexDir.appendingPathComponent("hooks.json")
        let tomlURL = codexDir.appendingPathComponent("config.toml")
        var removedSomething = false

        if fm.fileExists(atPath: hooksURL.path) {
            guard let data = fm.contents(atPath: hooksURL.path),
                  var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed(reason: uninstallJSONFailureReason(path: hooksURL.path))
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            removedSomething = containsBoopNestedHooks(hooks)
            hooks = removeLegacyHooks(from: hooks)
            root["hooks"] = hooks
            do {
                try writeJSONObject(root, to: hooksURL, agent: .codex)
            } catch {
                return .failed(reason: "Could not write \(hooksURL.path) after removing Boop entries")
            }
        }

        // Only take `codex_hooks` back out if we were the ones who set it.
        // Install deliberately skips writing the key when it's already on, so
        // stripping it unconditionally meant uninstalling Boop switched off a
        // feature the user had enabled for their own hooks.
        if userDefaults.bool(forKey: Self.codexHooksAddedKey),
           let toml = try? String(contentsOf: tomlURL, encoding: .utf8) {
            let stripped = Self.removingCodexHooks(from: toml)
            if stripped != toml {
                removedSomething = true
                do {
                    try writeString(stripped, to: tomlURL, agent: .codex)
                } catch {
                    return .failed(reason: "Could not write \(tomlURL.path) after removing Boop entries")
                }
            }
            userDefaults.removeObject(forKey: Self.codexHooksAddedKey)
        }

        return removedSomething ? .removed : .nothingInstalled
    }

    // MARK: - Script and helper

    private static let hookScriptContent = """
        #!/bin/bash
        # boop-hook v\(hookSchemaVersion) - managed by Boop.app; edits are overwritten on repair
        SOURCE="${1:-claude-code}"
        CFG="$HOME/.boop/config.json"
        PORT=$(grep -o '"port" *: *[0-9]*' "$CFG" 2>/dev/null | head -1 | grep -o '[0-9]*')
        TOKEN=$(grep -o '"token" *: *"[^"]*"' "$CFG" 2>/dev/null | head -1 | sed 's/.*"token" *: *"//; s/".*//')
        APPROVAL=$(grep -o '"approvalMode" *: *true' "$CFG" 2>/dev/null)
        # Always drain stdin, even when we're about to bail. The agent is
        # already writing the payload; exiting first hands it EPIPE/SIGPIPE
        # instead of a clean read.
        BODY="$(cat)"
        [ -z "$PORT" ] && exit 0
        [ -z "$TOKEN" ] && exit 0
        EVENT=$(echo "$BODY" | grep -o '"hook_event_name" *: *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
        if [ -n "$APPROVAL" ] && [ "$EVENT" = "PermissionRequest" ]; then
            RESPONSE=$(curl -s --noproxy '*' \\
                -X POST "http://127.0.0.1:${PORT}/hook/approve?source=${SOURCE}&pid=$$" \\
                -H "Content-Type: application/json" \\
                -H "X-Boop-Token: ${TOKEN}" \\
                -d "$BODY" \\
                --connect-timeout 2 \\
                --max-time 300 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
                echo "$RESPONSE"
            fi
            exit 0
        fi
        curl -s -o /dev/null --noproxy '*' \\
          -X POST "http://127.0.0.1:${PORT}/hook/event?source=${SOURCE}&pid=$$" \\
          -H "Content-Type: application/json" \\
          -H "X-Boop-Token: ${TOKEN}" \\
          -d "$BODY" \\
          --connect-timeout 1 \\
          --max-time 5 2>/dev/null || true
        exit 0
        """

    private func installHookScript() throws {
        let destURL = hookScriptURL()
        do {
            try Self.hookScriptContent.data(using: .utf8)?.write(to: destURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        } catch {
            throw HookInstallError.cantWriteScript(path: destURL.path)
        }
    }

    private func installManagedSignal() throws {
        let sourceURL = try resolvedBundledSignalURL()
        let destURL = managedSignalURL()
        let shouldCopy: Bool
        if fm.fileExists(atPath: destURL.path) {
            shouldCopy = (try? Data(contentsOf: sourceURL)) != (try? Data(contentsOf: destURL))
        } else {
            shouldCopy = true
        }

        guard shouldCopy else { return }
        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: sourceURL, to: destURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        } catch {
            throw HookInstallError.cantWriteHelper(path: destURL.path)
        }
    }

    private func resolvedBundledSignalURL() throws -> URL {
        if let bundledSignalURL, fm.fileExists(atPath: bundledSignalURL.path) {
            return bundledSignalURL
        }
        if let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("BoopSignal"),
           fm.fileExists(atPath: sibling.path) {
            return sibling
        }
        let expected = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("BoopSignal").path ?? "BoopSignal"
        throw HookInstallError.helperMissing(path: expected)
    }

    // MARK: - File helpers

    private func readJSONObject(at url: URL, agent: AgentKind) throws -> [String: Any] {
        guard fm.fileExists(atPath: url.path) else { return [:] }
        guard let data = fm.contents(atPath: url.path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallError.configUnreadable(agent: agent, path: url.path)
        }
        return root
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL, agent: AgentKind) throws {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            throw HookInstallError.serializationFailed(agent: agent)
        }
        try writeData(data, to: url, agent: agent)
    }

    private func writeString(_ string: String, to url: URL, agent: AgentKind) throws {
        guard let data = string.data(using: .utf8) else {
            throw HookInstallError.serializationFailed(agent: agent)
        }
        try writeData(data, to: url, agent: agent)
    }

    private func writeData(_ data: Data, to url: URL, agent: AgentKind) throws {
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backupIfPresent(url: url, agent: agent)
            try data.write(to: url, options: .atomic)
        } catch {
            throw HookInstallError.cantWriteConfig(path: url.path)
        }
    }

    private func backupIfPresent(url: URL, agent: AgentKind) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        let backupsDir = URL(fileURLWithPath: stateDir).appendingPathComponent("backups")
        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let timestamp = Self.backupDateFormatter.string(from: Date())
        let backupPrefix = "\(agent.rawValue)-\(url.lastPathComponent)-"
        let backupURL = backupsDir.appendingPathComponent("\(backupPrefix)\(timestamp)")
        if !fm.fileExists(atPath: backupURL.path) {
            try fm.copyItem(at: url, to: backupURL)
        }

        let backups = (try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil))
            ?? []
        let matching = backups
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in matching.dropLast(3) {
            try? fm.removeItem(at: old)
        }
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func createStateDirectories() throws {
        try fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: URL(fileURLWithPath: stateDir).appendingPathComponent("bin"), withIntermediateDirectories: true)
    }

    // MARK: - Shape helpers

    private static let claudePlainEvents = [
        "SessionStart", "UserPromptSubmit",
        "Stop", "StopFailure", "SessionEnd",
        "PostToolUse",
        "Elicitation", "ElicitationResult",
    ]

    private static let claudeNotificationMatchers = [
        "permission_prompt", "idle_prompt", "elicitation_dialog",
    ]

    private static let cursorEvents = [
        "sessionStart", "sessionEnd", "beforeSubmitPrompt", "stop",
        "beforeShellExecution", "beforeMCPExecution",
        "afterShellExecution", "afterMCPExecution",
    ]

    private static let codexEvents: [(event: String, matcher: String?, isApproval: Bool)] = [
        ("SessionStart", "startup|resume", false),
        ("UserPromptSubmit", nil, false),
        ("PermissionRequest", nil, true),
        ("PreToolUse", nil, false),
        ("PostToolUse", nil, false),
        ("Stop", nil, false),
    ]

    private func commandHook(command: String, timeout: Int) -> [String: Any] {
        ["type": "command", "command": command, "timeout": timeout]
    }

    private func addingNestedHook(to value: Any?, matcher: String?, hook: [String: Any]) -> [[String: Any]] {
        var eventHooks = value as? [[String: Any]] ?? []
        var group: [String: Any] = ["hooks": [hook]]
        if let matcher { group["matcher"] = matcher }
        eventHooks.append(group)
        return eventHooks
    }

    private func containsBoopNestedHooks(_ hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    for entry in innerHooks {
                        if let cmd = entry["command"] as? String, isBuddyCommand(cmd) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func isBoopInCursorHooks(_ root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                if let cmd = entry["command"] as? String, isBuddyCommand(cmd) {
                    return true
                }
            }
        }
        return false
    }

    private func removeBoopFromCursorHooks(_ root: [String: Any]) -> [String: Any] {
        var cleaned = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                (entry["command"] as? String).map(isBuddyCommand(_:)) ?? false
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

    private func removeLegacyHooks(from hooks: [String: Any]) -> [String: Any] {
        var cleaned = hooks
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { group in
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    return innerHooks.contains { entry in
                        if let cmd = entry["command"] as? String {
                            return isBuddyCommand(cmd)
                        }
                        if let url = entry["url"] as? String {
                            return url.contains("/claude-code/event")
                        }
                        return false
                    }
                }
                if let cmd = group["command"] as? String {
                    return isBuddyCommand(cmd)
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

    /// Is `codex_hooks` already switched on under `[features]`?
    ///
    /// Deliberately tolerant about spacing and trailing comments. Demanding
    /// the exact text `codex_hooks = true` meant a user who had written
    /// `codex_hooks=true` (or added a `# note`) read as "not enabled", so we
    /// inserted a SECOND copy of the key into the same table — which is
    /// invalid TOML, so Codex then refused to load its config at all. Verify
    /// reported it repairable, and every launch repaired it the same broken
    /// way, forever.
    private func codexHooksEnabled(in toml: String) -> Bool {
        var inFeatures = false
        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inFeatures = (line == "[features]")
                continue
            }
            guard inFeatures, let (key, value) = Self.tomlKeyValue(line) else { continue }
            if key == "codex_hooks" && value == "true" { return true }
        }
        return false
    }

    /// Split a TOML `key = value` line, dropping any trailing `# comment`.
    /// Returns nil for anything that isn't an assignment.
    nonisolated static func tomlKeyValue(_ line: String) -> (String, String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: eq)...])
        // Only strip a comment that isn't inside a quoted value; our keys are
        // bare booleans, so a quote before the # means leave it alone.
        if let hash = value.firstIndex(of: "#"),
           !value[..<hash].contains("\"") {
            value = String(value[..<hash])
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        return (key, trimmedValue)
    }

    private func hookSchemaVersion(in script: String) -> Int? {
        guard let header = script.split(separator: "\n").dropFirst().first else { return nil }
        guard let range = header.range(of: "boop-hook v") else { return nil }
        let suffix = header[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private func isExecutable(_ url: URL) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let perms = attrs[.posixPermissions] as? NSNumber else { return false }
        return (perms.intValue & 0o100) != 0
    }

    /// Is this hook entry one WE installed?
    ///
    /// Ownership means "it runs a binary we put there", i.e. the command names
    /// one of our own installed files. This used to be `cmd.contains("boop")`,
    /// which claimed any user hook whose path merely contained the word — a
    /// `~/.claude/hooks/reboop.sh`, or anything under a directory named after
    /// the pet — and then deleted the entire matcher group it belonged to,
    /// taking unrelated sibling hooks with it, on every install, repair and
    /// uninstall.
    private func isBuddyCommand(_ cmd: String) -> Bool {
        if cmd.contains(hookScriptURL().path) || cmd.contains(managedSignalURL().path) {
            return true
        }
        // Installs from an earlier layout may point somewhere else, so also
        // accept our binaries by exact filename — still a path component
        // match, never a bare substring of the whole command.
        return cmd.contains("/\(Self.hookScriptName)") || cmd.contains("/boop-signal")
    }

    private func configDir(for agent: AgentKind) -> URL {
        switch agent {
        case .claudeCode: return URL(fileURLWithPath: homeDir).appendingPathComponent(".claude")
        case .cursor: return URL(fileURLWithPath: homeDir).appendingPathComponent(".cursor")
        case .codex: return URL(fileURLWithPath: homeDir).appendingPathComponent(".codex")
        }
    }

    private func hookScriptURL() -> URL {
        URL(fileURLWithPath: stateDir).appendingPathComponent(Self.hookScriptName)
    }

    private func managedSignalURL() -> URL {
        URL(fileURLWithPath: stateDir).appendingPathComponent("bin/boop-signal")
    }

    private func scriptCommand(for agent: AgentKind) -> String {
        "\(hookScriptURL().path) \(agent.rawValue)"
    }

    private func cursorCommand() -> String {
        "\(managedSignalURL().path) --agent cursor"
    }

    private func rememberInstalled(_ agent: AgentKind) {
        var stored = Set(userDefaults.stringArray(forKey: DefaultsKey.installedAgents) ?? [])
        stored.insert(agent.rawValue)
        userDefaults.set(Array(stored).sorted(), forKey: DefaultsKey.installedAgents)
    }

    private func forgetInstalled(_ agent: AgentKind) {
        var stored = Set(userDefaults.stringArray(forKey: DefaultsKey.installedAgents) ?? [])
        stored.remove(agent.rawValue)
        if stored.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.installedAgents)
        } else {
            userDefaults.set(Array(stored).sorted(), forKey: DefaultsKey.installedAgents)
        }
    }

    private func uninstallJSONFailureReason(path: String) -> String {
        "\(path) is not valid JSON — Boop entries were not removed"
    }
}
