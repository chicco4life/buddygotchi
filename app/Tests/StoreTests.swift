import Foundation
import SQLite3
import XCTest
@testable import BoopCore

final class StoreTests: XCTestCase {
    func testLegacyMemoryMigrationAndReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        var memory = PetMemory.empty
        memory.lifetimeSessions = 12; memory.completedTurns = 100; memory.lifetimeCelebrations = 99
        memory.projects = ["boop":123]; memory.lastSeenAt = 321; memory.hourHistogram[9] = 7
        memory.agents["codex"] = AgentIdentity(color:"sky",visits:4,lastSeenAt:100)
        let legacy = dir.appendingPathComponent("pet-memory.json")
        try JSONEncoder().encode(memory).write(to:legacy)
        let store = try Store(stateDir:dir.path,now:0)
        let loaded = try await store.loadMemory()
        XCTAssertEqual(loaded,memory)
        XCTAssertFalse(FileManager.default.fileExists(atPath:legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:legacy.path + ".migrated"))
        memory.lifetimeSessions += 1
        try await store.saveMemory(memory)
        let reopened = try Store(stateDir:dir.path,now:0)
        let saved = try await reopened.loadMemory()
        XCTAssertEqual(saved,memory)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dir.path + "/boop.sqlite", &db, SQLITE_OPEN_READONLY,nil),SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db,"SELECT json FROM memory WHERE key='lifetimeSessions'",-1,&statement,nil),SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement),SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement,0),13)
    }
    func testPruningAtBoundaryOnStartupAndDaily() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try Store(stateDir:dir.path,now:0)
        let day: Double = 86_400_000
        try await store.appendFacts([0,1,day].map { StoredFact(fact:.project(id:"p"),sessionId:"s",project:"p",at:$0,day:"2026-01-01") })
        let reopened = try Store(stateDir:dir.path,now:30*day+1)
        let startup = try await reopened.facts()
        XCTAssertEqual(startup.count,2)
        try await reopened.prune(now:31*day+1,localDay:"2026-02-02")
        let pruned = try await reopened.facts()
        XCTAssertTrue(pruned.isEmpty)
    }
    func testProfileClearDoesNotResetGrowthBondOrMemory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try Store(stateDir:dir.path,now:0)
        _ = try await store.award([],active:true,at:0,localDay:"2026-01-01")
        try await store.saveMemory(.empty)
        try await store.addProfileLine("works late",source:"rules",at:0)
        try await store.addProfileLine("tests first, usually",source:"rules",at:0)
        let lines = try await store.profile()
        XCTAssertEqual(lines.count,2)
        try await store.deleteProfileLine(lines[0].id)
        let one = try await store.profile(); XCTAssertEqual(one.count,1)
        try await store.clearProfile()
        let empty = try await store.profile(); XCTAssertTrue(empty.isEmpty)
        let growth = try await store.growth(localDay:"2026-01-01",at:0); XCTAssertEqual(growth.xp,11)
        let traits = try await store.traits(); XCTAssertEqual(traits["bond"],1)
        let memory = try await store.loadMemory(); XCTAssertEqual(memory,.empty)
    }
    func testTraitsCapsAndBondMonotonicCaps() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try Store(stateDir:dir.path,now:0)
        for _ in 0..<10 {
            try await store.applyDrift(["energy":99,"cheek":-99,"warmth":99,"curiosity":-99],localDay:"2026-01-01")
            try await store.bond(collected:true,greetAfterAbsence:false,localDay:"2026-01-01")
        }
        var traits = try await store.traits()
        XCTAssertEqual(traits,["energy":131,"cheek":125,"warmth":131,"curiosity":125,"bond":3])
        for n in 0..<100 { try await store.applyDrift(["energy":3,"cheek":-3],localDay:"day-\(n)") }
        for _ in 0..<200 { try await store.bond(collected:false,greetAfterAbsence:true,localDay:"2026-01-01") }
        traits = try await store.traits()
        XCTAssertEqual(traits["energy"],255); XCTAssertEqual(traits["cheek"],0); XCTAssertEqual(traits["bond"],255)
    }
    func testInventoryUnlockAndEquipSurvivesReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try Store(stateDir:dir.path,now:0)
        _ = try await store.growth(localDay:"2026-01-01",at:0)
        do { try await store.equip(EquippedCosmetic(skin:"sky")); XCTFail("locked") } catch {}
        _ = try await store.award([LedgerRow(at:0,source:.task,amount:150,day:"2026-01-01")],active:false,at:0,localDay:"2026-01-01")
        try await store.equip(EquippedCosmetic(skin:"mint"))
        let reopened = try Store(stateDir:dir.path,now:0)
        let cosmetic = try await reopened.cosmetic(); XCTAssertEqual(cosmetic.skin,"mint")
        let growth = try await reopened.growth(localDay:"2026-01-01",at:0); XCTAssertEqual(growth.level,5)
        var formula = GrowthFormula(); formula.task = 16
        let reread = try await reopened.growth(localDay:"2026-01-01",at:0,formula:formula)
        XCTAssertEqual(reread.xp,2400)
        let original = try await reopened.growth(localDay:"2026-01-01",at:0)
        XCTAssertEqual(original.xp,1200)
    }
}

extension StoreTests {
    func testSetupTemperamentAndLastFiveHundredFacts() async throws {
        for (temperament,expected) in [("earnest",64),("cheeky",192)] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:dir) }
            let store = try Store(stateDir:dir.path,now:0,temperament:temperament)
            let traits = try await store.traits(); XCTAssertEqual(traits["cheek"],expected)
            try await store.appendFacts((0..<510).map { StoredFact(fact:.tokens(output:$0),sessionId:"s",project:"p",at:Double($0),day:"2026-01-01") })
            let facts = try await store.facts()
            XCTAssertEqual(facts.count,500); XCTAssertEqual(facts.first?.at,509); XCTAssertEqual(facts.last?.at,10)
        }
    }
}

extension StoreTests {
    func testSavingEmptyMemoryRemovesOptionalKeysAndCorruptLegacyStaysRecoverable() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let legacy = dir.appendingPathComponent("pet-memory.json")
        try Data("broken".utf8).write(to:legacy)
        let store = try Store(stateDir:dir.path,now:0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:legacy.path))
        var memory = PetMemory.empty; memory.lastSeenAt = 10
        try await store.saveMemory(memory); try await store.saveMemory(.empty)
        let empty = try await store.loadMemory(); XCTAssertEqual(empty,.empty)
        let growth = try await store.award([],active:true,at:0,localDay:"2026-01-01")
        XCTAssertEqual(growth.xp,11)
    }
}
