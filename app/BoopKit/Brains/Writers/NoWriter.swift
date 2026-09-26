import Foundation

/// No writer (Stage 2, HARNESS.md §6): writes nothing, so a mumble goes
/// without its real word and nothing is remembered. The setting `none`, and
/// what `apple` falls back to on a Mac where Apple's model can't run.
public struct NoWriter: Writer {
    public let id = "none"

    public init() {}

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        Writing(values: [:])
    }
}
