import Foundation

/// An output as the brain sees it (HARNESS.md §5). Each action writes its
/// own; the harness checks calls against it, and each argument's role says
/// which stage fills it in.
public struct ToolDefinition: Equatable, Sendable {
    public struct Parameter: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// One of these strings.
            case choice([String])
            /// One of these numbers.
            case number([Int])
            /// Free text, at most `maxLength` characters, or less when the
            /// choice parameter `by` has a value in `limits` (`remember`'s
            /// `where`).
            case text(maxLength: Int, by: String? = nil, limits: [String: Int] = [:])
        }

        /// Which stage fills it in (HARNESS.md §3).
        public enum Role: Equatable, Sendable {
            /// Stage 1, the classifier, from its choices.
            case decided
            /// Stage 2, the writer.
            case written
        }

        public var name: String
        public var kind: Kind
        public var optional: Bool
        public var role: Role
        /// What each choice means, for a brain that needs it spelled out (Jev).
        public var about: [String: String]
        /// For a decided argument: the question a model classifier asks to
        /// pick it, in plain words (Jev).
        public var question: String?
        /// For a written argument: what its value can come from, in the
        /// order to try. A model writer picks one of these first, then the
        /// value (HARNESS.md §7): `react`'s word comes from what the person
        /// said, what an agent failed at, how a turn went, or the feeling.
        public var sources: [String]

        public init(_ name: String, _ kind: Kind, optional: Bool = false, role: Role = .decided,
                    about: [String: String] = [:], question: String? = nil, sources: [String] = []) {
            self.name = name
            self.kind = kind
            self.optional = optional
            self.role = role
            self.about = about
            self.question = question
            self.sources = sources
        }

        public var decided: Bool { role == .decided }

        /// The text limit, given the call's other arguments.
        public func maxLength(_ arguments: [String: ToolValue]) -> Int? {
            guard case .text(let max, let by, let limits) = kind else { return nil }
            return by.flatMap { arguments[$0]?.string }.flatMap { limits[$0] } ?? max
        }
    }

    public var name: String
    public var description: String
    /// The yes/no a model classifier asks about calling it, in plain words
    /// (Jev): "Does what just happened call for Boop to react?"
    public var question: String?
    public var parameters: [Parameter]

    public init(name: String, description: String, question: String? = nil, parameters: [Parameter]) {
        self.name = name
        self.description = description
        self.question = question
        self.parameters = parameters
    }

    /// Why these arguments don't fit, or nil if they do: every required one
    /// present, no unknown ones, choices and lengths respected. The harness
    /// and every action use this same check. The reason names the argument
    /// but never repeats its value, since it's logged.
    public func check(_ arguments: [String: ToolValue]) -> String? {
        for key in arguments.keys.sorted() where !parameters.contains(where: { $0.name == key }) {
            return "unknown argument \(key)"
        }
        for p in parameters {
            guard let value = arguments[p.name] else {
                if p.optional { continue }
                return "\(p.name) is missing"
            }
            if let why = Self.check(value, p, arguments) { return why }
        }
        return nil
    }

    /// Stage 1's arguments only (HARNESS.md §3 step 4): every decided one
    /// present and from its choices, and no written ones.
    public func checkDecided(_ arguments: [String: ToolValue]) -> String? {
        for key in arguments.keys.sorted() {
            guard let p = parameters.first(where: { $0.name == key }) else { return "unknown argument \(key)" }
            if !p.decided { return "\(key) is the writer's" }
        }
        for p in parameters where p.decided {
            guard let value = arguments[p.name] else {
                if p.optional { continue }
                return "\(p.name) is missing"
            }
            if let why = Self.check(value, p, arguments) { return why }
        }
        return nil
    }

    static func check(_ value: ToolValue, _ p: Parameter, _ arguments: [String: ToolValue]) -> String? {
        switch p.kind {
        case .choice(let options):
            guard let s = value.string, options.contains(s) else { return "\(p.name) isn't one of its choices" }
        case .number(let options):
            guard let n = value.number, options.contains(n) else { return "\(p.name) isn't one of its choices" }
        case .text:
            guard let s = value.string else { return "\(p.name) isn't text" }
            let max = p.maxLength(arguments) ?? 0
            if s.count > max { return "\(p.name) is longer than \(max) characters" }
        }
        return nil
    }
}

/// An argument value in a tool call.
public enum ToolValue: Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Int)

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var number: Int? {
        switch self {
        case .number(let n): n
        case .string(let s): Int(s)
        }
    }

    public var description: String {
        switch self {
        case .string(let s): "\"\(s)\""
        case .number(let n): String(n)
        }
    }

    /// Without quotes unless it has a space: `proud`, `"demo on Thursday"`.
    public var plain: String {
        switch self {
        case .string(let s): s.contains(" ") || s.isEmpty ? "\"\(s)\"" : s
        case .number(let n): String(n)
        }
    }
}

/// One call to an output, from a classifier, a writer or a rule.
public struct ToolCall: Equatable, Sendable, CustomStringConvertible {
    public var name: String
    public var arguments: [String: ToolValue]

    public init(_ name: String, _ arguments: [String: ToolValue] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    /// `react(feeling: "proud", word: "yay")`.
    public var description: String {
        name + "(" + arguments.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + ")"
    }

    /// `react(feeling: proud, word: yay)`, for a model to read.
    public var plain: String {
        name + "(" + arguments.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.plain)" }.joined(separator: ", ") + ")"
    }
}
