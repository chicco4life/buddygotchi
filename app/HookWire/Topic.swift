import Foundation

/// Topic tags (ADAPTERS.md §3): a glance at a tool's input, so Boop's one real
/// word can be about the work. Only the tag leaves this function.
public enum Topic {
    /// Command shapes, as whole words in order. Deploy is checked first, then
    /// tests, then build, so `make test` is tests and `make` alone is build.
    static let rules: [(topic: String, patterns: [[String]])] = [
        ("deploy", [
            ["vercel"], ["fly", "deploy"], ["flyctl", "deploy"], ["kubectl", "apply"], ["terraform", "apply"],
            ["netlify", "deploy"], ["firebase", "deploy"], ["wrangler", "deploy"], ["wrangler", "publish"],
            ["helm", "upgrade"], ["helm", "install"], ["cdk", "deploy"], ["serverless", "deploy"],
            ["sls", "deploy"], ["railway", "up"], ["gcloud", "deploy"], ["git", "push", "heroku"],
        ]),
        ("tests", [
            ["pytest"], ["jest"], ["vitest"], ["mocha"], ["rspec"], ["phpunit"], ["tox"], ["ctest"],
            ["npm", "test"], ["npm", "run", "test"], ["npm", "t"], ["yarn", "test"], ["pnpm", "test"],
            ["pnpm", "run", "test"], ["bun", "test"], ["deno", "test"], ["go", "test"], ["cargo", "test"],
            ["swift", "test"], ["make", "test"], ["make", "check"], ["make", "fw-test"], ["pio", "test"],
            ["mix", "test"], ["gradle", "test"], ["gradlew", "test"], ["mvn", "test"], ["xcodebuild", "test"],
            ["dotnet", "test"], ["rake", "test"], ["playwright", "test"],
        ]),
        ("build", [
            ["make"], ["tsc"], ["xcodebuild"], ["cmake"], ["ninja"], ["npm", "run", "build"], ["yarn", "build"],
            ["pnpm", "build"], ["pnpm", "run", "build"], ["bun", "run", "build"], ["cargo", "build"],
            ["swift", "build"], ["go", "build"], ["gradle", "build"], ["gradlew", "build"],
            ["gradlew", "assemble"], ["mvn", "package"], ["mvn", "install"], ["pio", "run"],
            ["vite", "build"], ["next", "build"], ["docker", "build"], ["dotnet", "build"], ["webpack"],
        ]),
    ]

    static let docExtensions: Set<String> = ["md", "markdown", "mdx", "txt", "rst"]
    static let editTools: Set<String> = [
        "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch", "edit", "write", "write_file", "edit_file",
    ]
    static let shellTools: Set<String> = [
        "Bash", "shell", "local_shell", "exec_command", "container.exec", "bash", "unified_exec",
    ]

    public static func tag(tool: String?, input: Any?) -> String? {
        guard let tool else { return nil }
        if shellTools.contains(tool) || command(in: input) != nil && !editTools.contains(tool) {
            return command(in: input).flatMap(tag(command:))
        }
        if editTools.contains(tool) {
            return paths(in: input, tool: tool).contains(where: isDoc) ? "docs" : nil
        }
        return nil
    }

    public static func tag(command: String) -> String? {
        let words = tokens(command)
        guard !words.isEmpty else { return nil }
        for rule in rules {
            for pattern in rule.patterns where contains(words, pattern) {
                return rule.topic
            }
        }
        return nil
    }

    /// A shell command's text: Claude's `command` string, or Codex's argv.
    static func command(in input: Any?) -> String? {
        guard let object = input as? [String: Any] else { return nil }
        for key in ["command", "cmd"] {
            if let text = object[key] as? String { return text }
            if let argv = object[key] as? [String] { return argv.joined(separator: " ") }
        }
        return nil
    }

    static func paths(in input: Any?, tool: String) -> [String] {
        if let patch = input as? String { return patchPaths(patch) }
        guard let object = input as? [String: Any] else { return [] }
        var found: [String] = []
        for key in ["file_path", "path", "notebook_path", "filename"] {
            if let path = object[key] as? String { found.append(path) }
        }
        for key in ["patch", "input"] {
            if let patch = object[key] as? String { found += patchPaths(patch) }
        }
        return found
    }

    /// File names in an `apply_patch` body (`*** Update File: x.md`).
    static func patchPaths(_ patch: String) -> [String] {
        patch.split(separator: "\n").compactMap { line in
            for marker in ["*** Update File: ", "*** Add File: "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
            return nil
        }
    }

    static func isDoc(_ path: String) -> Bool {
        docExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Words of a command, with paths reduced to their last part
    /// (`./gradlew` → `gradlew`) and shell punctuation split off.
    static func tokens(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                let base = (current as NSString).lastPathComponent
                words.append(base.isEmpty ? current : base)
            }
            current = ""
        }
        for ch in command.prefix(4096) {
            if ch.isWhitespace || ";&|()`\"'".contains(ch) {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return words
    }

    static func contains(_ words: [String], _ pattern: [String]) -> Bool {
        guard pattern.count <= words.count else { return false }
        for start in 0...(words.count - pattern.count) where words[start] == pattern[0] {
            if Array(words[start..<(start + pattern.count)]) == pattern { return true }
        }
        return false
    }
}
