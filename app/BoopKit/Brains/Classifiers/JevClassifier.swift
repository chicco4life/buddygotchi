import Foundation

/// TypeSafe's Jev as the classifier (Stage 1, HARNESS.md §6), a "system one"
/// model: it doesn't write, it answers typed questions about a state with
/// probabilities, all in one request of about 0.2 s
/// (https://docs.typesafe.ai/api). Needs the person's API key.
///
/// The state is the pass as JSON: `steering.md` without its Writing
/// section (Jev never writes), both memory files, the window's recent
/// inputs (minutes ago, what happened, what they said, what the rules did
/// and what Boop did) and now. The menu becomes questions, built from the
/// outputs' own definitions, so nothing here knows what an output does:
///
///     react              yes/no: the definition's question
///     react.feeling      choice: happy | excited | proud | …   (a decided argument
///     react.voice        choice: silent | mumble                 with more than one option)
///     remember.moment    yes/no, one per choice, when the menu allows several calls
///                        told apart by it (a new day's `where`)
///
/// As TypeSafe advises for Jev, each question names the part of the state
/// it's about (`now`) and what to judge it by (`boop`, its Examples first),
/// and a yes means `boop` says to do it for something like `now`; anything
/// that needs arithmetic, like how long a turn took, arrives already named.
/// Jev answers each question on its own, so every argument is asked up front
/// and only a chosen output's answers are used. A yes is above 0.5; each
/// choice is Jev's most likely one. The answers go in the transcript as
/// evidence. Only the HTTP status of a failed request is logged.
public struct JevClassifier: Classifier {
    public let id: String
    let model: String
    let key: String
    /// Sends a request and returns the body and HTTP status. Tests pass their own.
    let send: @Sendable (URLRequest) async throws -> (Data, Int)

    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    public init(key: String, model: String = "jev-latest", send: (@Sendable (URLRequest) async throws -> (Data, Int))? = nil) {
        id = "jev:\(model)"
        self.model = model
        self.key = key
        self.send = send ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// The first option of an optional argument: leave it out.
    static let none = "none"

    /// A busy or failing server, or a dropped connection, is tried once more
    /// after this, as TypeSafe advises for 429 and 529 (HARNESS.md §6). The
    /// input's deadline still bounds the whole pass.
    static let retryAfterMs = 300

    static func retryable(_ status: Int) -> Bool { status == 429 || status >= 500 }

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": model, "state": JevClassifier.state(context), "questions": JevClassifier.questions(menu),
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        var request = URLRequest(url: JevClassifier.endpoint, timeoutInterval: Double(deadline.components.seconds) + 1)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        var (data, status) = try await sendOnce(request)
        if JevClassifier.retryable(status) {
            try await Task.sleep(for: .milliseconds(JevClassifier.retryAfterMs))
            (data, status) = try await send(request)
        }
        // Only the status: an error body may repeat the request.
        guard status == 200 else { throw BrainError("jev: HTTP \(status)") }
        let raw = String(decoding: data, as: UTF8.self)
        guard let answers = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["answers"] as? [String: Any]
        else { throw BrainError("jev: no answers", raw: raw) }
        return Classification(calls: try JevClassifier.calls(menu, answers), evidence: JevClassifier.evidence(answers))
    }

