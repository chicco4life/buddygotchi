import Foundation

// MARK: - Effort

/// How demanding the current task looks. Heuristics (elapsed work span, error
/// count) provide the floor; an agent's own report via MCP overrides them.
enum EffortTier: String, Sendable, Equatable, Codable, CaseIterable {
    case light
    case normal
    case hard
    case grinding
}

// MARK: - Ambient Mood

/// Circadian flavor on top of the base pet state. Deliberately tiny for v1:
/// expectant (awake around the user's usual start time before any session) and
/// surprised (a session at an hour this user never works). Wind-down yawning is
/// deferred — sleep already covers most of that register.
enum PetMood: String, Sendable, Equatable, Codable {
    case expectant
    case surprised
}

// MARK: - Agent Expression (System E)

/// One agent expression currently inhabiting the pet. The pet's body stays
/// system-rendered; this only colors it (identity border, emote, speech
/// bubble). Expires via `until` — the possession lease (S8).
struct AgentOverlay: Sendable, Equatable {
    var agentId: String
    var color: String?
    var emotion: String
    var intensity: String
    var motion: String?
    var say: String?
    var delivery: String?
    var until: Double
}

/// What an agent chose as its identity markers, plus how often it visits.
/// Personality accrues from history: the pet greets returning agents with
/// their own markers.
struct AgentIdentity: Sendable, Equatable, Codable {
    var color: String?
    var signatureEmote: String?
    var greeting: String?
    var visits: Int = 0
    var lastSeenAt: Double?

    init(color: String? = nil, signatureEmote: String? = nil, greeting: String? = nil, visits: Int = 0, lastSeenAt: Double? = nil) {
        self.color = color
        self.signatureEmote = signatureEmote
        self.greeting = greeting
        self.visits = visits
        self.lastSeenAt = lastSeenAt
    }

    /// Same schema-evolution rule as PetMemory: a missing key is a default,
    /// never a decode failure.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        signatureEmote = try c.decodeIfPresent(String.self, forKey: .signatureEmote)
        greeting = try c.decodeIfPresent(String.self, forKey: .greeting)
        visits = try c.decodeIfPresent(Int.self, forKey: .visits) ?? 0
        lastSeenAt = try c.decodeIfPresent(Double.self, forKey: .lastSeenAt)
    }
}

// MARK: - Agent Drawings (E4)

/// One agent drawing: palette-indexed pixel rows, at most 32×32. Stored as
/// hex-digit strings (one digit per pixel, index into `AgentVocabulary.palette`)
/// so a full drawing costs ~1KB in memory JSON and travels as plain text.
struct AgentDrawing: Sendable, Equatable, Codable {
    var agentId: String
    /// The agent's identity color at draw time — frames the drawing.
    var color: String?
    var rows: [String]
    var caption: String?
    var at: Double

    var width: Int { rows.first?.count ?? 0 }
    var height: Int { rows.count }

    init(agentId: String, color: String? = nil, rows: [String], caption: String? = nil, at: Double) {
        self.agentId = agentId
        self.color = color
        self.rows = rows
        self.caption = caption
        self.at = at
    }

    /// Schema-evolution rule (see PetMemory): only the fields a drawing
    /// cannot exist without are allowed to fail the decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try c.decode(String.self, forKey: .agentId)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        rows = try c.decode([String].self, forKey: .rows)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
    }
}

// MARK: - Pet Memory

/// The pet's persisted inner life. Owned by the reducer (it lives in
/// `InternalState`); the engine only loads it at startup and writes it back
/// when it changes. All time arithmetic uses event timestamps (epoch ms) so
/// the reducer stays clock-free.
struct PetMemory: Sendable, Equatable, Codable {
    var lastSeenAt: Double?
    /// Activity histogram over UTC hour-of-day. UTC on purpose: the absolute
    /// hour never matters, only consistency — "the user's usual hours" is the
    /// same shape in any fixed offset, and pure arithmetic keeps the reducer
    /// free of Calendar/timezone reads. A timezone move just re-learns.
    var hourHistogram: [Int] = Array(repeating: 0, count: 24)
    var histogramSamples: Int = 0
    var firstSampleAt: Double?
    var lastSampleAt: Double?
    var lifetimeSessions: Int = 0
    var lifetimeCelebrations: Int = 0
    var agents: [String: AgentIdentity] = [:]
    /// Drawings agents left behind — the seed of the keepsake shelf. FIFO
    /// capped so memory JSON stays bounded (~48KB of drawings at worst).
    var keepsakes: [AgentDrawing] = []
    /// When the pet last dug out an old drawing for a returning agent.
    var lastResurfacedAt: Double?

