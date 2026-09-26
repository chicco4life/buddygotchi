import Foundation

/// Energy, pace and pitch, 0–200 with 100 as neutral (PROTOCOL.md §3).
public struct Mood: Equatable, Sendable {
    public var energy: Int
    public var pace: Int
    public var pitch: Int

    public init(energy: Int = 100, pace: Int = 100, pitch: Int = 100) {
        self.energy = energy
        self.pace = pace
        self.pitch = pitch
    }
}

/// Mood by rule (BEHAVIORS.md §5): wins lift it, failures calm it, night
/// makes Boop drowsy, and it drifts back to neutral over about half an hour.
/// It never reads prompts.
struct MoodState: Sendable {
    /// Half-life of the drift back to neutral: after 30 minutes an eighth is left.
    static let halfLifeMs: Double = 10 * 60 * 1000
    static let limit: Double = 60

    var energy: Double = 0
    var pace: Double = 0
    var pitch: Double = 0
    /// Failures in a row, reset by a win.
    var failures = 0
    var updated: Int64 = 0

    mutating func decay(to now: Int64) {
        guard now > updated else { return }
        let factor = pow(0.5, Double(now - updated) / MoodState.halfLifeMs)
        energy *= factor
        pace *= factor
        pitch *= factor
        updated = now
    }

    /// A finished turn. Quick ones (under 10 seconds) lift it more.
    mutating func win(quick: Bool, at now: Int64) {
        decay(to: now)
        failures = 0
        nudge(energy: quick ? 14 : 8, pace: quick ? 8 : 4, pitch: quick ? 10 : 6)
    }

    mutating func fail(at now: Int64) {
        decay(to: now)
        failures += 1
        nudge(energy: -15, pace: -10, pitch: -10)
    }

    private mutating func nudge(energy e: Double, pace p: Double, pitch h: Double) {
        energy = max(-MoodState.limit, min(MoodState.limit, energy + e))
        pace = max(-MoodState.limit, min(MoodState.limit, pace + p))
        pitch = max(-MoodState.limit, min(MoodState.limit, pitch + h))
    }

    func mood(at now: Int64, night: Bool, hunger: Growth.Hunger) -> Mood {
        var copy = self
        copy.decay(to: now)
        var e = 100 + copy.energy
        var p = 100 + copy.pace
        var h = 100 + copy.pitch
        if night { e -= 25; p -= 15; h -= 10 }
        switch hunger {
        case .fed: break
        case .hungry: e -= 10; p -= 5
        case .starving: e -= 30; p -= 15
        }
        func clamp(_ v: Double) -> Int { Int(max(0, min(200, v.rounded()))) }
        return Mood(energy: clamp(e), pace: clamp(p), pitch: clamp(h))
    }

    /// How `short-term.md` describes the mood today.
    func word(at now: Int64, night: Bool, hunger: Growth.Hunger) -> String {
        let m = mood(at: now, night: night, hunger: hunger)
        if failures >= 2 { return "a bit frazzled" }
        if hunger == .starving { return "peckish and low" }
        if night && m.energy < 90 { return "sleepy" }
        if m.energy >= 125 { return "bouncy" }
        if m.energy <= 75 { return "a bit flat" }
        return "content"
    }

    /// The feeling for a mumble by rule, from how Boop feels right now.
    func feeling(at now: Int64, night: Bool, hunger: Growth.Hunger) -> String {
        let m = mood(at: now, night: night, hunger: hunger)
        if failures >= 2 { return "annoyed" }
        if hunger == .starving { return "sad" }
        if night || m.energy < 70 { return "sleepy" }
        if hunger == .hungry { return "hopeful" }
        if m.energy >= 130 { return "excited" }
        if m.energy >= 110 { return "happy" }
        return "curious"
    }
}
