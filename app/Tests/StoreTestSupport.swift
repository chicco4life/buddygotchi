import Foundation
import XCTest
@testable import BoopCore

func makeStore(now: Double = 0, temperament: String? = nil) throws -> (Store, URL, () -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try Store(stateDir: dir.path, now: now, temperament: temperament)
    return (store, dir, { try? FileManager.default.removeItem(at: dir) })
}

@MainActor
func makeEngine(store: (any EngineStore)? = nil) -> (BuddyEngine, MockClock) {
    let clock = MockClock()
    var config = BuddyConfig.default
    config.httpPort = 0; config.stateDir = "/tmp"; config.token = "test-token"
    config.staleTimeoutMs = 600_000; config.celebrateDurationMs = 4_000
    return (BuddyEngine(config: config, clock: clock, store: store), clock)
}

/// Suspends facts forever while every other operation remains a real SQLite operation.
actor SuspendedFactStore: EngineStore {
    let base: Store
    private(set) var appendStarted = false
    private var blocked: UnsafeContinuation<Void, Never>?
    init(base: Store) { self.base = base }
    func appendFacts(_ facts: [StoredFact]) async throws {
        appendStarted = true
        await withUnsafeContinuation { blocked = $0 }
    }
    func migrate() async throws { try await base.migrate() }
    func loadMemory() async throws -> PetMemory? { try await base.loadMemory() }
    func saveMemory(_ memory: PetMemory) async throws { try await base.saveMemory(memory) }
    func facts() async throws -> [StoredFact] { try await base.facts() }
    func award(_ rows: [LedgerRow], active: Bool, at: Double, localDay: String) async throws -> GrowthSnapshot? { try await base.award(rows, active: active, at: at, localDay: localDay) }
    func growth(localDay: String, at: Double) async throws -> GrowthSnapshot { try await base.growth(localDay: localDay, at: at) }
    func cosmetic() async throws -> EquippedCosmetic { try await base.cosmetic() }
    func recordCheer(_ size: CheerSize) async throws { try await base.recordCheer(size) }
    func bond(collected: Bool, greetAfterAbsence: Bool, localDay: String) async throws { try await base.bond(collected: collected, greetAfterAbsence: greetAfterAbsence, localDay: localDay) }
    func prune(now: Double, localDay: String) async throws { try await base.prune(now: now, localDay: localDay) }
    func reflect(localDay: String, at: Double) async throws -> [ProfileLine] { try await base.reflect(localDay: localDay, at: at) }
    func profile() async throws -> [ProfileLine] { try await base.profile() }
    func inventory() async throws -> [InventoryItem] { try await base.inventory() }
    func deleteProfileLine(_ id: Int) async throws { try await base.deleteProfileLine(id) }
    func clearProfile() async throws { try await base.clearProfile() }
    func equip(_ cosmetic: EquippedCosmetic) async throws { try await base.equip(cosmetic) }
}

/// Counts voice-related I/O while retaining real SQLite behavior.
actor CountingVoiceStore: EngineStore {
    let base: Store
    private(set) var exclusionReads = 0
    private(set) var dayFactReads = 0
    private(set) var recapChecks = 0
    private(set) var profileReads = 0
    private(set) var traitReads = 0
    private(set) var remembered: [String] = []
    init(base: Store) { self.base = base }
    func appendFacts(_ facts: [StoredFact]) async throws { try await base.appendFacts(facts) }
    func voiceExclusions(localDay: String) async throws -> [String] {
        exclusionReads += 1
        return try await base.voiceExclusions(localDay: localDay)
    }
    func rememberVoice(_ line: String, localDay: String) async throws {
        remembered.append(line)
        try await base.rememberVoice(line, localDay: localDay)
    }
    func facts(localDay: String) async throws -> [StoredFact] {
        dayFactReads += 1
        return try await base.facts(localDay: localDay)
    }
    func recapDay() async throws -> String? { recapChecks += 1; return try await base.recapDay() }
    func traits() async throws -> Traits { traitReads += 1; return try await base.traits() }
    func migrate() async throws { try await base.migrate() }
    func loadMemory() async throws -> PetMemory? { try await base.loadMemory() }
    func saveMemory(_ memory: PetMemory) async throws { try await base.saveMemory(memory) }
    func facts() async throws -> [StoredFact] { try await base.facts() }
    func award(_ rows: [LedgerRow], active: Bool, at: Double, localDay: String) async throws -> GrowthSnapshot? { try await base.award(rows, active: active, at: at, localDay: localDay) }
    func growth(localDay: String, at: Double) async throws -> GrowthSnapshot { try await base.growth(localDay: localDay, at: at) }
    func cosmetic() async throws -> EquippedCosmetic { try await base.cosmetic() }
    func recordCheer(_ size: CheerSize) async throws { try await base.recordCheer(size) }
    func bond(collected: Bool, greetAfterAbsence: Bool, localDay: String) async throws { try await base.bond(collected: collected, greetAfterAbsence: greetAfterAbsence, localDay: localDay) }
    func prune(now: Double, localDay: String) async throws { try await base.prune(now: now, localDay: localDay) }
    func reflect(localDay: String, at: Double) async throws -> [ProfileLine] { try await base.reflect(localDay: localDay, at: at) }
    func profile() async throws -> [ProfileLine] { profileReads += 1; return try await base.profile() }
    func inventory() async throws -> [InventoryItem] { try await base.inventory() }
    func deleteProfileLine(_ id: Int) async throws { try await base.deleteProfileLine(id) }
    func clearProfile() async throws { try await base.clearProfile() }
    func equip(_ cosmetic: EquippedCosmetic) async throws { try await base.equip(cosmetic) }
}