    /// Sends the request; a connection that failed (not one that timed out)
    /// reads as a 503, so it's tried again.
    func sendOnce(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await send(request)
        } catch let error as URLError where error.code != .timedOut && error.code != .cancelled {
            return (Data(), 503)
        }
    }

    // MARK: Questions

    /// The decided choice argument that tells several calls to one tool
    /// apart, when the menu allows more than one (`where` on a new day).
    static func split(_ tool: ToolDefinition, _ menu: Menu) -> ToolDefinition.Parameter? {
        guard (menu.max[tool.name] ?? 1) > 1 else { return nil }
        return tool.parameters.first { p in
            if p.decided, case .choice(let options) = p.kind { return options.count > 1 }
            return false
        }
    }

    /// The options of a decided argument, as Jev's criteria.
    static func criteria(_ p: ToolDefinition.Parameter) -> [String: String] {
        var criteria: [String: String] = [:]
        switch p.kind {
        case .choice(let options): for o in options { criteria[o] = p.about[o] ?? o }
        case .number(let options): for n in options { criteria[String(n)] = p.about[String(n)] ?? "\(n) \(p.name)" }
        case .text: break
        }
        if p.optional { criteria[none] = "No \(p.name); leave it out." }
        return criteria
    }

    /// What a yes and a no mean, for every yes/no.
    static let yesNo = ["true": "Yes: `boop` says to do this for something like `now`.",
                        "false": "No: `boop` says to do nothing, or something else, for something like `now`."]

    /// A question with what it's about and what to judge it by.
    static func instructions(_ question: String, _ more: [String: String] = [:]) -> [String: String] {
        ["question": question, "about": "`now`", "judge_by": "`boop`, its Examples first"].merging(more) { $1 }
    }

    static func questions(_ menu: Menu) -> [String: Any] {
        var questions: [String: Any] = [:]
        for tool in menu.tools {
            let split = split(tool, menu)
            let ask = tool.question ?? "Should Boop \(tool.name) now? \(tool.description)"
            if let split, case .choice(let options) = split.kind {
                for option in options {
                    questions[tool.name + "." + option] = [
                        "type": "noul", "criteria": yesNo,
                        "instructions": instructions(ask, [split.name: split.about[option] ?? option]),
                    ]
                }
            } else {
                questions[tool.name] = ["type": "noul", "criteria": yesNo, "instructions": instructions(ask)]
            }
            for p in tool.parameters where p.decided && p != split {
                let criteria = criteria(p)
                guard criteria.count > 1 else { continue }
                questions[tool.name + "." + p.name] = [
                    "type": "choice", "criteria": criteria,
                    "instructions": instructions(p.question ?? "If Boop does \(tool.name), which \(p.name) fits best?"),
                ]
            }
        }
        return questions
    }

    // MARK: Answers

    static func calls(_ menu: Menu, _ answers: [String: Any]) throws -> [ToolCall] {
        var calls: [ToolCall] = []
        for tool in menu.tools {
            let split = split(tool, menu)
            var picks: [[String: ToolValue]] = []
            if let split, case .choice(let options) = split.kind {
                for option in options where yes(answers, tool.name + "." + option) {
                    picks.append([split.name: .string(option)])
                }
            } else if yes(answers, tool.name) {
                picks.append([:])
            }
            for var arguments in picks {
                for p in tool.parameters where p.decided && p != split {
                    let options = criteria(p).keys.sorted()
                    let answer = options.count == 1 ? options[0] : choice(answers, tool.name + "." + p.name)
                    guard let answer else { throw BrainError("jev: no answer for \(tool.name).\(p.name)") }
                    if answer == none && p.optional { continue }
                    if case .number = p.kind, let n = Int(answer) {
                        arguments[p.name] = .number(n)
                    } else {
                        arguments[p.name] = .string(answer)
                    }
                }
                calls.append(ToolCall(tool.name, arguments))
            }
        }
        return calls
    }

    static func choice(_ answers: [String: Any], _ question: String) -> String? {
        (answers[question] as? [String: Any])?["choice"] as? String
    }

    /// A yes/no answer above one half.
    static func yes(_ answers: [String: Any], _ question: String) -> Bool {
        ((answers[question] as? [String: Any])?["noul"] as? NSNumber)?.doubleValue ?? 0 > 0.5
    }

    /// The answers in short, for the transcript: `react 0.71 · react.feeling proud 0.62`.
    static func evidence(_ answers: [String: Any]) -> String {
        answers.keys.sorted().compactMap { key -> String? in
            guard let a = answers[key] as? [String: Any] else { return nil }
            if let n = (a["noul"] as? NSNumber)?.doubleValue { return "\(key) \(String(format: "%.2f", n))" }
            if let c = a["choice"] as? String {
                let p = ((a["probabilities"] as? [String: Any])?[c] as? NSNumber)?.doubleValue
                return "\(key) \(c)" + (p.map { String(format: " %.2f", $0) } ?? "")
            }
            return nil
        }.joined(separator: " · ")
    }

    // MARK: State

    /// What Jev judges against: who Boop is, its memory, what happened lately
    /// and what just happened.
    static func state(_ context: Context) -> [String: Any] {
        let input = context.input
        var groups = Transcript.groups(context.window)
        // The last input is this one: it's `now`.
        if let last = groups.indices.last(where: { groups[$0].did != nil }) { groups.remove(at: last) }
        let recent = groups.map { g -> [String: Any] in
            var o: [String: Any] = ["minutes_ago": max(0, (input.ts - g.ts) / 60_000), "happened": g.happened]
            if let words = g.words { o["they_said"] = words }
            if let rules = g.rules { o["rules"] = rules }
            if let did = g.did { o["boop_did"] = did.isEmpty ? ["nothing"] : did.map(\.plain) }
            return o
        }
        var now: [String: Any] = ["happened": input.line]
        if let words = input.words { now["they_said"] = words }
        if let rules = input.rules { now["rules"] = rules }
        var memory = ["long_term": context.memory.longTerm, "short_term": context.memory.shortTerm]
        if input.kind == .newDay { memory["short_term_yesterday"] = memory.removeValue(forKey: "short_term") }
        return ["boop": JevClassifier.boop(context.memory.steering), "memory": memory, "recent": recent, "now": now]
    }

    /// `steering.md` for Jev: without its maintainers' note, and without
    /// its Writing section, which is only the writer's. Unrelated text costs
    /// Jev accuracy (TypeSafe's "context rot").
    static func boop(_ steering: String) -> String {
        let text = Prompt.stripComment(steering)
        guard let start = text.range(of: "\n## Writing\n") else { return text }
        let end = text.range(of: "\n## ", range: start.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let before = text[..<start.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text[end...].trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? before : before + "\n\n" + after
    }
}