    static let empty = PetMemory()

    init() {}

    /// Forward-compatible on purpose: synthesized Codable fails the WHOLE
    /// decode when a key is missing, so adding any field would make older
    /// memory files unreadable and silently reset the pet — "fondness is a
    /// ratchet, never resets" lost to a schema bump. (Exactly that wiped the
    /// first agent identities when `keepsakes` landed.) Every field decodes
    /// as if-present with its default instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastSeenAt = try c.decodeIfPresent(Double.self, forKey: .lastSeenAt)
        let histogram = try c.decodeIfPresent([Int].self, forKey: .hourHistogram) ?? []
        hourHistogram = histogram.count == 24 ? histogram : Array(repeating: 0, count: 24)
        histogramSamples = try c.decodeIfPresent(Int.self, forKey: .histogramSamples) ?? 0
        firstSampleAt = try c.decodeIfPresent(Double.self, forKey: .firstSampleAt)
        lastSampleAt = try c.decodeIfPresent(Double.self, forKey: .lastSampleAt)
        lifetimeSessions = try c.decodeIfPresent(Int.self, forKey: .lifetimeSessions) ?? 0
        lifetimeCelebrations = try c.decodeIfPresent(Int.self, forKey: .lifetimeCelebrations) ?? 0
        agents = try c.decodeIfPresent([String: AgentIdentity].self, forKey: .agents) ?? [:]
        keepsakes = try c.decodeIfPresent([AgentDrawing].self, forKey: .keepsakes) ?? []
        lastResurfacedAt = try c.decodeIfPresent(Double.self, forKey: .lastResurfacedAt)
    }

    // MARK: Circadian derivations

    static func utcHour(ofMs at: Double) -> Int {
        // Epoch ms → hour of day, UTC. Double-safe for any plausible date.
        let hours = Int(at / 3_600_000)
        return ((hours % 24) + 24) % 24
    }

    /// Cold-start neutrality: no circadian behavior until the histogram has
    /// both enough samples and enough calendar age to mean something.
    func circadianReady(at: Double) -> Bool {
        guard let first = firstSampleAt else { return false }
        return histogramSamples >= PetTuning.circadianMinSamples
            && at - first >= PetTuning.circadianMinAgeMs
    }

    /// An hour the user regularly works: at least ~8% of all sampled activity.
    func isTypicalHour(_ hour: Int) -> Bool {
        guard hour >= 0, hour < 24, histogramSamples > 0 else { return false }
        return hourHistogram[hour] >= max(2, Int(Double(histogramSamples) * 0.08))
    }

    /// An hour this user essentially never works: ≤2% of sampled activity.
    func isUnusualHour(_ hour: Int) -> Bool {
        guard hour >= 0, hour < 24, histogramSamples > 0 else { return false }
        return hourHistogram[hour] <= Int(Double(histogramSamples) * 0.02)
    }
}

// MARK: - Tuning

/// Behavior thresholds for Systems P and E, in one place. All times epoch ms
/// or durations in ms.
enum PetTuning {
    /// Gap after which returning earns a greeting. Absence is a ratchet: the
    /// pet is glad to see you, never guilty about the gap.
    static let greetGapMs: Double = 18 * 3_600_000
    /// A week away upgrades the greeting to the big one. Capped there — a
    /// month reads the same as a week, by design.
    static let greetBigGapMs: Double = 7 * 24 * 3_600_000
    static let greetShortMs: Double = 5_000
    static let greetBigMs: Double = 8_000

    /// One histogram sample per ~30 min of presence, not one per tool call —
    /// "active hours" sampling, so a chatty agent doesn't dominate the shape.
    static let circadianSampleGapMs: Double = 30 * 60_000
    static let circadianMinSamples = 20
    static let circadianMinAgeMs: Double = 14 * 24 * 3_600_000
    /// How long the surprised-then-cozy reaction lasts after an odd-hour start.
    static let surpriseMoodMs: Double = 60_000

