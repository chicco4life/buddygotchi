import Foundation

/// Installs, repairs and removes Boop's hook entries (ADAPTERS.md §5):
/// Claude's in `~/.claude/settings.json`, Codex's in `~/.codex/hooks.json`.
///
/// Every entry Boop adds calls `boop-hook`, and that's how it recognises its
/// own. It never touches anyone else's hooks, but it does remove the previous
/// generation's, which call `~/.boop/boop-hook.sh`. Nothing is written when
/// nothing would change, so installing twice is the same as once.
public struct HookInstaller {
    public enum Agent: String, CaseIterable, Sendable {
        case claude, codex

        public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    }

    public enum Health: Equatable, Sendable {
        case notInstalled
        case installed
        /// Some of Boop's entries are missing, old or point elsewhere.
        case outdated
        /// The file isn't JSON Boop can read; it's left alone.
        case unreadable(String)
    }

    /// The hooks each agent gets, with a matcher where one is needed.
    static let events: [Agent: [(event: String, matcher: String?)]] = [
        .claude: [
            ("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", nil), ("PostToolUse", nil),
            ("PostToolUseFailure", nil), ("PermissionRequest", nil),
            ("Notification", "permission_prompt|elicitation_dialog"), ("Elicitation", nil),
            ("ElicitationResult", nil), ("Stop", nil), ("StopFailure", nil), ("SessionEnd", nil),
        ],
        .codex: [
            ("SessionStart", "startup|resume|clear"), ("UserPromptSubmit", nil), ("PreToolUse", nil),
            ("PostToolUse", nil), ("PermissionRequest", nil), ("Stop", nil), ("SessionEnd", nil),
        ],
    ]
    /// Seconds. `boop-hook` finishes in milliseconds and gives up after one.
    static let timeout = 5

    public let home: URL
    /// The `boop-hook` binary the entries call.
    public let hookPath: String

    public init(home: URL, hookPath: String) {
        self.home = home
        self.hookPath = hookPath
    }

    public func configURL(_ agent: Agent) -> URL {
        switch agent {
        case .claude: home.appendingPathComponent(".claude/settings.json")
        case .codex: home.appendingPathComponent(".codex/hooks.json")
        }
    }

    /// Whether the agent looks installed on this Mac.
    public func detected(_ agent: Agent) -> Bool {
        FileManager.default.fileExists(atPath: configURL(agent).deletingLastPathComponent().path)
    }

    public func command(_ agent: Agent) -> String {
        "\"\(hookPath)\" \(agent.rawValue)"
    }

