import Foundation

/// The part of a tool the brain sees (HARNESS.md §6). Each action writes its
/// own; the harness only checks answers against it.
public struct ToolDefinition: Equatable, Sendable {
    public struct Parameter: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// One of these strings.
            case choice([String])
            /// One of these numbers.
            case number([Int])
            /// Free text, at most this many characters.
            case text(maxLength: Int)
        }

        public var name: String
        public var kind: Kind
        public var optional: Bool

        public init(_ name: String, _ kind: Kind, optional: Bool = false) {
            self.name = name
            self.kind = kind
            self.optional = optional
        }
    }

    public var name: String
    public var description: String
    public var parameters: [Parameter]

    public init(name: String, description: String, parameters: [Parameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Why these arguments don't fit, or nil if they do: every required one
    /// present, no unknown ones, choices and lengths respected. The harness's
    /// shape check and every action use this same check.
    public func check(_ arguments: [String: ToolValue]) -> String? {
        for key in arguments.keys.sorted() where !parameters.contains(where: { $0.name == key }) {
            return "unknown argument \(key)"
        }
        for p in parameters {
            guard let value = arguments[p.name] else {
                if p.optional { continue }
                return "\(p.name) is missing"
            }
            switch p.kind {
            case .choice(let options):
                guard let s = value.string, options.contains(s) else { return "\(p.name) \(value) isn't one of its choices" }
            case .number(let options):
                guard let n = value.number, options.contains(n) else { return "\(p.name) \(value) isn't one of its choices" }
            case .text(let max):
                guard let s = value.string else { return "\(p.name) isn't text" }
                if s.count > max { return "\(p.name) is longer than \(max) characters" }
            }
        }
        return nil
    }

    /// `{"name":…,"description":…,"parameters":{…}}`, parameters in order.
    public var json: String {
        func quote(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }
        let params = parameters.map { p -> String in
            var fields: [String]
            switch p.kind {
            case .choice(let values): fields = ["\"enum\":[" + values.map(quote).joined(separator: ",") + "]"]
            case .number(let values): fields = ["\"enum\":[" + values.map(String.init).joined(separator: ",") + "]"]
            case .text(let max): fields = ["\"type\":\"string\"", "\"maxLength\":\(max)"]
            }
            if p.optional { fields.append("\"optional\":true") }
            return quote(p.name) + ":{" + fields.joined(separator: ",") + "}"
        }
        return "{\"name\":\(quote(name)),\"description\":\(quote(description)),\"parameters\":{"
            + params.joined(separator: ",") + "}}"
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
}

/// One tool call from the brain, or from a rule.
public struct ToolCall: Equatable, Sendable, CustomStringConvertible {
    public var name: String
    public var arguments: [String: ToolValue]

    public init(_ name: String, _ arguments: [String: ToolValue] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    /// `say(feeling: proud, word: finally)`.
    public var description: String {
        name + "(" + arguments.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + ")"
    }
}
