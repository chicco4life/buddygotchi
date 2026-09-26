import Foundation

/// What Boop may do for one input (HARNESS.md §3): the outputs, in the order
/// they run, each narrowed to the choices this input allows, and how many
/// calls each may take. Stage 1 picks from it; the harness holds every
/// answer to it.
public struct Menu: Equatable, Sendable {
    /// An output on an input's menu (`Input.Kind.menu`): plain data.
    public struct Item: Equatable, Sendable {
        public var tool: String
        /// Fewer choices for some decided arguments, e.g. `where: [today]`.
        public var only: [String: [String]]
        /// At most this many calls to the tool for one input, never two alike.
        public var max: Int

        public init(_ tool: String, only: [String: [String]] = [:], max: Int = 1) {
            self.tool = tool
            self.only = only
            self.max = max
        }
    }

    /// Narrowed definitions, in the order the calls run.
    public var tools: [ToolDefinition]
    public var max: [String: Int]

    public init(tools: [ToolDefinition], max: [String: Int] = [:]) {
        self.tools = tools
        self.max = max
    }

    /// The items with the actions' definitions, in the items' order; an
    /// item no action defines is left out.
    public init(_ items: [Item], definitions: [ToolDefinition]) {
        var tools: [ToolDefinition] = []
        var max: [String: Int] = [:]
        for item in items {
            guard let d = definitions.first(where: { $0.name == item.tool }) else { continue }
            tools.append(d.narrowed(item.only))
            max[item.tool] = item.max
        }
        self.init(tools: tools, max: max)
    }

    public func definition(_ tool: String) -> ToolDefinition? { tools.first { $0.name == tool } }

    /// Why Stage 1's calls don't fit (HARNESS.md §3 step 4), or nil: only
    /// tools on the menu, decided arguments from their choices and no written
    /// ones, at most `max` calls to a tool, and never the same call twice.
    /// One bad call drops them all.
    public func check(_ calls: [ToolCall]) -> String? {
        var seen: [ToolCall] = []
        for call in calls {
            guard let d = definition(call.name) else { return "\(call.name) isn't on the menu" }
            if let why = d.checkDecided(call.arguments) { return "\(call.name): \(why)" }
            if seen.contains(call) { return "\(call.name) twice" }
            if seen.filter({ $0.name == call.name }).count >= (max[call.name] ?? 1) {
                return "more than \(max[call.name] ?? 1) \(call.name)"
            }
            seen.append(call)
        }
        return nil
    }

    /// The calls in the menu's order; calls to one tool keep theirs.
    public func ordered(_ calls: [ToolCall]) -> [ToolCall] {
        let rank = Dictionary(uniqueKeysWithValues: tools.enumerated().map { ($1.name, $0) })
        return calls.enumerated().sorted { (rank[$0.1.name] ?? 0, $0.0) < (rank[$1.1.name] ?? 0, $1.0) }.map(\.1)
    }

    /// What Stage 2 has to write for these calls: each written argument whose
    /// condition holds.
    public func slots(_ calls: [ToolCall]) -> [Slot] {
        var slots: [Slot] = []
        for (index, call) in calls.enumerated() {
            guard let d = definition(call.name) else { continue }
            let repeats = calls.filter { $0.name == call.name }.count > 1
            let nth = calls[...index].filter { $0.name == call.name }.count
            for p in d.parameters {
                switch p.role {
                case .decided: continue
                case .written: break
                case .writtenWhen(let name, let value): if call.arguments[name]?.string != value { continue }
                }
                let kind: Slot.Kind
                switch p.kind {
                case .choice(let options): kind = .word(options)
                case .number(let options): kind = .word(options.map(String.init))
                case .text: kind = .text(maxLength: p.maxLength(call.arguments) ?? 0)
                }
                let key = call.name + (repeats ? "#\(nth)" : "") + "." + p.name
                slots.append(Slot(key: key, call: index, decided: call, parameter: p.name, kind: kind,
                                  optional: p.optional, about: d.description, choice: Slot.chosen(call, d),
                                  sources: p.sources))
            }
        }
        return slots
    }
}

/// One thing for Stage 2 to write: an argument of a decided call.
public struct Slot: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// One of these, or `none` when the slot is optional.
        case word([String])
        /// Plain text, at most this many characters.
        case text(maxLength: Int)
    }

    /// `react.word`, `remember.text`, or `remember#2.text` when a tool is called twice.
    public var key: String
    /// Which of the pass's calls it belongs to.
    public var call: Int
    public var decided: ToolCall
    public var parameter: String
    public var kind: Kind
    public var optional: Bool
    /// The output's description.
    public var about: String
    /// What the decided choices mean, e.g. `where: today` → "A note for later today…".
    public var choice: String?
    /// What the value can come from, for a model writer to pick first
    /// (`ToolDefinition.Parameter.sources`); empty for most.
    public var sources: [String] = []

    /// The meaning of the call's first decided choice that has one.
    static func chosen(_ call: ToolCall, _ d: ToolDefinition) -> String? {
        for p in d.parameters where p.decided {
            if let v = call.arguments[p.name]?.string, let about = p.about[v] { return about }
        }
        return nil
    }

    /// The value to use, or nil to leave it empty: `none`, blank and anything
    /// that doesn't fit count as empty.
    public func value(_ raw: String?) -> String? {
        let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch kind {
        case .word(let options):
            return options.contains(v) ? v : nil
        case .text(let max):
            return v.isEmpty || v.lowercased() == "none" || v.count > max ? nil : v
        }
    }
}
