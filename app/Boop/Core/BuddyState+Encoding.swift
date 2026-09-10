import Foundation

// Diagnostic /state JSON retains its established shape while legacy values
// are derived from the creature. Species remains nested under "pet".
extension BuddyState {
    private enum CodingKeys: String, CodingKey {
        case language
        case growth
        case cosmetic
        case version
        case updatedAt
        case desktop
        case sessions
        case msg
        case entries
        case prompt
        case devicePosture
        case deviceBattery
        case creature
        case pet
        case lastSignal
        case celebrateUntil
        case affectionUntil
        case lastTaskDurationMs
        case lastCompletionAt
        case lastCompleted
        case firstErrored
        case activeSessions
        case currentActivityKind
        case greetUntil
        case greetLevel
        case effortTier
        case celebrateIntensity
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(growth, forKey: .growth)
        try c.encode(cosmetic, forKey: .cosmetic)
        try c.encode(version, forKey: .version)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(desktop, forKey: .desktop)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(msg, forKey: .msg)
        try c.encode(entries, forKey: .entries)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(devicePosture, forKey: .devicePosture)
        try c.encodeIfPresent(deviceBattery, forKey: .deviceBattery)
        try c.encode(creature, forKey: .creature)
        try c.encode(pet, forKey: .pet)
        try c.encodeIfPresent(lastSignal, forKey: .lastSignal)
        try c.encodeIfPresent(celebrateUntil, forKey: .celebrateUntil)
        try c.encodeIfPresent(affectionUntil, forKey: .affectionUntil)
        try c.encodeIfPresent(lastTaskDurationMs, forKey: .lastTaskDurationMs)
        try c.encodeIfPresent(lastCompletionAt, forKey: .lastCompletionAt)
        try c.encodeIfPresent(lastCompleted, forKey: .lastCompleted)
        try c.encodeIfPresent(firstErrored, forKey: .firstErrored)
        try c.encode(activeSessions, forKey: .activeSessions)
        try c.encodeIfPresent(currentActivityKind, forKey: .currentActivityKind)
        try c.encodeIfPresent(greetUntil, forKey: .greetUntil)
        try c.encodeIfPresent(greetLevel, forKey: .greetLevel)
        try c.encodeIfPresent(effortTier, forKey: .effortTier)
        try c.encodeIfPresent(celebrateIntensity, forKey: .celebrateIntensity)
    }
}
