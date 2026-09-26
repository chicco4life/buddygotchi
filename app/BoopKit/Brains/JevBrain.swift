import Foundation

/// TypeSafe's Jev, a "system one" model (HARNESS.md §7): it doesn't write, it
/// answers typed questions about a state, with probabilities
/// (https://docs.typesafe.ai/api). The situation goes as JSON state, and the
/// menu becomes questions, all in one request:
///
///     act            choice: stay_quiet | say | face | quiet   (the open tools it can fill)
///     say.feeling    choice: happy | excited | proud | …
///     say.word       choice: none | tests | build | …
///     face.name      choice: happy | proud | …
///     quiet.minutes  choice: 15 | 30 | 60 | 120
///     note           yes/no: does this call for a note?        (each open tool that needs words)
///
/// Jev answers each question on its own, so every argument is asked up front
/// and only the chosen tool's answers are used. The most likely `act` wins.
/// Writing is its own yes/no question rather than an `act`, because Jev
/// judges one small thing at a time: as an `act`, `note` never beat staying
/// quiet. On a yes, `writer` writes that one call (if it's a `Writer`; the
/// rules can't write), after Jev's own. Reflection offers nothing Jev can
/// fill, so the writer decides it alone.
public struct JevBrain: Brain {
    public let id: String
    let model: String
    let key: String
    let writer: any Brain
    /// Sends a request and returns the body and HTTP status. Tests pass their own.
    let send: @Sendable (URLRequest) async throws -> (Data, Int)

    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    public init(key: String, model: String = "jev-latest", writer: any Brain,
                send: (@Sendable (URLRequest) async throws -> (Data, Int))? = nil) {
        id = "jev:\(model)"
        self.model = model
        self.key = key
        self.writer = writer
        self.send = send ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// The first `act` option.
    static let stayQuiet = "stay_quiet"
    /// The first option of an optional argument: leave it out.
    static let none = "none"

    public func decide(_ situation: Situation, _ menu: Menu, deadline: Duration) async throws -> Decision {
        let open = menu.open.filter(JevBrain.callable)
        // Nothing Jev can choose by itself: reflection is all writing.
        guard open.contains(where: JevBrain.choosable) else { return try await writer.decide(situation, menu, deadline: deadline) }

        let body = try JSONSerialization.data(withJSONObject: [
            "model": model, "state": JevBrain.state(situation), "questions": JevBrain.questions(open),
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        var request = URLRequest(url: JevBrain.endpoint, timeoutInterval: Double(deadline.components.seconds) + 1)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, status) = try await send(request)
        // Only the status: an error body may repeat the request.
        guard status == 200 else { throw BrainError("jev: HTTP \(status)") }
        let raw = String(decoding: data, as: UTF8.self)
        guard let answers = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["answers"] as? [String: Any]
        else { throw BrainError("jev: no answers", raw: raw) }

        let chosen = JevBrain.choice(answers, "act")
        var calls: [ToolCall] = []
        if let chosen, chosen != JevBrain.stayQuiet {
            guard let tool = open.first(where: { $0.name == chosen && JevBrain.choosable($0) }) else {
                throw BrainError("jev: act \(chosen) isn't offered", raw: raw)
            }
            calls.append(try JevBrain.call(tool, answers, raw: raw))
        }
        let writes = open.filter { !JevBrain.choosable($0) && JevBrain.yes(answers, $0.name) }
        guard !writes.isEmpty, let writer = writer as? any Writer else { return Decision(calls: calls, raw: raw) }
        var written: [ToolCall] = []
        for tool in writes {
            if let call = try await writer.write(tool, situation, deadline: deadline) { written.append(call) }
        }
        return Decision(calls: calls + written, raw: raw + "\nwriter: " + Answer.json(written))
    }

    /// The chosen tool, with its arguments from their own questions.
    static func call(_ tool: ToolDefinition, _ answers: [String: Any], raw: String) throws -> ToolCall {
        var arguments: [String: ToolValue] = [:]
        for p in tool.parameters {
            guard let answer = choice(answers, tool.name + "." + p.name) else {
                throw BrainError("jev: no answer for \(tool.name).\(p.name)", raw: raw)
            }
            if answer == none, p.optional { continue }
            if case .number = p.kind, let n = Int(answer) {
                arguments[p.name] = .number(n)
            } else {
                arguments[p.name] = .string(answer)
            }
        }
        return ToolCall(tool.name, arguments)
    }

    /// A tool can be called at all: no required choice with nothing to
    /// choose from (`forget` with no lines to forget).
    static func callable(_ tool: ToolDefinition) -> Bool {
        !tool.parameters.contains { p in
            switch p.kind {
            case .choice(let options): options.isEmpty && !p.optional
            case .number(let options): options.isEmpty && !p.optional
            case .text: false
            }
        }
    }

    /// Jev can fill every argument: no free text.
    static func choosable(_ tool: ToolDefinition) -> Bool {
        !tool.parameters.contains { if case .text = $0.kind { return true } else { return false } }
    }

    /// The questions for these tools: `act`, one per argument of each tool
    /// Jev can fill, and a yes/no for each tool that needs words.
    static func questions(_ tools: [ToolDefinition]) -> [String: Any] {
        var act = [stayQuiet: "Do nothing. Often best: Boop reacts only when something really calls for it."]
        for tool in tools where choosable(tool) { act[tool.name] = tool.description }
        var questions: [String: Any] = [
            "act": ["type": "choice", "criteria": act,
                    "instructions": "What should Boop do about what just happened (now)? If the person asks for something, do that."],
        ]
        for tool in tools where !choosable(tool) {
            questions[tool.name] = [
                "type": "noul", "instructions": "Does what just happened (now) call for Boop to \(tool.name)? \(tool.description)",
                "criteria": ["true": "Yes, this is worth it now.", "false": "No, nothing here for that."],
            ]
        }
        for tool in tools where choosable(tool) {
            for p in tool.parameters {
                var options: [String]
                switch p.kind {
                case .choice(let values): options = values
                case .number(let values): options = values.map(String.init)
                case .text: continue
                }
                var criteria: [String: String] = [:]
                for option in options { criteria[option] = p.kind.isNumber ? "\(option) \(p.name)" : option }
                if p.optional { criteria[none] = "No \(p.name); leave it out." }
                questions[tool.name + "." + p.name] = [
                    "type": "choice", "criteria": criteria,
                    "instructions": "If Boop does \(tool.name) (\(tool.description)), which \(p.name) fits best?",
                ]
            }
        }
        return questions
    }

    /// What Jev judges against: who Boop is (`steering.md`), its memory, what
    /// it did lately, and what just happened.
    static func state(_ s: Situation) -> [String: Any] {
        func happened(_ t: Trigger) -> [String: Any] {
            var o: [String: Any] = ["happened": t.line]
            if let words = t.words { o["they_said"] = words }
            return o
        }
        let recent = s.recent.map { turn -> [String: Any] in
            var o = happened(turn.trigger)
            o["minutes_ago"] = max(0, (s.trigger.ts - turn.trigger.ts) / 60_000)
            o["boop_did"] = turn.did.isEmpty ? ["stayed quiet"] : turn.did.map(\.description)
            return o
        }
        var memory = ["long_term": s.memory.longTerm, "short_term": s.memory.shortTerm]
        if s.trigger.kind == .reflect { memory["short_term_yesterday"] = memory.removeValue(forKey: "short_term") }
        return ["boop": Prompt.stripComment(s.memory.steering), "memory": memory, "recent": recent, "now": happened(s.trigger)]
    }

    static func choice(_ answers: [String: Any], _ question: String) -> String? {
        (answers[question] as? [String: Any])?["choice"] as? String
    }

    /// A yes/no answer above one half.
    static func yes(_ answers: [String: Any], _ question: String) -> Bool {
        ((answers[question] as? [String: Any])?["noul"] as? NSNumber)?.doubleValue ?? 0 > 0.5
    }
}

extension ToolDefinition.Parameter.Kind {
    var isNumber: Bool { if case .number = self { true } else { false } }
}
