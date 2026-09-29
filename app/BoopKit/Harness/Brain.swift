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
    /// scripted`): every pass, an excited face that names a start (a
    /// `start` take, a word, in excited: "Go" or the like), held once, and the mood kept (the mood question's first option); and a
    /// turn's finish in it when NOW is a turn that ended, success when done
    /// and failure when failed, since no rule plays one (BEHAVIORS.md §5).
    /// An answer a question doesn't offer is its first option, as Jev can
    /// only pick one of each question's own.
    public static let pipelineCheck = ScriptedBrain(id: "scripted") { state, questions in
        let now = state.components(separatedBy: "\nNOW (").last ?? ""
        let finish = !now.contains(" finished turn ") ? "none"
            : now.contains(": done, a ") ? "success" : now.contains(": failed, a ") ? "failure" : "none"
        let answers: Answers = [
            "react.mood": Answer(choice: "excited", probabilities: ["excited": 1]),
            "react.animation": Answer(choice: finish, probabilities: [finish: 1]),
            "react.loops": Answer(choice: "once", probabilities: ["once": 1]),
            "say.feeling": Answer(choice: "none", probabilities: ["none": 1]),
            "say.about": Answer(choice: "start", probabilities: ["start": 1]),
            "say.kind": Answer(choice: "word", probabilities: ["word": 1]),
        ]
        var out: Answers = [:]
        for q in questions {
            let offered = answers[q.key].flatMap { a in q.options.contains { $0.name == a.choice } ? a : nil }
            out[q.key] = offered ?? q.options.first.map { Answer(choice: $0.name, probabilities: [$0.name: 1]) }
        }
        return out
    }
}
