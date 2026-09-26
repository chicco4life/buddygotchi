import Foundation

/// Stage 1 of the brain (HARNESS.md §6): decides what Boop does about an
/// input. It picks outputs from the menu and fills in every argument the
/// menu marks as decided; it never writes words. Staying quiet is no calls.
public protocol Classifier: Sendable {
    /// e.g. `rules@2`, `jev:jev-latest`.
    var id: String { get }
    /// May throw; the harness drops the pass and logs why.
    func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification
}

/// Stage 2 (HARNESS.md §6): writes the words for what Stage 1 decided, and
/// nothing else. It fills slots: it can't add, drop or reorder decisions.
public protocol Writer: Sendable {
    /// e.g. `apple:26.4`, `none`.
    var id: String { get }
    /// Values by slot key. A slot left out, empty or `none` is left empty.
    /// May throw; the harness then treats every slot as empty.
    func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing
}

/// What a brain gets for one pass: the input, the memory text and the
/// transcript's window (HARNESS.md §4), oldest first. The window ends with
/// this input's own entries; the writer's also has Stage 1's `decided`.
public struct Context: Equatable, Sendable {
    public var input: Input
    public var memory: Prompt.Memory
    public var window: [Transcript.Entry]

    public init(input: Input, memory: Prompt.Memory, window: [Transcript.Entry]) {
        self.input = input
        self.memory = memory
        self.window = window
    }
}

/// Stage 1's answer: the calls, with only decided arguments, and how it got
/// there (the rule that matched, Jev's answers) for the transcript and the log.
public struct Classification: Equatable, Sendable {
    public var calls: [ToolCall]
    public var evidence: String?

    public init(calls: [ToolCall], evidence: String? = nil) {
        self.calls = calls
        self.evidence = evidence
    }
}

/// Stage 2's answer: a value for each slot it filled, and what the model
/// returned, for the debug log.
public struct Writing: Equatable, Sendable {
    public var values: [String: String]
    public var raw: String?

    public init(values: [String: String], raw: String? = nil) {
        self.values = values
        self.raw = raw
    }
}

public struct BrainError: Error, Equatable, CustomStringConvertible {
    public var description: String
    /// What the model answered, when it answered something unusable.
    public var raw: String?

    public init(_ description: String, raw: String? = nil) {
        self.description = description
        self.raw = raw
    }

    /// The model declined to answer (a guardrail). Handled like any error,
    /// but counted apart in L5.
    public static func refused(_ why: String) -> BrainError { BrainError(refusedPrefix + why) }
    static let refusedPrefix = "refused: "
    public var refused: Bool { description.hasPrefix(BrainError.refusedPrefix) }
}
