import Foundation

/// The brain (kit/BRAIN-KIT.md §8): answers multiple-choice questions
/// about a plain-text state, with probabilities. `JevBrain`, or
/// `ScriptedBrain` in tests.
public protocol Brain: Sendable {
    /// For logs: `jev:jev-latest`, `scripted`.
    var id: String { get }
    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers
}

public struct BrainError: Error, Equatable, CustomStringConvertible {
    public var description: String
    /// What came back, when it couldn't be used, for debug mode.
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
    package let script: @Sendable (String, [Question]) throws -> Answers

    public init(id: String = "scripted", _ script: @escaping @Sendable (String, [Question]) throws -> Answers) {
        self.id = id
        self.script = script
    }

    /// The same answers every time, by question key; a question it has no
    /// answer for gets its first option.
    public init(id: String = "scripted", always answers: Answers) {
        self.init(id: id) { _, questions in
            var out: Answers = [:]
            for q in questions {
                out[q.key] = answers[q.key] ?? q.options.first.map { Answer(choice: $0.name, probabilities: [$0.name: 1]) }
            }
            return out
        }
    }

    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try script(state, questions)
    }
}
