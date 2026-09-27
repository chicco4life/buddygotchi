import Foundation

/// One of the four things that reach the brain's pipeline (HARNESS.md §2),
/// typed. The core builds them; classifiers read their fields, and language
/// models read `line`. A tap and "needs you" never become inputs: the rules
/// handle them, and the transcript only notes them. A poke streak does.
public struct Input: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case agentStarted = "agent started"
        case agentFinished = "agent finished"
        case said = "you said"
        case poked = "poked again and again"

        /// Milliseconds for both stages; a later answer is dropped.
        public var deadlineMs: Int {
            switch self {
            case .agentStarted, .agentFinished: 5000
            case .said, .poked: 4000
            }
        }

        /// What Boop may do for this kind of input, in the order it's done
        /// (HARNESS.md §3); `Input.menu` narrows it for the input itself.
        /// Plain data: the harness doesn't know what the tools do.
        public var menu: [String] {
            switch self {
            case .agentStarted, .agentFinished, .poked: ["react"]
            case .said: ["quiet", "react", "remember"]
            }
        }
    }

    public enum Outcome: String, Sendable { case done, failed }

    /// How long a finished turn took, by name, so no brain has to compare
    /// numbers (HARNESS.md §2): short under 15 s, long up to a minute, very
    /// long past it.
    public enum Length: String, Sendable {
        case short
        case long
        case veryLong = "very long"

        public init(ms: Int64) {
            self = ms < 15_000 ? .short : ms <= 60_000 ? .long : .veryLong
        }
    }

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
    public var length: Length? { tookMs.map(Length.init(ms:)) }
    /// A failed turn's error class, e.g. `rate_limit` (ADAPTERS.md §2).
    public var error: String?
    /// How many other agent inputs a 3 s burst merged into this one.
    public var more = 0
    /// You said: your words, at most `maxWords` characters.
    public var words: String?
    /// You said: you yelled it (BEHAVIORS.md §3.3).
    public var yelled = false
    /// `14:05`, and `Tuesday`.
    public var clock: String
    public var weekday: String
    /// What the rules already did about it, e.g. `cheer`, for the transcript.
    public var rules: String?
    public var ts: Int64

    /// Your words are cut to this, about 30 s of speech.
    public static let maxWords = 500

    public init(_ kind: Kind, agent: String? = nil, project: String? = nil, outcome: Outcome? = nil,
                topic: String? = nil, tookMs: Int64? = nil, error: String? = nil, more: Int = 0,
                words: String? = nil, yelled: Bool = false, clock: String,
                weekday: String, rules: String? = nil, ts: Int64) {
        self.kind = kind
        self.agent = agent
        self.project = project
        self.outcome = outcome
        self.topic = topic
        self.tookMs = tookMs
        self.error = error
        self.more = more
        self.words = words.map { String($0.prefix(Input.maxWords)) }
        self.yelled = yelled
        self.clock = clock
        self.weekday = weekday
        self.rules = rules
        self.ts = ts
    }

    /// What happened, as one line, e.g. `agent finished · done · claude ·
    /// jetpack · topic: tests · a very long turn (18 min) · 14:05 Tuesday`,
    /// or `you said · yelled · 14:05 Tuesday`. The words of `you said`
    /// aren't in it.
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
                parts.append("a \(Length(ms: tookMs).rawValue) turn (\(Input.took(tookMs)))")
            }
        case .said:
            if yelled { parts.append("yelled") }
        case .poked:
            break
        }
        parts.append("\(clock) \(weekday)")
        if more > 0 { parts.append("+\(more) more") }
        return parts.joined(separator: " · ")
    }

    public static func took(_ ms: Int64) -> String {
        ms < 60_000 ? "\(ms / 1000) s" : "\(ms / 60_000) min"
    }

    /// What Boop may do for this input (HARNESS.md §3): its kind's menu,
    /// narrowed to what can happen, since a brain isn't asked what the
    /// rules decide: `quiet` only when the words ask for quiet or for it to
    /// end, since the quiet action would refuse it otherwise.
    public var menu: [String] {
        kind.menu.filter { $0 != "quiet" || quietAsk != nil }
    }

    /// Which way your words asked about quiet mode (BEHAVIORS.md §3.3).
    public enum QuietAsk: Equatable, Sendable {
        /// "be quiet": `quiet` with minutes.
        case start
        /// "you can talk again": `quiet(0)`.
        case end
    }

    /// Whether your words asked Boop to be quiet, or to stop being quiet,
    /// or neither (nil). Only then may `quiet` run, and only that way,
    /// whoever decided it: the menu, the core and the quiet action all ask
    /// this (BEHAVIORS.md §3.3).
    public var quietAsk: QuietAsk? { endsQuiet ? .end : asksForQuiet ? .start : nil }

    /// Your words asked Boop to be quiet: they have "quiet", "hush", "stop
    /// talking" or "keep it down" in them, as whole words ("be quiet"), and
    /// neither ask it to remember something ("remember I like it quiet")
    /// nor to stop being quiet.
    var asksForQuiet: Bool {
        guard kind == .said else { return false }
        let plain = Input.plain(words ?? "")
        return Input.askingQuiet.contains(where: plain.contains) && !asksToRemember && !endsQuiet
    }

    /// Asking Boop to be quiet (BEHAVIORS.md §3.3).
    static let askingQuiet = [" quiet ", " hush ", " stop talking ", " keep it down "]

    /// Your words asked Boop to stop being quiet ("you can talk again"),
    /// and don't ask it to remember something.
    var endsQuiet: Bool {
        kind == .said && Input.endingQuiet.contains(where: Input.plain(words ?? "").contains) && !asksToRemember
    }

    /// Asking Boop to stop being quiet (BEHAVIORS.md §3.3).
    static let endingQuiet = [" stop being quiet ", " don't have to be quiet ", " dont have to be quiet ",
                              " don't need to be quiet ", " dont need to be quiet ", " no more quiet ",
                              " not quiet anymore ", " quiet mode off ", " turn off quiet ", " you can talk again ",
                              " you can speak again ", " you can mumble again ", " unmute "]

    /// Your words asked Boop to remember something: "remember" or "note",
    /// unless they tell Boop off (HARNESS.md §6). Yelled or not.
    public var asksToRemember: Bool {
        guard kind == .said else { return false }
        let plain = Input.plain(words ?? "")
        return [" remember ", " note "].contains(where: plain.contains) && !Input.tellsOff(plain)
    }

    /// Being told off (BEHAVIORS.md §3.3): one of these, or "you" with an
    /// insult, so "you're so annoying" counts and "this build is annoying"
    /// doesn't.
    static let tellingOff = [" shut up ", " go away ", " hate you ", " you suck "]
    static let you = [" you ", " you're ", " youre ", " ur "]
    static let insults = [" annoying ", " stupid ", " dumb ", " useless ", " idiot "]

    /// Plain words (`plain`) that tell Boop off.
    static func tellsOff(_ plain: String) -> Bool {
        tellingOff.contains(where: plain.contains)
            || you.contains(where: plain.contains) && insults.contains(where: plain.contains)
    }

    /// Lowercase words between single spaces, padded, so a phrase matches
    /// whole words only: " hi there ". Curly apostrophes are straight ones:
    /// "I’d rather" is " i'd rather ". Anything but letters, digits and
    /// `keeping` splits words.
    public static func plain(_ words: String, keeping: String = "'") -> String {
        let letters = straight(words).lowercased().map { $0.isLetter || $0.isNumber || keeping.contains($0) ? $0 : " " }
        return " " + String(letters).split(separator: " ").joined(separator: " ") + " "
    }

    /// The words with curly apostrophes (’ and ‘, as typed or pasted text
    /// may have them) made straight.
    public static func straight(_ words: String) -> String {
        words.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
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
    /// `yelled`. The caller gives the time.
    public static func fixture(_ line: String, ts: Int64 = 0) -> Input? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let kind = (o["input"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        return Input(kind, agent: o["agent"] as? String, project: o["project"] as? String,
                     outcome: (o["outcome"] as? String).flatMap(Outcome.init(rawValue:)), topic: o["topic"] as? String,
                     tookMs: (o["took_s"] as? Int).map { Int64($0) * 1000 }, error: o["error"] as? String,
                     more: o["more"] as? Int ?? 0, words: o["words"] as? String, yelled: o["yelled"] as? Bool ?? false,
                     clock: o["time"] as? String ?? "12:00", weekday: o["weekday"] as? String ?? "Tuesday", ts: ts)
    }
}
