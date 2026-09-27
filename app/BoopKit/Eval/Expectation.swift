import Foundation

/// One pass as a scenario expects it (EVALS.md §3), parsed from its line:
/// `agent finished → react(feeling: proud, word: finally|done|yay)`.
///
/// An argument's value lists every value that fits, split by `|`; `none`
/// among them lets the argument be left out, and `*` stands for any run of
/// characters (`text: "*Thursday*"`), matched without regard to case. With
/// no writer, the arguments a writer fills aren't checked, and a call that
/// needs one is expected dropped (unwritten), as the harness drops it, so
/// one line holds for every writer.
public struct Expectation: Equatable, Sendable {
    public struct Call: Equatable, Sendable {
        public var name: String
        /// The values that fit, by argument.
        public var arguments: [String: [String]]
        /// `unwritten` or `action`, when the call should be dropped.
        public var dropped: String?
    }

    public enum Answer: Equatable, Sendable {
        /// One of the core's rule reactions, as `Eval.describe` writes it:
        /// `rules → cheer`. Only in a scenario that records them.
        case rule(String)
        case nothing
        /// The whole pass: `off menu`, `error`, `refused`, `late` or `cancelled`.
        case dropped(String)
        case calls([Call])
    }

    /// As the scenario wrote it.
    public var line: String
    /// The input's kind, e.g. `agent finished`.
    public var input: String
    public var answer: Answer
    /// `error`, `refused` or `late`, when Stage 2 should fail.
    public var writerFailed: String?

    public init(_ line: String) throws {
        func bad(_ why: String) -> Error { EvalError("\"\(line)\": \(why)") }
        self.line = line
        guard let arrow = line.range(of: " → ") else { throw bad("needs an input, then → and what happened") }
        input = String(line[..<arrow.lowerBound])
        var rest = String(line[arrow.upperBound...])
        if input == "rules" {
            answer = .rule(line)
            return
        }
        guard Input.Kind(rawValue: input) != nil else { throw bad("\(input) isn't an input") }
        if let failed = rest.range(of: " · writer failed (", options: .backwards), rest.hasSuffix(")") {
            writerFailed = String(rest[failed.upperBound..<rest.index(before: rest.endIndex)])
            rest = String(rest[..<failed.lowerBound])
        }
        if rest == "nothing" {
            answer = .nothing
        } else if rest.hasPrefix("dropped ("), rest.hasSuffix(")") {
            answer = .dropped(String(rest.dropFirst("dropped (".count).dropLast()))
        } else {
            answer = .calls(try Expectation.calls(rest, bad: bad))
        }
    }

    /// `react(feeling: sad), remember(where: today) dropped (unwritten)`.
    static func calls(_ text: String, bad: (String) -> Error) throws -> [Call] {
        var calls: [Call] = []
        var s = Substring(text)
        while !s.isEmpty {
            guard let open = s.firstIndex(of: "(") else { throw bad("a call is name(arguments)") }
            let name = s[..<open].trimmingCharacters(in: .whitespaces)
            var i = s.index(after: open)
            var quoted = false
            var close: Substring.Index?
            while i < s.endIndex {
                if s[i] == "\"" { quoted.toggle() } else if s[i] == ")", !quoted { close = i; break }
                i = s.index(after: i)
            }
            guard let close else { throw bad("\(name)( isn't closed") }
            let arguments = try Expectation.arguments(s[s.index(after: open)..<close], bad: bad)
            s = s[s.index(after: close)...]
            var dropped: String?
            if s.hasPrefix(" dropped (") {
                guard let end = s.firstIndex(of: ")") else { throw bad("dropped ( isn't closed") }
                dropped = String(s[s.index(s.startIndex, offsetBy: " dropped (".count)..<end])
                s = s[s.index(after: end)...]
            }
            calls.append(Call(name: name, arguments: arguments, dropped: dropped))
            if s.hasPrefix(", ") {
                s = s.dropFirst(2)
            } else if !s.isEmpty {
                throw bad("calls are separated by \", \"")
            }
        }
        return calls
    }

    /// `feeling: proud, text: "demo, Thursday"` → the values that fit, by name.
    static func arguments(_ text: Substring, bad: (String) -> Error) throws -> [String: [String]] {
        var parts: [String] = []
        var part = ""
        var quoted = false
        for c in text {
            if c == "\"" { quoted.toggle() }
            if c == ",", !quoted {
                parts.append(part)
                part = ""
            } else {
                part.append(c)
            }
        }
        if !part.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(part) }
        var arguments: [String: [String]] = [:]
        for part in parts {
            guard let colon = part.firstIndex(of: ":") else { throw bad("an argument is name: value") }
            let name = part[..<colon].trimmingCharacters(in: .whitespaces)
            var value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            arguments[name] = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        }
        return arguments
    }

    /// Whether a pass fits. `writing` is false when nothing writes for it
    /// (no writer, and nothing scripted); `definitions` say which arguments
    /// are the writer's.
    public func matches(_ record: Harness.Record, writing: Bool, definitions: [ToolDefinition]) -> Bool {
        guard record.input.kind.rawValue == input, record.writeFailed.map(Eval.why) == writerFailed else { return false }
        switch answer {
        case .rule:
            return false
        case .dropped(let why):
            return record.dropped.map(Eval.why) == why
        case .nothing:
            return record.dropped == nil && record.ran.isEmpty
        case .calls(let calls):
            guard record.dropped == nil, record.ran.count == calls.count else { return false }
            return zip(calls, record.ran).allSatisfy { expected, ran in
                expected.matches(ran.call, ran.outcome, writing: writing,
                                 definition: definitions.first { $0.name == ran.call.name })
            }
        }
    }

    /// `*` for any run of characters, without regard to case.
    static func fits(_ pattern: String, _ value: String) -> Bool {
        let regex = "^" + pattern.components(separatedBy: "*").map(NSRegularExpression.escapedPattern).joined(separator: ".*") + "$"
        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Expectation.Call {
    func matches(_ call: ToolCall, _ outcome: ActionOutcome, writing: Bool, definition: ToolDefinition?) -> Bool {
        guard call.name == name else { return false }
        var expected = arguments
        var dropped = self.dropped
        if !writing, let definition {
            for p in definition.parameters where !p.decided {
                expected[p.name] = nil
                if !p.optional { dropped = "unwritten" }
            }
        }
        let actual: String? = switch outcome {
        case .done: nil
        case .dropped(let why): why == Harness.unwritten ? "unwritten" : "action"
        }
        guard actual == dropped else { return false }
        for key in Set(expected.keys).union(call.arguments.keys) {
            guard let fit = expected[key] else { return false }
            switch call.arguments[key] {
            case nil: guard fit.contains("none") else { return false }
            case .string(let s): guard fit.contains(where: { Expectation.fits($0, s) }) else { return false }
            case .number(let n): guard fit.contains(String(n)) else { return false }
            }
        }
        return true
    }
}
