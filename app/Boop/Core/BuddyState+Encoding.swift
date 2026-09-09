import Foundation

// Diagnostic /state JSON retains its established shape while legacy values
// are derived from the creature. Species remains nested under "pet".
extension BuddyState {
    private enum CodingKeys: String, CodingKey {
        case language
        case recap
        case leaderboard
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
        case firstThinking
        case activeSessions
        case currentActivityKind
        case greetUntil
        case greetLevel
        case mood
        case moodUntil
        case effortTier
        case celebrateIntensity
        case agentOverlay
        case agentDrawing
        case agentDrawingUntil
        case agentDrawingIsMemory
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encodeIfPresent(recap, forKey: .recap)
        try c.encodeIfPresent(leaderboard, forKey: .leaderboard)
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
        try c.encodeIfPresent(firstThinking, forKey: .firstThinking)
        try c.encode(activeSessions, forKey: .activeSessions)
        try c.encodeIfPresent(currentActivityKind, forKey: .currentActivityKind)
        try c.encodeIfPresent(greetUntil, forKey: .greetUntil)
        try c.encodeIfPresent(greetLevel, forKey: .greetLevel)
        try c.encodeIfPresent(mood, forKey: .mood)
        try c.encodeIfPresent(moodUntil, forKey: .moodUntil)
        try c.encodeIfPresent(effortTier, forKey: .effortTier)
        try c.encodeIfPresent(celebrateIntensity, forKey: .celebrateIntensity)
        try c.encodeIfPresent(agentOverlay, forKey: .agentOverlay)
        try c.encodeIfPresent(agentDrawing, forKey: .agentDrawing)
        try c.encodeIfPresent(agentDrawingUntil, forKey: .agentDrawingUntil)
        try c.encodeIfPresent(agentDrawingIsMemory, forKey: .agentDrawingIsMemory)
    }
}
