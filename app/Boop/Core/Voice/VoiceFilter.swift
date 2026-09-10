import Foundation

/// Display validation only. Personality, wording and punctuation belong in
/// BEHAVIOR.md, so editing that guide can actually change the buddy's voice.
enum VoiceFilter {
    static func check(_ text: String, language: String, byteCap: Int) -> String? {
        guard ["en", "ko"].contains(language), byteCap > 0,
              text.utf8.prefix(8193).count <= 8192 else { return nil }
        let line = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty,
              !line.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || $0.value == 0x200B || $0.value == 0x200D
              }) else { return nil }
        let capped = line.prefix(utf8Bytes: byteCap)
        return capped.isEmpty ? nil : capped
    }
}
