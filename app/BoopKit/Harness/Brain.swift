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
    /// scripted`): every pass, an excited mumble with "yay", its face held
    /// once, and the mood happy; a cheer in it when NOW is a turn finished
    /// done, since no rule cheers (BEHAVIORS.md §3.1).
    public static let pipelineCheck = ScriptedBrain(id: "scripted") { state, questions in
        let now = state.components(separatedBy: "\nNOW (").last ?? ""
        let finished = now.contains(" finished turn ") && now.contains(": done, a ")
        let answers: Answers = [
            "mood": Answer(choice: "happy", probabilities: ["happy": 1]),
            "react.mood": Answer(choice: "excited", probabilities: ["excited": 1]),
            "react.animation": finished ? Answer(choice: "cheer", probabilities: ["cheer": 1])
                : Answer(choice: "none", probabilities: ["none": 1]),
            "react.loops": Answer(choice: "once", probabilities: ["once": 1]),
            "word.feeling": Answer(choice: "yay", probabilities: ["yay": 1]),
            "word.about": Answer(choice: "none", probabilities: ["none": 1]),
        ]
        var out: Answers = [:]
        for q in questions { out[q.key] = answers[q.key] ?? q.options.first.map { Answer(choice: $0.name, probabilities: [$0.name: 1]) } }
        return out
    }
}
