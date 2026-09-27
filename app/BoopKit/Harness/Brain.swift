import Foundation

/// The brain (harness/HARNESS.md §7): answers multiple-choice questions
/// about a plain-text state, with probabilities. Jev in the app,
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

    public init(_ description: String, raw: String? = nil) {
        self.description = description
        self.raw = raw
    }
}

/// Answers from a script: for tests and replays. The script sees the state
/// and the questions and returns the answers, or throws.
public struct ScriptedBrain: Brain {
    public let id: String
    let script: @Sendable (String, [Question]) throws -> Answers

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

extension ScriptedBrain {
    /// For pipeline checks with no network (`Boop --headless --brain
    /// scripted`): every pass, an excited mumble with "yay", and no mood
    /// change.
    public static let pipelineCheck = ScriptedBrain(id: "scripted", always: [
        "mood": Answer(choice: "cheerful", probabilities: ["cheerful": 1]),
        "react": Answer(choice: "excited", probabilities: ["excited": 1]),
        "word.feeling": Answer(choice: "yay", probabilities: ["yay": 1]),
        "word.about": Answer(choice: "none", probabilities: ["none": 1]),
    ])
}
