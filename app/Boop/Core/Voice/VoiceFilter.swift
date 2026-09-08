import Foundation

enum VoiceFilter {
    private static let sentenceEnd = try! NSRegularExpression(pattern: #"[.!?](?:\s+|$)"#)
    static let banned = ["you keep", "you always", "you never", "you should", "your fault", "당신은 항상", "당신은 맨날", "너는 항상", "너는 맨날", "너 맨날", "너 항상", "넌 맨날", "넌 항상", "네가 맨날", "네가 항상", "당신은 늘", "너는 늘", "당신 잘못", "네 잘못", "네 탓", "니 탓", "당신 탓", "해야 해", "해야해", "token", "money", "dollar", "productivity", "productive", "efficiency", "efficient", "cash", "price", "profit", "cost", "rent", "wage", "salary", "budget", "euro", "dollars", "bucks", "spend", "토큰", "돈", "달러", "생산성", "효율", "수익", "비용", "원화", "가격", "월급", "예산"]
    static let bannedWords: Set<String> = Set(banned.filter {
        $0.unicodeScalars.allSatisfy(\.isASCII) && !$0.contains(" ")
    }.flatMap { [$0, $0 + "s"] })
    static let bannedSqueezed: [String] = banned.filter {
        !$0.unicodeScalars.allSatisfy(\.isASCII) || $0.contains(" ")
    }.map { String($0.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }
    /// Validate the whole response before truncation, so an unsafe suffix cannot be hidden.
    static func check(_ text: String, language: String, byteCap: Int, allowExclamation: Bool = false) -> String? {
        guard ["en", "ko"].contains(language), byteCap > 0, text.utf8.prefix(8193).count <= 8192 else { return nil }
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
        let compact = normalized.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let squeezed = String(compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        let words = compact.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let unsafe = words.contains { bannedWords.contains($0) || $0.hasPrefix("token") }
            || bannedSqueezed.contains { squeezed.contains($0) }
        guard !unsafe,
              !normalized.contains("$"), !normalized.contains("₩"), !normalized.contains("€"),
              allowExclamation || !normalized.contains("!"),
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x200B || $0.value == 0x200D }),
              !normalized.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 127) || $0.value == 0xFE0F || $0.value == 0x20E3 }) else { return nil }
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let endings = sentenceEnd.matches(in: trimmed, range: range)
        let tail = endings.last.map { NSMaxRange($0.range) < range.length } ?? !trimmed.isEmpty
        guard endings.count + (tail ? 1 : 0) <= (byteCap <= VoiceCap.bubble.rawValue ? 1 : 3) else { return nil }
        let line = trimmed.prefix(utf8Bytes: byteCap)
        return line.isEmpty ? nil : line
    }
}
