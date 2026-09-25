import Foundation

/// The checks every line written to memory passes: one plain line within a
/// length, with no code, paths or secrets, and (for long-term memory) no
/// other people's names (ARCHITECTURE.md §4.2).
enum MemoryText {
    /// Capitalised words that aren't names.
    static let notNames: Set<String> = [
        "I", "I'm", "I've", "I'd", "OK", "Boop", "Claude", "Codex", "Cursor", "Mac", "AI", "English",
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays",
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
        "November", "December",
    ]

    /// The cleaned line, or why it's refused.
    static func check(_ raw: String, max: Int, names: Bool, boopName: String? = nil) -> Result<String, Refusal> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .failure(Refusal("empty")) }
        if text.contains(where: \.isNewline) { return .failure(Refusal("more than one line")) }
        if text.count > max { return .failure(Refusal("longer than \(max) characters")) }
        if text.hasPrefix("#") { return .failure(Refusal("looks like a heading")) }
        if let why = code(text) { return .failure(Refusal(why)) }
        if names, let name = otherName(text, boopName: boopName) {
            return .failure(Refusal("\"\(name)\" looks like someone's name"))
        }
        return .success(text)
    }

    static func code(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return "has a link" }
        if text.contains("`") || text.contains("{") || text.contains("}") || text.contains(";") || text.contains("=")
            || text.contains("()") || text.contains("->") || text.contains("$") || text.contains("<") || text.contains(">")
        {
            return "looks like code"
        }
        if text.contains("@") { return "has an address" }
        // A path: `~/x`, `/x/y`, `./x`, or a word with a slash and a file
        // extension. "and/or" is fine.
        let words = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for w in words {
            let bare = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,:!?()\"'"))
            if bare.hasPrefix("~/") || bare.hasPrefix("./") || bare.hasPrefix("../") { return "has a path" }
            if bare.hasPrefix("/") && bare.count > 1 { return "has a path" }
            if bare.filter({ $0 == "/" }).count >= 2 { return "has a path" }
            if bare.contains("/") && bare.contains(".") { return "has a path" }
            if secret(bare) { return "looks like a secret" }
        }
        return nil
    }

    /// Long runs of letters and digits mixed, or a known key prefix.
    static func secret(_ w: String) -> Bool {
        let prefixes = ["sk-", "sk_", "pk_", "ghp_", "gho_", "github_pat_", "xox", "akia", "aiza", "eyj"]
        if prefixes.contains(where: { w.lowercased().hasPrefix($0) }) && w.count >= 12 { return true }
        guard w.count >= 20 else { return false }
        let digits = w.filter(\.isNumber).count
        let letters = w.filter(\.isLetter).count
        return digits >= 3 && letters >= 3
    }

    /// A capitalised word that isn't the first word of a sentence and isn't a
    /// day, month, agent or Boop's own name.
    static func otherName(_ text: String, boopName: String?) -> String? {
        var sentenceStart = true
        for w in text.split(separator: " ") {
            let bare = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()\"'"))
            defer { sentenceStart = w.hasSuffix(".") || w.hasSuffix("!") || w.hasSuffix("?") || w.hasSuffix(":") }
            guard let first = bare.first, first.isUppercase else { continue }
            if sentenceStart || notNames.contains(bare) || bare == boopName { continue }
            // All capitals is an acronym (CI, PR), not a name.
            if bare.allSatisfy({ $0.isUppercase || $0.isNumber }) { continue }
            let possessive = bare.hasSuffix("'s") ? String(bare.dropLast(2)) : bare
            if notNames.contains(possessive) || possessive == boopName { continue }
            return bare
        }
        return nil
    }
}

public struct Refusal: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}
