import Foundation

/// DeepSeek as the writer (Stage 2, HARNESS.md §6), with the person's own
/// API key. Not built yet: it refuses every write, so a mumble goes without
/// its word and nothing is remembered, and Settings shows it as not yet
/// available. When it's built it will send the window as chat messages that
/// only ever grow, so DeepSeek's prompt cache applies (FUTURE.md).
public struct DeepSeekWriter: Writer {
    public let model: String
    public var id: String { "deepseek:\(model)" }

    public init(model: String = "deepseek-flash") { self.model = model }

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        throw BrainError("the DeepSeek writer isn't available yet")
    }
}
