import Foundation

/// What Boop may do for one input (HARNESS.md §3): the outputs, in the order
/// they run, each narrowed to the choices this input allows and called at
/// most once. Stage 1 picks from it; the harness holds every answer to it.
public struct Menu: Equatable, Sendable {
    /// An output on an input's menu (`Input.menu`): plain data.
    public struct Item: Equatable, Sendable {
        public var tool: String
        /// Fewer choices for some decided arguments, e.g. `voice: [mumble]`.
        public var only: [String: [String]]

        public init(_ tool: String, only: [String: [String]] = [:]) {
            self.tool = tool
            self.only = only
        }
    }

    /// Narrowed definitions, in the order the calls run.
    public var tools: [ToolDefinition]

    public init(tools: [ToolDefinition]) {
        self.tools = tools
    }

    /// The items with the actions' definitions, in the items' order; an
    /// item no action defines is left out.
    public init(_ items: [Item], definitions: [ToolDefinition]) {
        self.init(tools: items.compactMap { item in
            definitions.first { $0.name == item.tool }.map { $0.narrowed(item.only) }
        })
    }

    public func definition(_ tool: String) -> ToolDefinition? { tools.first { $0.name == tool } }

    /// Why Stage 1's calls don't fit (HARNESS.md §3 step 4), or nil: only
    /// tools on the menu, decided arguments from their choices and no written
    /// ones, and at most one call to a tool. One bad call drops them all.
    public func check(_ calls: [ToolCall]) -> String? {
        var seen: Set<String> = []
        for call in calls {
            guard let d = definition(call.name) else { return "\(call.name) isn't on the menu" }
            if let why = d.checkDecided(call.arguments) { return "\(call.name): \(why)" }
            if !seen.insert(call.name).inserted { return "\(call.name) twice" }
        }
        return nil
    }

    /// The calls in the menu's order.
    public func ordered(_ calls: [ToolCall]) -> [ToolCall] {
        let rank = Dictionary(uniqueKeysWithValues: tools.enumerated().map { ($1.name, $0) })
        return calls.sorted { (rank[$0.name] ?? 0) < (rank[$1.name] ?? 0) }
    }

    /// What Stage 2 has to write for these calls: each written argument whose
    /// condition holds.
    public func slots(_ calls: [ToolCall]) -> [Slot] {
        var slots: [Slot] = []
        for (index, call) in calls.enumerated() {
            guard let d = definition(call.name) else { continue }
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
                slots.append(Slot(key: call.name + "." + p.name, call: index, decided: call, parameter: p.name,
                                  kind: kind, optional: p.optional, about: d.description, choice: Slot.chosen(call, d),
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

    /// `react.word`, `remember.text`.
    public var key: String
    /// Which of the pass's calls it belongs to.
    public var call: Int
    public var decided: ToolCall
    public var parameter: String
    public var kind: Kind
    public var optional: Bool
    /// The output's description.
    public var about: String
    /// What the decided choices mean, e.g. `where: about_you` → "Long-term: a durable fact…".
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
