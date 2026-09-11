import Foundation

/// Narrow display-boundary checks, not a claim of comprehensive PII detection.
/// Private reflection has its own evidence contract and does not use these.
enum DisplayPrivacy {
    private static let credential = #"(?i)\b(?:password|passwd|api[_ -]?key|access[_ -]?token|secret)\s*[:=]\s*[\"']?([^\s\"';,]+)"#
    private static let privatePatterns = [
        credential,
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"(?:/Users/|/home/|/private/|/tmp/|~/)[^\s\"']+"#,
        #"\b[A-Z]:\\[^\s\"']+"#,
        #"\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{8,})\b"#
    ]
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    static func redacted(_ value: Any) -> Any {
        if let text = value as? String {
            return privatePatterns.reduce(text) { text, pattern in
                regex(pattern)?.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[private]") ?? text
            }
        }
        if let items = value as? [Any] { return items.map(redacted) }
        if let object = value as? [String: Any] { return object.mapValues(redacted) }
        return value
    }
    static func allows(_ text: String, context: BehaviorContext) -> Bool {
        if (redacted(text) as? String) != text { return false }
        let inputs = context.desk.projects.flatMap { $0.tasks.flatMap { [$0.intent, $0.latest_request].compactMap { $0 } } }
        guard let pattern = regex(credential) else { return false }
        for input in inputs {
            for match in pattern.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
                guard let range = Range(match.range(at: 1), in: input) else { continue }
                let value = String(input[range])
                if !value.isEmpty, text.range(of: value, options: [.caseInsensitive]) != nil { return false }
            }
        }
        return true
    }
    static func remarkKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