    /// Effort tier boundaries on the current work span.
    static let effortLightMaxMs: Double = 2 * 60_000
    static let effortHardMinMs: Double = 10 * 60_000
    static let effortGrindingMinMs: Double = 25 * 60_000

    /// Celebration payoff boundaries — struggle-proportional joy.
    static let celebrateBigMinMs: Double = 10 * 60_000
    static let celebrateHugeMinMs: Double = 25 * 60_000

    /// Possession lease (S8): an expression owns the overlay this long, then
    /// the pet is itself again. Speech lingers slightly longer to be readable.
    static let agentExpressLeaseMs: Double = 6_000
    static let agentSayLeaseMs: Double = 8_000
    /// Hard server-side floor between expressions per agent (S6).
    static let agentExpressMinGapMs: Double = 60_000

    static let sayMaxBytes = 40
    static let greetingMaxBytes = 30

    /// Drawing canvas cap — a security parameter, not just an aesthetic one:
    /// ~4 legible characters fits at 32px, a convincing instruction does not.
    /// Do not raise without redoing the spoofing analysis (plan doc, E4).
    static let drawMaxSide = 32
    static let drawCaptionMaxBytes = 30
    /// Floor between drawings per agent (S6). Ten minutes: enough to draw at
    /// natural moments through a session (a finish, a milestone, a whim), not
    /// just at parting — while staying an event rather than wallpaper.
    static let agentDrawMinGapMs: Double = 10 * 60_000
    /// How long the pet holds a fresh drawing up before shelving it.
    static let drawShowMs: Double = 12_000
    static let keepsakeCap = 48
    /// Resurfacing ("remember this?"): a returning agent's old drawing comes
    /// back out. The drawing must be at least this old to count as a memory…
    static let resurfaceMinAgeMs: Double = 24 * 3_600_000
    /// …and the pet does this at most once a day, so it stays a small
    /// surprise instead of a ritual.
    static let resurfaceMinGapMs: Double = 24 * 3_600_000
}

// MARK: - Agent expression vocabulary (S4)

/// The enum-only sandbox. Evocative names on purpose: the schema's enum list
/// is the affordance menu the model reads, and `sheepish`/`smug`/`wistful`
/// elicit far more differentiated choices than `happy1`/`happy2`.
enum AgentVocabulary {
    static let emotions: Set<String> = [
        "happy", "proud", "sheepish", "smug", "determined", "focused",
        "wistful", "curious", "surprised", "relieved", "exhausted",
        "dramatic-collapse", "triumphant", "grateful", "playful", "shy",
        "stoic", "puzzled", "mischievous", "cozy", "pumped", "zen",
        "apologetic", "celebratory",
    ]
    static let motions: Set<String> = [
        "bounce", "tilt", "spin", "wiggle", "look-at-user", "sigh", "nod", "shake",
    ]
    static let intensities: Set<String> = ["low", "medium", "high"]
    static let deliveries: Set<String> = ["whisper", "plain", "excited", "deadpan"]
    /// Identity colors an agent may claim in `introduce`.
    static let colors: Set<String> = [
        "coral", "amber", "mint", "sky", "lavender", "rose", "sand", "teal",
    ]

    /// The drawing palette (E4). Fixed on purpose: the agent picks indices,
    /// the product picks the vibe, so every drawing by every model looks
    /// like it belongs to Boop. Index 0 is transparent; hex digit in a
    /// drawing row = index here. Mirror any change into the firmware
    /// renderer when the glass path lands.
    static let palette: [String] = [
        "transparent",
        "#1A1A1A",  // 1 ink
        "#FFF6E5",  // 2 cream
        "#8A8578",  // 3 warm gray
        "#F47159",  // 4 coral
        "#F5B042",  // 5 amber
        "#FFD94A",  // 6 sunshine
        "#6DDB92",  // 7 mint
        "#3E9B5C",  // 8 leaf
        "#4992E8",  // 9 sky
        "#24B6B0",  // a teal
        "#B692FF",  // b lavender
        "#EB80AD",  // c rose
        "#DBB66D",  // d sand
        "#7A4E2E",  // e cocoa
        "#E0393E",  // f cherry
    ]
}
