import Foundation
import BoopSQLite
import SQLite3
import XCTest
@testable import BoopCore

final class StoreTests: XCTestCase {
    func testLegacyMemoryMigrationAndReopen() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        var memory = PetMemory.empty
        memory.lifetimeSessions = 12; memory.completedTurns = 100; memory.lifetimeCelebrations = 99
        memory.projects = ["boop":123]; memory.lastSeenAt = 321; memory.hourHistogram[9] = 7
        memory.agents["codex"] = AgentIdentity(color:"sky",visits:4,lastSeenAt:100)
        memory.keepsakes = [AgentDrawing(agentId: "codex", rows: ["01", "10"], caption: "saved", at: 100)]
        let legacy = dir.appendingPathComponent("pet-memory.json")
        try JSONEncoder().encode(memory).write(to:legacy)
        try await store.migrate()
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
        XCTAssertEqual(sqlite3_prepare_v2(db,"SELECT json_extract(json, '$.lifetimeSessions') FROM memory WHERE key='memory'",-1,&statement,nil),SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement),SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement,0),13)
    }
    func testPruningAtBoundaryOnStartupAndDaily() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
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
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
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
        let growth = try await store.growth(localDay:"2026-01-01",at:0); XCTAssertEqual(growth.xp,10)
        let traits = try await store.traits(); XCTAssertEqual(traits["bond"],0)
        let memory = try await store.loadMemory(); XCTAssertEqual(memory,.empty)
    }

    func testFixedAppearanceIgnoresLegacyChoicesAndPreservesGrowth() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let initialInventory = try await store.inventory()
        XCTAssertEqual(initialInventory.count, CompanionOption.catalog.count)
        let db = try Database(path: dir.path + "/boop.sqlite")
        try db.run("INSERT OR REPLACE INTO meta VALUES('equipped', ?)", [String(decoding: JSONEncoder().encode(EquippedCosmetic(skin: "midnight", accessory: "crown", silhouette: "tall")), as: UTF8.self)])
        do { try await store.equip(EquippedCosmetic(skin: "mint")); XCTFail("custom appearance accepted") } catch {}
        let fresh = try await store.growth(localDay:"2026-01-01",at:0)
        XCTAssertEqual(fresh.xp, 0)
        XCTAssertEqual(fresh.level, 1)
        do { try await store.equip(EquippedCosmetic(skin:"not-a-skin")); XCTFail("unknown cosmetic accepted") } catch {}
        let preserved = try await store.cosmetic()
        XCTAssertEqual(preserved, EquippedCosmetic())
        let lowLevelReopened = try Store(stateDir:dir.path,now:0)
        let lowLevelAppearance = try await lowLevelReopened.cosmetic()
        XCTAssertEqual(lowLevelAppearance, EquippedCosmetic())
        let reopenedInventory = try await lowLevelReopened.inventory()
        XCTAssertEqual(reopenedInventory.map { "\($0.kind):\($0.name)" }, initialInventory.map { "\($0.kind):\($0.name)" })
        _ = try await store.award([LedgerRow(at:0,source:.turn,amount:400,day:"2026-01-01")],active:false,at:0,localDay:"2026-01-01")
        try await store.equip(EquippedCosmetic())
        let reopened = try Store(stateDir:dir.path,now:0)
        let cosmetic = try await reopened.cosmetic(); XCTAssertEqual(cosmetic, EquippedCosmetic())
        let growth = try await reopened.growth(localDay:"2026-01-01",at:0); XCTAssertEqual(growth.level,5)
        var formula = GrowthFormula(); formula.turn = 16
        let reread = try await reopened.growth(localDay:"2026-01-01",at:0,formula:formula)
        XCTAssertEqual(reread.xp,1200)
        let original = try await reopened.growth(localDay:"2026-01-01",at:0)
        XCTAssertEqual(original.xp,1200)
        let laterInventory = try await reopened.inventory()
        XCTAssertEqual(laterInventory.filter { $0.kind != "keepsake" }.map { "\($0.kind):\($0.name)" }, initialInventory.map { "\($0.kind):\($0.name)" })
    }
}

extension StoreTests {
    func testSetupTemperamentAndLastFiveHundredFacts() async throws {
        for (temperament,expected) in [("earnest",64),("cheeky",192)] {
            let (store, _, cleanup) = try makeStore(temperament: temperament)
            defer { cleanup() }
            let traits = try await store.traits(); XCTAssertEqual(traits["cheek"],expected)
            try await store.appendFacts((0..<510).map { StoredFact(fact:.tokens(output:$0),sessionId:"s",project:"p",at:Double($0),day:"2026-01-01") })
            let facts = try await store.facts()
            XCTAssertEqual(facts.count,500); XCTAssertEqual(facts.first?.at,509); XCTAssertEqual(facts.last?.at,10)
        }
    }
}

