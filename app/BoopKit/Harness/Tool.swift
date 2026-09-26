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
    /// shape check and every action use this same check. The reason names
    /// the argument but never repeats its value, since it's logged.
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
                guard let s = value.string, options.contains(s) else { return "\(p.name) isn't one of its choices" }
            case .number(let options):
                guard let n = value.number, options.contains(n) else { return "\(p.name) isn't one of its choices" }
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

/// How often one tool may run for one kind of trigger (HARNESS.md §5). Plain
/// data: the harness doesn't know what the tool does, only when it last ran.
public struct ToolLimit: Equatable, Sendable {
    public var tool: String
    /// At least this long between two runs that went through, in ms.
    public var everyMs: Int64
    /// Never offered when the trigger's line starts with one of these.
    public var neverOn: [String]

    public init(_ tool: String, everyMs: Int64, neverOn: [String] = []) {
        self.tool = tool
        self.everyMs = everyMs
        self.neverOn = neverOn
    }
}

/// When each limited tool last ran, per trigger kind, on the triggers' own
/// clock. Shared by whoever needs one history across harnesses (`boopdev
/// brain`). Touched only on the harness's queue.
public final class ToolLimits: @unchecked Sendable {
    var last: [String: Int64] = [:]

    public init() {}

    /// Why `tool` can't run for this trigger, as the line the prompt shows
    /// (`say limit: once every 5 min on tap, next in 3 min`), or nil if it
    /// can. A call past its limit is dropped with the same line.
    public func blocked(_ tool: String, for trigger: Trigger) -> String? {
        if !trigger.kind.tools.contains(tool) {
            let kinds = Trigger.Kind.allCases.filter { $0.converses && $0.tools.contains(tool) }.map(\.rawValue)
            return "\(tool) limit: " + (kinds.isEmpty ? "not on \(trigger.kind.rawValue)" : "only on " + kinds.joined(separator: " or "))
        }
        guard let limit = trigger.kind.limits.first(where: { $0.tool == tool }) else { return nil }
        if let start = limit.neverOn.first(where: { trigger.line.hasPrefix($0) }) {
            return "\(tool) limit: not on \(start)"
        }
        if let at = last[key(tool, trigger.kind)], trigger.ts - at < limit.everyMs {
            let left = (limit.everyMs - (trigger.ts - at) + 59_999) / 60_000
            return "\(tool) limit: once every \(limit.everyMs / 60_000) min on \(trigger.kind.rawValue), next in \(left) min"
        }
        return nil
    }

    /// A call to `tool` went through for this trigger.
    public func ran(_ tool: String, for trigger: Trigger) {
        guard trigger.kind.limits.contains(where: { $0.tool == tool }) else { return }
        last[key(tool, trigger.kind)] = trigger.ts
    }

    func key(_ tool: String, _ kind: Trigger.Kind) -> String { kind.rawValue + "/" + tool }
}
