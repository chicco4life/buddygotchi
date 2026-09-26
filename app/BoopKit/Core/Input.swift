import Foundation

/// One of the four things that reach the brain's pipeline (HARNESS.md §2),
/// typed. The core builds them; classifiers read their fields, and language
/// models read `line`. Taps and "needs you" never become inputs: the rules
/// handle them, and the transcript only notes them.
public struct Input: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case agentStarted = "agent started"
        case agentFinished = "agent finished"
        case said = "you said"
        case newDay = "new day"

        /// Milliseconds for both stages; a later answer is dropped.
        public var deadlineMs: Int {
            switch self {
            case .agentStarted, .agentFinished: 5000
            case .said: 4000
            case .newDay: 600_000
            }
        }

        /// What Boop may do for this input, in the order it's done
        /// (HARNESS.md §3). Plain data: the harness doesn't know what the
        /// tools do.
        public var menu: [Menu.Item] {
            switch self {
            case .agentStarted, .agentFinished:
                [Menu.Item("react")]
            case .said:
                [Menu.Item("quiet"), Menu.Item("react"), Menu.Item("remember", only: ["where": ["today"]])]
            case .newDay:
                [Menu.Item("remember", only: ["where": ["about_you", "preference", "temperament", "moment"]], max: 4)]
            }
        }
    }

    public enum Outcome: String, Sendable { case done, failed }

    public var kind: Kind
    /// `claude` or `codex`, for agent inputs.
    public var agent: String?
    public var project: String?
    /// Agent finished: how the turn ended.
    public var outcome: Outcome?
    /// The session's latest topic (`tests`, `build`, `deploy`, `docs`), for a finish.
    public var topic: String?
    /// How long the turn took, for a finish.
    public var tookMs: Int64?
    /// A failed turn's error class, e.g. `rate_limit` (ADAPTERS.md §2).
    public var error: String?
    /// How many other agent inputs a 3 s burst merged into this one.
    public var more = 0
    /// You said: your words, at most `maxWords` characters.
    public var words: String?
    /// New day: the day to reflect on, `yyyy-MM-dd`.
    public var yesterday: String?
    /// `14:05`, and `Tuesday`.
    public var clock: String
    public var weekday: String
    public var hunger: Growth.Hunger
    /// What the rules already did about it, e.g. `cheer size 2`, for the transcript.
    public var rules: String?
    public var ts: Int64

    /// Your words are cut to this, about 30 s of speech.
    public static let maxWords = 500

    public init(_ kind: Kind, agent: String? = nil, project: String? = nil, outcome: Outcome? = nil,
                topic: String? = nil, tookMs: Int64? = nil, error: String? = nil, more: Int = 0,
                words: String? = nil, yesterday: String? = nil, clock: String, weekday: String,
                hunger: Growth.Hunger = .fed, rules: String? = nil, ts: Int64) {
        self.kind = kind
        self.agent = agent
        self.project = project
        self.outcome = outcome
        self.topic = topic
        self.tookMs = tookMs
        self.error = error
        self.more = more
        self.words = words.map { String($0.prefix(Input.maxWords)) }
        self.yesterday = yesterday
        self.clock = clock
        self.weekday = weekday
        self.hunger = hunger
        self.rules = rules
        self.ts = ts
    }

    /// What happened, as one line, e.g. `agent finished · done · claude ·
    /// jetpack · topic: tests · took 18 min · 14:05 Tuesday`. The words of
    /// `you said` aren't in it.
    public var line: String {
        var parts = [kind.rawValue]
        switch kind {
        case .agentStarted:
            parts += [agent ?? "?", project ?? "?"]
        case .agentFinished:
            parts += [outcome?.rawValue ?? "done", agent ?? "?", project ?? "?"]
            if let topic { parts.append("topic: \(topic)") }
            if outcome == .failed {
                if let error { parts.append("error: " + error.replacingOccurrences(of: "_", with: " ")) }
            } else if let tookMs {
                parts.append("took " + Input.took(tookMs))
            }
        case .said:
            break
        case .newDay:
            return ([kind.rawValue] + (yesterday.map { ["yesterday \($0)"] } ?? [])).joined(separator: " · ")
        }
        parts.append("\(clock) \(weekday)")
        if hunger == .hungry { parts.append("hungry") }
        if hunger == .starving { parts.append("starving") }
        if more > 0 { parts.append("+\(more) more") }
        return parts.joined(separator: " · ")
    }

    public static func took(_ ms: Int64) -> String {
        ms < 60_000 ? "\(ms / 1000) s" : "\(ms / 60_000) min"
    }
}

extension Input {
    /// One line of a fixture file (`app/Tests/Fixtures/inputs/`), or nil when
    /// it isn't one:
    ///
    ///     {"input": "agent finished", "outcome": "done", "agent": "claude", "project": "jetpack",
    ///      "topic": "tests", "took_s": 1080, "time": "14:05", "weekday": "Tuesday"}
    ///
    /// Optional fields: `outcome`, `topic`, `took_s`, `error`, `more`, `words`,
    /// `yesterday`, `hunger` (`hungry` or `starving`). The caller gives the time.
    public static func fixture(_ line: String, ts: Int64 = 0) -> Input? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let kind = (o["input"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        let hunger: Growth.Hunger = switch o["hunger"] as? String {
        case "hungry": .hungry
        case "starving": .starving
        default: .fed
        }
        return Input(kind, agent: o["agent"] as? String, project: o["project"] as? String,
                     outcome: (o["outcome"] as? String).flatMap(Outcome.init(rawValue:)), topic: o["topic"] as? String,
                     tookMs: (o["took_s"] as? Int).map { Int64($0) * 1000 }, error: o["error"] as? String,
                     more: o["more"] as? Int ?? 0, words: o["words"] as? String, yesterday: o["yesterday"] as? String,
                     clock: o["time"] as? String ?? "12:00", weekday: o["weekday"] as? String ?? "Tuesday",
                     hunger: hunger, ts: ts)
    }
}