    /// A Boop entry, current or from the previous generation.
    public static func isBoopCommand(_ command: String) -> Bool {
        if command.contains("/boop-hook.sh") { return true }
        return command.range(of: #"(^|/)boop-hook"?(\s|$)"#, options: .regularExpression) != nil
    }

    // MARK: Reading

    public func health(_ agent: Agent) -> Health {
        let root: [String: Any]
        switch read(agent) {
        case .failure(let why): return .unreadable(why.description)
        case .success(let r): root = r
        }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let ours = Self.boopCommands(in: hooks)
        if ours.isEmpty { return .notInstalled }
        return NSDictionary(dictionary: installing(agent, into: root)).isEqual(to: root) ? .installed : .outdated
    }

    /// What installing adds, one line per hook, for the setup screen, which
    /// puts the config file's path above it. For Codex it ends with the
    /// switch installing turns on in `config.toml`, unless it's already on.
    public func preview(_ agent: Agent) -> String {
        var text = Self.events[agent]!.map { "\($0.event)\($0.matcher.map { " (\($0))" } ?? "") → \(command(agent))" }
            .joined(separator: "\n")
        if agent == .codex, Self.enablingCodexHooks(in: codexConfigText) != nil {
            text += "\n\nIn \(codexConfigURL.path), under [features]:\ncodex_hooks = true"
        }
        return text
    }

    // MARK: Changing

    /// Adds Boop's entries, replacing any older ones. For Codex it also turns
    /// hooks on in `config.toml`.
    public func install(_ agent: Agent) throws {
        let root = try read(agent).get()
        try write(installing(agent, into: root), agent)
        if agent == .codex { try enableCodexHooks() }
    }

    /// Removes Boop's entries, current and old, and nothing else.
    public func remove(_ agent: Agent) throws {
        let root = try read(agent).get()
        try write(removing(from: root), agent)
    }

    /// On launch: brings back missing or outdated entries for agents that
    /// already have Boop's. Returns the agents it repaired.
    @discardableResult
    public func repair() -> [Agent] {
        Agent.allCases.filter { agent in
            guard health(agent) == .outdated else { return false }
            return (try? install(agent)) != nil
        }
    }

    func installing(_ agent: Agent, into root: [String: Any]) -> [String: Any] {
        var root = removing(from: root)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["type": "command", "command": command(agent), "timeout": Self.timeout]
        for (event, matcher) in Self.events[agent]! {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [entry]]
            if let matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return root
    }

    func removing(from root: [String: Any]) -> [String: Any] {
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        var removedAny = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            var changed = false
            for var group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else {
                    kept.append(group)
                    continue
                }
                let others = entries.filter { !Self.isBoopCommand($0["command"] as? String ?? "") }
                if others.count == entries.count {
                    kept.append(group)
                    continue
                }
                changed = true
                if !others.isEmpty {
                    group["hooks"] = others
                    kept.append(group)
                }
            }
            guard changed else { continue }
            removedAny = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard removedAny else { return root }
        var root = root
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    static func boopCommands(in hooks: [String: Any]) -> [String] {
        hooks.values.flatMap { value -> [String] in
            let groups = value as? [[String: Any]] ?? []
            return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }.filter(isBoopCommand)
    }

    // MARK: Files

    func read(_ agent: Agent) -> Result<[String: Any], Refusal> {
        let url = configURL(agent)
        guard let data = try? Data(contentsOf: url) else { return .success([:]) }
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return .success([:]) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(Refusal("\(url.lastPathComponent) isn't a JSON object"))
        }
        return .success(object)
    }

    func write(_ root: [String: Any], _ agent: Agent) throws {
        let url = configURL(agent)
        if case .success(let old) = read(agent), NSDictionary(dictionary: old).isEqual(to: root),
           FileManager.default.fileExists(atPath: url.path) || root.isEmpty { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    /// Codex runs hooks only with `codex_hooks = true` under `[features]`.
    /// Boop adds the line if it's missing and never removes it: other hooks
    /// may rely on it.
    func enableCodexHooks() throws {
        guard let updated = Self.enablingCodexHooks(in: codexConfigText) else { return }
        try updated.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    }

    var codexConfigURL: URL { home.appendingPathComponent(".codex/config.toml") }

    /// `config.toml` as it is now; empty if it isn't there.
    var codexConfigText: String { (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? "" }

    /// `toml` with `codex_hooks = true` in `[features]`, or nil if it's
    /// already there.
    static func enablingCodexHooks(in toml: String) -> String? {
        var lines = toml.components(separatedBy: "\n")
        var section = ""
        var featuresAt: Int?
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line
                if line == "[features]" { featuresAt = i }
                continue
            }
            if section == "[features]", line.replacingOccurrences(of: " ", with: "").hasPrefix("codex_hooks=") {
                if line.replacingOccurrences(of: " ", with: "") == "codex_hooks=true" { return nil }
                lines[i] = "codex_hooks = true"
                return lines.joined(separator: "\n")
            }
        }
        if let featuresAt {
            lines.insert("codex_hooks = true", at: featuresAt + 1)
            return lines.joined(separator: "\n")
        }
        var out = toml
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty { out += "\n" }
        return out + "[features]\ncodex_hooks = true\n"
    }
}
