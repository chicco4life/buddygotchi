import Foundation

/// Owner-editable guidance, read again for each decision. State authority stays
/// in the reducer; this file steers only model choices within its action surface.
struct BuddyBehaviorGuide: Sendable {
    var overrideURL: URL? = nil
    static let maxBytes = 32_768

    func read() -> String {
        if let overrideURL, let text = Self.read(overrideURL) { return text }
        if let url = BuddyResources.moduleResourceURL(forResource: "BEHAVIOR", withExtension: "md", subdirectory: ""),
           let text = Self.read(url) { return text }
        return "Be a quiet desk companion. Use supplied facts only. Return SILENT."
    }

    private static func read(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes,
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
