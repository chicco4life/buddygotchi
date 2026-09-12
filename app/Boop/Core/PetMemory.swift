import Foundation

// MARK: - Effort

/// Elapsed duration of the current work period, independent of errors or retries.
enum EffortTier: String, Sendable, Equatable, Codable, CaseIterable {
    var creatureEffort: CreatureEffort { CreatureEffort(rawValue: rawValue) ?? .light }
    case light
    case hard
    case grinding
}

// MARK: - Ambient Mood

// MARK: - Legacy identity storage

/// Inactive legacy record, preserved only for saved-memory compatibility.
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

// MARK: - Legacy drawing storage

/// Inactive legacy drawing. Decode and re-encode it without displaying it.
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
    var lastInteractionAt: Double?
    var lastSeenAt: Double?
    /// Activity histogram over UTC hour-of-day. UTC on purpose: the absolute
    /// hour never matters, only consistency — "the user's usual hours" is the
    /// same shape in any fixed offset, and pure arithmetic keeps the reducer
    /// free of Calendar/timezone reads. A timezone move just re-learns.
    var hourHistogram: [Int] = Array(repeating: 0, count: 24)
    var histogramSamples: Int = 0
    var firstSampleAt: Double?
    var lastSampleAt: Double?
    var projects: [String: Double] = [:]
    var completedTurns: Int = 0
    var lifetimeSessions: Int = 0
    var lifetimeCelebrations: Int = 0
    var agents: [String: AgentIdentity] = [:]
    /// Inactive saved drawings; no new entries or resurfacing.
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
        lastInteractionAt = try c.decodeIfPresent(Double.self, forKey: .lastInteractionAt)
        projects = try c.decodeIfPresent([String: Double].self, forKey: .projects) ?? [:]
        completedTurns = try c.decodeIfPresent(Int.self, forKey: .completedTurns) ?? c.decodeIfPresent(Int.self, forKey: .lifetimeCelebrations) ?? 0
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

    static let celebrationMinMs: Double = 60_000

    /// Effort tier boundaries on the current work span.
    static let effortHardMinMs: Double = 3 * 60_000
    static let effortGrindingMinMs: Double = 5 * 60_000

}
