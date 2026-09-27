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

    /// The topic of what a shell command runs: its program and the words
    /// after it, in each of its commands (`cd app && swift test` is two),
    /// after `VAR=value` and wrappers like `npx`, `uv run` or `bundle exec`.
    /// A check word in an argument, quoted text or a heredoc doesn't count,
    /// so `grep -n "make test" Makefile` has no topic. When several commands
    /// have one, deploy beats tests, which beats build.
    public static func tag(command: String) -> String? {
        var best: Int?
        for words in commands(command) {
            guard let index = rule(words) else { continue }
            best = min(best ?? index, index)
        }
        return best.map { rules[$0].topic }
    }

    /// The first rule one simple command matches: the pattern's first word
    /// is the program, and the rest appear in order among its arguments
    /// that aren't flags (`make -C firmware test`).
    static func rule(_ words: [String]) -> Int? {
        guard let (program, args) = unwrap(words) else { return nil }
        if shells.contains(program), let at = args.firstIndex(where: isDashC), at + 1 < args.count {
            // `bash -lc "cargo test -q"`: the script is the command.
            return commands(args[at + 1]).compactMap(rule).min()
        }
        if let inside = containerCommand(program, args) { return rule(inside) }
        let operands = args.filter { !$0.hasPrefix("-") }
        for (index, rule) in rules.enumerated() {
            for pattern in rule.patterns where pattern[0] == program && inOrder(Array(pattern.dropFirst()), operands) {
                return index
            }
        }
        return nil
    }

    static let shells: Set<String> = ["sh", "bash", "zsh"]
    /// A shell's `-c`, alone or among other short options (`-lc`), and not
    /// a long option such as `--norc` or `--rcfile`.
    static func isDashC(_ word: String) -> Bool {
        word.hasPrefix("-") && !word.hasPrefix("--") && word.contains("c")
    }
    /// Shell words that start a command without being its program:
    /// `do make test`, `then make test`, `{ make test; }`, `! make test`.
    static let reserved: Set<String> = ["if", "then", "elif", "else", "do", "while", "until", "!", "{"]
    /// Words that run the command after them: `sudo make`, `npx jest`.
    static let wrappers: Set<String> = [
        "sudo", "env", "time", "nice", "nohup", "command", "exec", "caffeinate", "timeout", "xcrun", "npx", "bunx",
        "pnpx", "stdbuf",
    ]
    /// A wrapper's flags that take the next word as their value:
    /// `sudo -u me make`, `timeout -s KILL 60 make`.
    static let wrapperValueFlags: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-p", "-C", "-D", "-U", "-r", "-t", "-T", "-h"],
        "env": ["-u", "--unset", "-C", "--chdir"], "timeout": ["-s", "--signal", "-k", "--kill-after"],
        "nice": ["-n"], "exec": ["-a"], "xcrun": ["--sdk", "-sdk", "--toolchain", "-toolchain"],
        "npx": ["-p", "--package"], "stdbuf": ["-i", "-o", "-e"],
    ]
    /// Two-word wrappers: `uv run pytest`, `bundle exec rspec`.
    static let runners: Set<String> = [
        "uv run", "poetry run", "pipenv run", "pdm run", "hatch run", "rye run", "bundle exec", "pnpm exec",
        "pnpm dlx", "yarn dlx", "npm exec", "bun x",
    ]
    /// Package managers that run a project's own tools by name: `yarn jest`,
    /// `pnpm vitest run`. Only for a tool a rule knows, so `yarn test` stays
    /// the script it names.
    static let toolRunners: Set<String> = ["yarn", "pnpm", "bun"]
    static let tools: Set<String> = Set(rules.flatMap { $0.patterns.map { $0[0] } }).subtracting(["npm", "yarn", "pnpm", "bun", "deno"])

    /// The program a simple command runs, reduced to its last path part
    /// (`./gradlew` → `gradlew`), and its arguments. Nil when it runs
    /// nothing, such as `command -v pytest`, which only looks one up.
    static func unwrap(_ words: [String]) -> (program: String, args: [String])? {
        var i = 0
        func skipAssignments() {
            while i < words.count, isAssignment(words[i]) { i += 1 }
        }
        skipAssignments()
        while i < words.count {
            let word = (words[i] as NSString).lastPathComponent
            if reserved.contains(words[i]) {
                i += 1
                skipAssignments()
            } else if wrappers.contains(word) {
                if word == "command", i + 1 < words.count, ["-v", "-V"].contains(words[i + 1]) { return nil }
                let valued = wrapperValueFlags[word] ?? []
                i += 1
                // Its flags and their values, a duration (`timeout 60`) and
                // `env`'s variables.
                while i < words.count, words[i].hasPrefix("-") || words[i].first?.isNumber == true || isAssignment(words[i]) {
                    i += valued.contains(words[i]) ? 2 : 1
                }
            } else if i + 1 < words.count, runners.contains(word + " " + words[i + 1]) {
                i += 2
            } else if toolRunners.contains(word), i + 1 < words.count, tools.contains(words[i + 1]) {
                i += 1
            } else if word.hasPrefix("python"), i + 2 < words.count, words[i + 1] == "-m" {
                i += 2  // `python -m pytest` runs pytest
            } else {
                return (word, Array(words[(i + 1)...]))
            }
        }
        return nil
    }

    /// Container flags that take the next word as their value.
    static let containerValueFlags: Set<String> = [
        "-e", "--env", "--env-file", "-w", "--workdir", "-v", "--volume", "-u", "--user", "-p", "--publish",
        "--name", "--entrypoint", "-l", "--label", "--network", "--platform", "--index", "-f", "--file",
        "--project-name", "--profile",
    ]

    /// The command a container runs: `docker compose run --rm web pytest`
    /// or `docker exec -it api make test` runs what follows the service or
    /// image. Nil for anything else, `docker build` included.
    static func containerCommand(_ program: String, _ args: [String]) -> [String]? {
        guard ["docker", "docker-compose", "podman"].contains(program) else { return nil }
        var i = 0
        func skipFlags() {
            while i < args.count, args[i].hasPrefix("-") { i += containerValueFlags.contains(args[i]) ? 2 : 1 }
        }
        skipFlags()
        if i < args.count, args[i] == "compose" {
            i += 1
            skipFlags()
        }
        guard i < args.count, ["run", "exec"].contains(args[i]) else { return nil }
        i += 1
        skipFlags()
        i += 1  // the service or image
        return i < args.count ? Array(args[i...]) : nil
    }

    static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex, let first = word.first,
              first.isLetter || first == "_" else { return false }
        return word[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func inOrder(_ pattern: [String], _ words: [String]) -> Bool {
        var next = pattern.startIndex
        for word in words where next < pattern.endIndex && word == pattern[next] { next += 1 }
        return next == pattern.endIndex
    }

    /// A shell command's text: Claude's `command` string, or Codex's argv.
    static func command(in input: Any?) -> String? {
        guard let object = input as? [String: Any] else { return nil }
        for key in ["command", "cmd"] {
            if let text = object[key] as? String { return text }
            if let argv = object[key] as? [String] { return argv.map(quoted).joined(separator: " ") }
        }
        return nil
    }

    /// One argv word as the shell would need it, so `["bash", "-lc",
    /// "cargo test"]` keeps its script in one piece.
    static func quoted(_ word: String) -> String {
        guard word.isEmpty || word.contains(where: { $0.isWhitespace || "'\"\\;&|()`$<>".contains($0) }) else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    /// A command line's simple commands, each as its words: split at `;`,
    /// `&&`, `||`, `|`, `&`, newlines, parentheses, backticks and `$(`,
    /// with quotes and backslashes taken as the shell does and heredoc
    /// bodies left out. Only the first 4 KB is read.
    static func commands(_ command: String) -> [[String]] {
        var all: [[String]] = []
        var words: [String] = []
        var current = ""
        var quotedWord = false
        func endWord() {
            if !current.isEmpty || quotedWord { words.append(current) }
            current = ""
            quotedWord = false
        }
        func endCommand() {
            endWord()
            if !words.isEmpty { all.append(words) }
            words = []
        }
        let chars = Array(withoutHeredocs(String(command.prefix(4096))))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            switch ch {
            case "'":
                quotedWord = true
                i += 1
                while i < chars.count, chars[i] != "'" { current.append(chars[i]); i += 1 }
            case "\"":
                quotedWord = true
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count { i += 1 }
                    current.append(chars[i])
                    i += 1
                }
            case "\\":
                if let next, next != "\n" { current.append(next) }
                i += 1
            case "&" where current.hasSuffix(">") || current.hasSuffix("<") || next == ">":
                current.append(ch)  // a redirection: `2>&1`, `&>log`
            case "$" where next == "(":
                endCommand()
                i += 1
            case ";", "\n", "|", "&", "(", ")", "`":
                endCommand()
            default:
                if ch.isWhitespace { endWord() } else { current.append(ch) }
            }
            i += 1
        }
        endCommand()
        return all
    }

    /// The command with each heredoc's body taken out, since it's text and
    /// not commands: `git commit -F - <<'EOF'` … `EOF`.
    static func withoutHeredocs(_ command: String) -> String {
        guard command.contains("<<") else { return command }
        var kept: [Substring] = []
        var delimiter: String?
        for line in command.split(separator: "\n", omittingEmptySubsequences: false) {
            if let d = delimiter {
                if line.trimmingCharacters(in: .whitespaces) == d { delimiter = nil }
                continue
            }
            kept.append(line)
            guard let marker = line.range(of: "<<"), !line[marker.upperBound...].hasPrefix("<") else { continue }
            let word = line[marker.upperBound...].drop { $0 == "-" || $0 == " " || $0 == "\t" }
                .prefix { !$0.isWhitespace && !";&|)".contains($0) }
            let name = word.filter { $0 != "'" && $0 != "\"" && $0 != "\\" }
            if !name.isEmpty { delimiter = name }
        }
        return kept.joined(separator: "\n")
    }
}
