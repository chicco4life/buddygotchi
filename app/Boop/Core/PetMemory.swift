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

    static let empty = PetMemory()

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
}
