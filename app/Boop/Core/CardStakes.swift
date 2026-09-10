import Foundation

/// Destructive-shell classifier. Literal fragments are plain `contains`;
/// only the pipe-to-shell shapes need a regex, compiled once.
enum CardStakesPolicy {
    static let carefulLiterals = ["rm -rf", "rm -r ", "sudo ", "git push --force", "git push -f", "mkfs", "dd if=", "chmod 777"]
    static let carefulRegexes: [NSRegularExpression] = [#"curl\b[^\n]*\|\s*sh\b"#, #"wget\b[^\n]*\|\s*sh\b"#]
        .map { try! NSRegularExpression(pattern: $0) }
    /// Cursor's read-only tool names; Claude/Codex names go through `activityKind`.
    static let readOnlyCursorTools: Set<String> = ["ls", "read_file", "list_dir", "list_directory", "file_search", "grep_search", "codebase_search", "search"]
    static let controlCharacters = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\t"))
}

func cardStakes(tool: String, hint: String) -> Stakes {
    if hint.rangeOfCharacter(from: CardStakesPolicy.controlCharacters) != nil { return .careful }
    if CardStakesPolicy.carefulLiterals.contains(where: { hint.contains($0) }) { return .careful }
    let range = NSRange(location: 0, length: (hint as NSString).length)
    if CardStakesPolicy.carefulRegexes.contains(where: { $0.firstMatch(in: hint, range: range) != nil }) { return .careful }
    if activityKind(tool: tool, hint: hint) == .read || CardStakesPolicy.readOnlyCursorTools.contains(tool.lowercased()) { return .fine }
    return .checkIt
}
