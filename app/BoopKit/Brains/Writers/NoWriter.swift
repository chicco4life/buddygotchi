import Foundation

/// No writer (Stage 2, HARNESS.md §6): writes nothing, so a mumble goes
/// without its real word and nothing is remembered. `--writer none`, and
/// the deterministic evals.
public struct NoWriter: Writer {
    public let id = "none"

    public init() {}

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        Writing(values: [:])
    }
}
