import Foundation

/// The brain (SPEC.md §8): answers multiple-choice questions
/// about a plain-text state, with probabilities. `JevBrain`, or
/// `ScriptedBrain` in tests.
public protocol Brain: Sendable {
    /// For logs: `jev:jev-latest`, `scripted`.
    var id: String { get }
    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers
}

public struct BrainError: Error, Equatable, CustomStringConvertible {
    public var description: String
    /// What came back, when it couldn't be used, for your own debugging.
    public var raw: String?
    /// The HTTP status, when the brain's server answered with an error.
    public var status: Int?

    public init(_ description: String, raw: String? = nil, status: Int? = nil) {
        self.description = description
        self.raw = raw
        self.status = status
    }
}

/// Answers from a script: for tests and replays. The script sees the state
/// and the questions and returns the answers, or throws.
public struct ScriptedBrain: Brain {
    public let id: String
    public let script: @Sendable (String, [Question]) throws -> Answers

    public init(id: String = "scripted", _ script: @escaping @Sendable (String, [Question]) throws -> Answers) {
        self.id = id
        self.script = script
    }

    /// The same answers every time, by question key; a question it has no
    /// answer for gets its first option. An answer given with no
    /// probabilities reports its pick at 1, as a brain with none does (§8).
    public init(id: String = "scripted", always answers: Answers) {
        self.init(id: id) { _, questions in
            var out: Answers = [:]
            for q in questions {
                let pick = answers[q.key] ?? q.options.first.map { Answer(choice: $0.name) }
                out[q.key] = pick.map { $0.probabilities.isEmpty ? Answer(choice: $0.choice, probabilities: [$0.choice: 1]) : $0 }
            }
            return out
        }
    }

    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try script(state, questions)
    }
}