extension StoreTests {
    func testSavingEmptyMemoryRemovesOptionalKeysAndCorruptLegacyStaysRecoverable() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let legacy = dir.appendingPathComponent("pet-memory.json")
        try Data("broken".utf8).write(to:legacy)
        try await store.migrate()
        XCTAssertFalse(FileManager.default.fileExists(atPath:legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:legacy.path + ".unreadable"))
        var memory = PetMemory.empty; memory.lastSeenAt = 10
        try await store.saveMemory(memory); try await store.saveMemory(.empty)
        let empty = try await store.loadMemory(); XCTAssertEqual(empty,.empty)
        let growth = try await store.award([],active:true,at:0,localDay:"2026-01-01")
        XCTAssertEqual(growth?.xp,10)
    }
}

extension StoreTests {
    @MainActor func testUnreadableLegacyBootstrapStillLoadsGrowthAndPersists() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let legacy = dir.appendingPathComponent("pet-memory.json")
        try Data("not JSON".utf8).write(to: legacy)
        var config = BuddyConfig.default; config.stateDir = dir.path
        let engine = BuddyEngine(config: config)
        engine.start()
        defer { engine.stop() }
        engine.sessionStarted(sessionId: "after-migration", source: "codex", cwd: nil)
        await engine.flushStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".unreadable"))
        XCTAssertEqual(engine.state.growth.xp, 10)
        let saved = try await store.loadMemory()
        XCTAssertEqual(saved?.lastSeenAt, engine.petMemory.lastSeenAt)
        XCTAssertNotNil(saved?.lastSeenAt)
        XCTAssertEqual(saved?.lifetimeSessions, 0)
        XCTAssertFalse(engine.diagnosticLog.entries.contains { $0.category == "store" && $0.event == "error" })
    }
    func testRollupMatchesReplayAcrossCapsMidnightReopenAndBackdatedRows() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let midnight = 86_400_000.0
        for i in 0..<62 {
            let at = midnight - 30 + Double(i)
            let day = at < midnight ? "2026-01-01" : "2026-01-02"
            _ = try await store.award([LedgerRow(at: at, source: .turn, sessionId: "s", day: day)], active: true, at: at, localDay: day)
        }
        for i in 0..<25 {
            let at = midnight + 100 + Double(i)
            _ = try await store.award([LedgerRow(at: at, source: .checkIn, day: "2026-01-02"), LedgerRow(at: at, source: .tokens, amount: 55_000, day: "2026-01-02")], active: false, at: at, localDay: "2026-01-02")
        }
        _ = try await store.award([LedgerRow(at: 0, source: .task, day: "2026-01-01")], active: false, at: 0, localDay: "2026-01-01")
        let reopened = try Store(stateDir: dir.path, now: midnight)
        let rows = try await reopened.ledger()
        let actual = try await reopened.growth(localDay: "2026-01-02", at: midnight)
        XCTAssertEqual(actual, GrowthFormula().snapshot(rows, localDay: "2026-01-02"))
        var tuned = GrowthFormula(); tuned.turn = 0
        let changed = try await reopened.growth(localDay: "2026-01-02", at: midnight, formula: tuned)
        XCTAssertEqual(changed, actual)
    }
}

extension StoreTests {
    func testExistingPerKeySQLiteMemoryMigratesToOneBlob() async throws {
        let (store, dir, cleanup) = try makeStore()
        defer { cleanup() }
        let db = try Database(path: dir.path + "/boop.sqlite")
        try db.run("INSERT INTO memory VALUES('lifetimeSessions','7')")
        try db.run("INSERT INTO memory VALUES('lastSeenAt','500000')")
        try await store.migrate()
        let memory = try await store.loadMemory()
        XCTAssertEqual(memory?.lifetimeSessions, 7)
        XCTAssertEqual(memory?.lastSeenAt, 500_000)
        let keys = try db.run("SELECT key FROM memory")
        XCTAssertEqual(keys, [["memory"]])
        try await store.migrate()
        let again = try await store.loadMemory()
        XCTAssertEqual(again, memory)
    }
}

extension StoreTests {
    func testXPActivityUsesActualCappedAwardsAndProgressIsWithinLevel() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        _ = try await store.award([
            LedgerRow(at: 1, source: .checkIn, amount: 100, day: "2026-01-01"),
            LedgerRow(at: 2, source: .tokens, amount: 200_000, day: "2026-01-01")
        ], active: false, at: 2, localDay: "2026-01-01")
        let source: any EngineStore = store
        let activity = try await source.recentXPActivity()
        XCTAssertEqual(activity.first { $0.source == .checkIn }?.xp, nil)
        XCTAssertEqual(activity.first { $0.source == .tokens }?.xp, nil)
        let level = GrowthSnapshot(level: 5, xp: 1340, xpNext: 410)
        XCTAssertEqual(level.levelStartXP, 1200)
        XCTAssertEqual(level.levelTargetXP, 1750)
        XCTAssertEqual(level.levelProgress, 140.0 / 550.0, accuracy: 0.0001)
    }
}
