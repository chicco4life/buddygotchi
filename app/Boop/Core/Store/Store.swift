import Foundation
import BoopSQLite

struct StoredFact: Codable, Sendable, Equatable {
    var fact: Fact, sessionId: String, project: String, at: Double, day: String
}
struct ProfileLine: Codable, Sendable, Equatable {
    var id: Int, line: String, source: String, confidence: Double, createdAt: Double
}
actor Store: EngineStore {
    static let factRetentionMs: Double = 30 * 86_400_000
    private let db: Database
    private let stateDir: String
    private var rollupFormula: GrowthFormula?
    private var ownerGeneration = 0
    private var retiring = false
    init(stateDir: String, now: Double, temperament: String? = nil) throws {
        self.stateDir = stateDir
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        db = try Database(path: stateDir + "/boop.sqlite")
        try db.run("PRAGMA journal_mode=WAL")
        try db.run("PRAGMA secure_delete=ON")
        try db.run("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        let version = Int(try db.run("SELECT value FROM meta WHERE key='schema_version'").first?.first ?? "0") ?? 0
        guard version <= 4 else { throw StoreError(message: "Unsupported store schema \(version)") }
        if version == 0 {
            try db.transaction {
                for sql in [
                    "CREATE TABLE facts(id INTEGER PRIMARY KEY, kind TEXT NOT NULL, session_id TEXT NOT NULL, project TEXT NOT NULL, at REAL NOT NULL, day TEXT NOT NULL, payload_json TEXT NOT NULL)",
                    "CREATE INDEX facts_at ON facts(at)", "CREATE INDEX facts_day ON facts(day)",
                    "CREATE TABLE profile(id INTEGER PRIMARY KEY, line TEXT UNIQUE NOT NULL, source TEXT NOT NULL, confidence REAL NOT NULL, created_at REAL NOT NULL)",
                    "CREATE TABLE traits(axis TEXT PRIMARY KEY, value INTEGER NOT NULL CHECK(value BETWEEN 0 AND 255))",
                    "CREATE TABLE ledger(id INTEGER PRIMARY KEY, at REAL NOT NULL, source TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount>=0), session_id TEXT NOT NULL, day TEXT NOT NULL)",
                    "CREATE INDEX ledger_day ON ledger(day)",
                    "CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger BEGIN SELECT RAISE(ABORT, 'append only'); END",
                    "CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger BEGIN SELECT RAISE(ABORT, 'append only'); END",
                    "CREATE TABLE inventory(kind TEXT NOT NULL, name TEXT NOT NULL, unlocked_at REAL NOT NULL, PRIMARY KEY(kind,name))",
                    "CREATE TABLE memory(key TEXT PRIMARY KEY, json TEXT NOT NULL)",
                    "CREATE TABLE drift(day TEXT NOT NULL, axis TEXT NOT NULL, delta INTEGER NOT NULL, PRIMARY KEY(day,axis))",
                    "INSERT INTO meta VALUES('schema_version','1')"] { try db.run(sql) }
                for axis in ["energy", "cheek", "warmth", "curiosity", "bond"] { try db.run("INSERT INTO traits VALUES(?,?)", [axis, axis == "bond" ? "0" : axis == "cheek" && temperament == "earnest" ? "64" : axis == "cheek" && temperament == "cheeky" ? "192" : "128"]) }
            }
        }
        try db.run("DELETE FROM facts WHERE at < ?", [String(now - Self.factRetentionMs)])
        try db.run("CREATE TABLE IF NOT EXISTS growth_totals(day TEXT NOT NULL, source TEXT NOT NULL, xp INTEGER NOT NULL, units INTEGER NOT NULL, PRIMARY KEY(day,source))")
        // Empty legacy schema retained for old-store compatibility and retirement.
        // Neither rolling limits nor device signing run in the current product.
        try db.run("CREATE TABLE IF NOT EXISTS growth_turns(at REAL NOT NULL, session_id TEXT NOT NULL, units INTEGER NOT NULL)")
        try db.run("CREATE INDEX IF NOT EXISTS growth_turns_session_at ON growth_turns(session_id,at)")
        try db.run("CREATE INDEX IF NOT EXISTS ledger_at ON ledger(at)")
        try db.run("CREATE TABLE IF NOT EXISTS unit(unit TEXT PRIMARY KEY, pub TEXT NOT NULL, alg TEXT NOT NULL, first_seen REAL NOT NULL)")
        try db.run("CREATE TABLE IF NOT EXISTS ledger_signatures(day TEXT NOT NULL, xp INTEGER NOT NULL, nonce TEXT NOT NULL, sig TEXT NOT NULL, unit TEXT NOT NULL, PRIMARY KEY(unit,day), UNIQUE(unit,nonce))")
        try db.run("CREATE TABLE IF NOT EXISTS voice_recent(id INTEGER PRIMARY KEY, day TEXT NOT NULL, line TEXT NOT NULL)")
        try db.run("CREATE TABLE IF NOT EXISTS voice_day(day TEXT NOT NULL, line TEXT NOT NULL, PRIMARY KEY(day,line))")
        try db.run("INSERT OR REPLACE INTO meta VALUES('schema_version','4')")
    }
    func retire() async throws {
        retiring = true
        defer { retiring = false }
        ownerGeneration += 1
        while !reflecting.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        try db.transaction {
            try db.run("DROP TRIGGER ledger_no_delete")
            for table in ["unit", "ledger_signatures", "facts", "profile", "ledger", "inventory", "memory", "drift", "growth_totals", "growth_turns", "voice_recent", "voice_day"] {
                try db.run("DELETE FROM " + table)
            }
            try db.run("UPDATE traits SET value=CASE WHEN axis='bond' THEN 0 ELSE 128 END")
            try db.run("DELETE FROM meta WHERE key NOT IN ('schema_version','memory_migrated')")
            try db.run("INSERT OR REPLACE INTO meta VALUES('memory_migrated','1')")
            try db.run("CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger BEGIN SELECT RAISE(ABORT, 'append only'); END")
        }
        rollupFormula = nil
        try db.run("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func migrate() throws { try StoreMigrator.run(db: db, stateDir: stateDir) }
    func loadMemory() throws -> PetMemory? {
        guard let json = try db.run("SELECT json FROM memory WHERE key='memory'").first?.first else { return nil }
        return try JSONDecoder().decode(PetMemory.self, from: Data(json.utf8))
    }
    func saveMemory(_ memory: PetMemory) throws {
        try db.run("INSERT OR REPLACE INTO memory(key,json) VALUES('memory', ?)", [String(decoding: JSONEncoder().encode(memory), as: UTF8.self)])
    }
    func appendFacts(_ facts: [StoredFact]) throws {
        try db.transaction {
            for f in facts {
                let json = try JSONEncoder().encode(f.fact)
                try db.run("INSERT INTO facts(kind,session_id,project,at,day,payload_json) VALUES(?,?,?,?,?,?)", [f.fact.kind, f.sessionId, f.project, String(f.at), f.day, String(decoding: json, as: UTF8.self)])
            }
        }
    }
    func recentBehaviorMoments() throws -> [BehaviorMemory.RememberedMoment] {
        let facts = try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts WHERE kind IN ('turnCompleted','toolOutcome','errorClass') ORDER BY at DESC,id DESC LIMIT 20"))
        return BehaviorMemory.recentMoments(from: facts)
    }
    func facts() throws -> [StoredFact] { try facts(limit: 500) }
    func facts(limit: Int) throws -> [StoredFact] {
        try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts ORDER BY at DESC,id DESC LIMIT ?", [String(max(0, limit))]))
    }
    private func decodeFacts(_ rows: [[String]]) throws -> [StoredFact] {
        let decoder = JSONDecoder()
        return try rows.map { StoredFact(fact: try decoder.decode(Fact.self, from: Data($0[0].utf8)), sessionId: $0[1], project: $0[2], at: Double($0[3])!, day: $0[4]) }
    }
    func prune(now: Double, localDay: String) throws {
        guard try meta("pruned_day") != localDay else { return }
        try db.run("DELETE FROM facts WHERE at < ?", [String(now - Self.factRetentionMs)])
        try setMeta("pruned_day", localDay)
    }
    func ledger() throws -> [LedgerRow] {
        try db.run("SELECT at,source,amount,session_id,day FROM ledger ORDER BY at,id").map {
            guard let source = XPSource(rawValue: $0[1]) else { throw StoreError(message: "Unknown XP source") }
            return LedgerRow(at: Double($0[0])!, source: source, amount: Int($0[2])!, sessionId: $0[3], day: $0[4])
        }
    }
    func award(_ rows: [LedgerRow], active: Bool, at: Double, localDay: String) throws -> GrowthSnapshot? {
        let formula = GrowthFormula()
        try ensureRollup(formula)
        let rows = rows.filter { $0.source == .turn || $0.source == .activeDay }
        var awarded = !rows.isEmpty
        try db.transaction {
            if active, try db.run("SELECT day FROM growth_totals WHERE source='activeDay' AND day=?", [localDay]).isEmpty {
                awarded = true
                try append(LedgerRow(at: at, source: .activeDay, day: localDay), formula: formula)
            }
            for row in rows { try append(row, formula: formula) }
        }
        return awarded ? try growth(localDay: localDay, at: at) : nil
    }
    private func ensureRollup(_ formula: GrowthFormula) throws {
        guard rollupFormula != formula else { return }
        if try meta("simple_growth_v1") == nil {
            try db.transaction {
                // Existing materialized XP is authoritative; never reprice it.
                if try db.run("SELECT 1 FROM growth_totals LIMIT 1").isEmpty {
                    let stored = try meta("growth_formula")
                    let legacy = stored.flatMap { try? JSONDecoder().decode(LegacyGrowthFormula.self, from: Data($0.utf8)) } ?? LegacyGrowthFormula()
                    for (row, xp) in legacy.awards(try ledger()) { try addTotal(row, xp: xp) }
                }
                try db.run("DELETE FROM growth_turns")
                try setMeta("simple_growth_v1", "1")
            }
        }
        rollupFormula = formula
    }
    private func addTotal(_ row: LedgerRow, xp: Int) throws {
        try db.run("INSERT INTO growth_totals VALUES(?,?,?,?) ON CONFLICT(day,source) DO UPDATE SET xp=xp+excluded.xp,units=units+excluded.units", [row.day, row.source.rawValue, String(xp), String(row.amount)])
    }
    private func append(_ input: LedgerRow, formula: GrowthFormula) throws {
        var row = input; row.amount = max(0, row.amount)
        guard row.source == .turn || row.source == .activeDay else { return }
        if row.source == .activeDay,
           try !db.run("SELECT 1 FROM growth_totals WHERE source='activeDay' AND day=?", [row.day]).isEmpty { return }
        let xp = formula.awards([row]).first!.1
        try db.run("INSERT INTO ledger(at,source,amount,session_id,day) VALUES(?,?,?,?,?)", [String(row.at), row.source.rawValue, String(row.amount), row.sessionId, row.day])
        try addTotal(row, xp: xp)
    }
    func growth(localDay: String, at: Double) throws -> GrowthSnapshot { try growth(localDay: localDay, at: at, formula: GrowthFormula()) }
    func growth(localDay: String, at: Double, formula: GrowthFormula) throws -> GrowthSnapshot {
        try ensureRollup(formula)
        let totals = try db.run("SELECT day,source,xp,units FROM growth_totals")
        let xp = totals.reduce(0) { $0 + Int($1[2])! }
        let days = totals.filter { $0[1] == "activeDay" }.map { $0[0] }
        let streak = Streak.calculate(days: days, through: localDay)
        let biggest = CheerSize(rawValue: try meta("biggest") ?? "hop") ?? .hop
        let result = GrowthSnapshot(level: formula.level(for: xp), xp: xp, xpNext: formula.xpToNext(for: xp), streak: streak.current,
            bestStreak: streak.best, daysTogether: days.count,
            tasks: totals.filter { $0[1] == "turn" }.reduce(0) { $0 + Int($1[3])! },
            today: totals.filter { $0[0] == localDay }.reduce(0) { $0 + Int($1[2])! }, biggest: biggest)
        return result
    }
    func recentXPActivity() async throws -> [XPActivity] {
        try ensureRollup(GrowthFormula())
        return try db.run("SELECT day,source,xp FROM growth_totals WHERE xp>0 ORDER BY day DESC,source LIMIT 60").compactMap {
            guard let source = XPSource(rawValue: $0[1]), let xp = Int($0[2]) else { return nil }
            return XPActivity(day: $0[0], source: source, xp: xp)
        }
    }
    func inventory() throws -> [InventoryItem] {
        let recorded = try db.run("SELECT kind,name,unlocked_at FROM inventory ORDER BY kind,name").map {
            InventoryItem(kind: $0[0], name: $0[1], unlockedAt: Double($0[2])!)
        }
        // Preserve historical timestamps and keepsakes without requiring an award,
        // migration, or growth calculation to make the full catalog available.
        let available = CompanionOption.catalog.filter { option in
            !recorded.contains { $0.kind == option.kind && $0.name == option.name }
        }.map { InventoryItem(kind: $0.kind, name: $0.name, unlockedAt: 0) }
        return (recorded + available).sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }
    func recordCheer(_ size: CheerSize) throws {
        let old = CheerSize(rawValue: try meta("biggest") ?? "hop") ?? .hop
        if size.intensity > old.intensity { try setMeta("biggest", size.rawValue) }
    }
    func cosmetic() throws -> EquippedCosmetic {
        // One product appearance. Old saved choices remain stored but inactive.
        EquippedCosmetic()
    }
    func equip(_ cosmetic: EquippedCosmetic) throws {
        guard cosmetic == EquippedCosmetic() else { throw StoreError(message: "Appearance customization is unavailable") }
        try setMeta("equipped", String(decoding: JSONEncoder().encode(cosmetic), as: UTF8.self))
    }
    func profile() throws -> [ProfileLine] {
        try db.run("SELECT id,line,source,confidence,created_at FROM profile ORDER BY id").map {
            ProfileLine(id: Int($0[0])!, line: $0[1], source: $0[2], confidence: Double($0[3])!, createdAt: Double($0[4])!)
        }
    }
    func clearProfile() throws { try db.run("DELETE FROM profile"); try db.run("PRAGMA wal_checkpoint(TRUNCATE)") }
    func deleteProfileLine(_ id: Int) throws { try db.run("DELETE FROM profile WHERE id=?", [String(id)]); try db.run("PRAGMA wal_checkpoint(TRUNCATE)") }
    func addProfileLine(_ line: String, source: String, at: Double) throws {
        try db.run("INSERT INTO profile(line,source,confidence,created_at) VALUES(?,?,0.6,?) ON CONFLICT(line) DO UPDATE SET confidence=min(1.0,confidence+0.1)", [line,source,String(at)])
    }
    func traits() async throws -> [String: Int] { Dictionary(uniqueKeysWithValues: try db.run("SELECT axis,value FROM traits").map { ($0[0], Int($0[1])!) }) }

    private var reflectionVoice: Voice?
    private var voiceLanguage = "en"
    private var reflecting: Set<String> = []
    func configureVoice(_ voice: Voice, language: String) async {
        reflectionVoice = voice; voiceLanguage = language
    }
    func facts(localDay: String) async throws -> [StoredFact] {
        try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts WHERE day=? ORDER BY at,id", [localDay]))
    }
    func voiceExclusions(localDay: String) async throws -> [String] {
        try db.run("SELECT line FROM voice_day WHERE day=? UNION SELECT line FROM voice_recent", [localDay]).map { $0[0] }
    }
    func rememberVoice(_ line: String, localDay: String) async throws {
        try db.transaction {
            try db.run("INSERT INTO voice_recent(day,line) VALUES(?,?)", [localDay,line])
            try db.run("DELETE FROM voice_recent WHERE id NOT IN (SELECT id FROM voice_recent ORDER BY id DESC LIMIT 20)")
            try db.run("DELETE FROM voice_day WHERE day<>?", [localDay])
            try db.run("INSERT OR IGNORE INTO voice_day VALUES(?,?)", [localDay,line])
        }
    }
    func reflect(localDay: String, at: Double) async throws -> [ProfileLine] {
        guard !retiring else { return [] }
        guard try meta("reflected_" + localDay) == nil, reflecting.insert(localDay).inserted else { return try profile() }
        defer { reflecting.remove(localDay) }
        let generation = ownerGeneration
        let history = try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts WHERE day<=? ORDER BY at,id", [localDay]))
        guard let voice = reflectionVoice else { return try profile() }
        let context = try profile().map(\.line)
        guard let update = await voice.reflect(history: history, profile: context, day: localDay, language: voiceLanguage) else { return try profile() }
        guard generation == ownerGeneration, !retiring else { return [] }
        try db.transaction {
            for memory in update.memories { try addProfileLine(memory.line, source: "model", at: at) }
            try setMeta("reflected_" + localDay, "1")
        }
        return try profile()
    }
    private func meta(_ key: String) throws -> String? { try db.run("SELECT value FROM meta WHERE key=?", [key]).first?.first }
    private func setMeta(_ key: String, _ value: String) throws { try db.run("INSERT OR REPLACE INTO meta VALUES(?,?)", [key,value]) }
}

struct InventoryItem: Codable, Sendable, Equatable {
    var kind: String, name: String, unlockedAt: Double
}

enum StoreMigrator {
    static func run(db: Database, stateDir: String) throws {
        // Upgrade Phase 4's per-key memory without changing its Codable representation.
        let rows = try db.run("SELECT key,json FROM memory WHERE key != 'memory'")
        if !rows.isEmpty {
            let json = "{" + rows.map { "\"" + $0[0] + "\":" + $0[1] }.joined(separator: ",") + "}"
            let memory = try JSONDecoder().decode(PetMemory.self, from: Data(json.utf8))
            try db.transaction {
                try db.run("INSERT OR IGNORE INTO memory VALUES('memory',?)", [String(decoding: JSONEncoder().encode(memory), as: UTF8.self)])
                try db.run("DELETE FROM memory WHERE key != 'memory'")
            }
        }
        let legacy = stateDir + "/pet-memory.json"
        if FileManager.default.fileExists(atPath: legacy) {
            var suffix = ".migrated"
            if try db.run("SELECT key FROM meta WHERE key='memory_migrated'").isEmpty {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: legacy)), let memory = try? JSONDecoder().decode(PetMemory.self, from: data) {
                    try db.transaction {
                        try db.run("INSERT OR IGNORE INTO memory VALUES('memory',?)", [String(decoding: JSONEncoder().encode(memory), as: UTF8.self)])
                        try db.run("INSERT INTO meta VALUES('memory_migrated','1')")
                    }
                } else { suffix = ".unreadable" }
            }
            var destination = legacy + suffix
            if FileManager.default.fileExists(atPath: destination) { destination += "." + UUID().uuidString }
            try FileManager.default.moveItem(atPath: legacy, toPath: destination)
        }
    }
}

/// Engine persistence seam. Production uses SQLite; tests can suspend individual operations.
protocol EngineStore: AnyObject, Sendable {
    func retire() async throws

    func traits() async throws -> Traits
    func configureVoice(_ voice: Voice, language: String) async
    func facts(localDay: String) async throws -> [StoredFact]
    func voiceExclusions(localDay: String) async throws -> [String]
    func rememberVoice(_ line: String, localDay: String) async throws
    func migrate() async throws
    func loadMemory() async throws -> PetMemory?
    func saveMemory(_ memory: PetMemory) async throws
    func appendFacts(_ facts: [StoredFact]) async throws
    func facts() async throws -> [StoredFact]
    func recentBehaviorMoments() async throws -> [BehaviorMemory.RememberedMoment]
    func award(_ rows: [LedgerRow], active: Bool, at: Double, localDay: String) async throws -> GrowthSnapshot?
    func growth(localDay: String, at: Double) async throws -> GrowthSnapshot
    func cosmetic() async throws -> EquippedCosmetic
    func recordCheer(_ size: CheerSize) async throws
    func prune(now: Double, localDay: String) async throws
    func reflect(localDay: String, at: Double) async throws -> [ProfileLine]
    func profile() async throws -> [ProfileLine]
    func inventory() async throws -> [InventoryItem]
    func recentXPActivity() async throws -> [XPActivity]
    func deleteProfileLine(_ id: Int) async throws
    func clearProfile() async throws
    func equip(_ cosmetic: EquippedCosmetic) async throws
}

// Memory-only test stores can opt into voice persistence independently.
extension EngineStore {
    func recentBehaviorMoments() async throws -> [BehaviorMemory.RememberedMoment] {
        BehaviorMemory.recentMoments(from: try await facts())
    }
    func recentXPActivity() async throws -> [XPActivity] { [] }
    func retire() async throws { throw StoreError(message: "Retire is unavailable") }

    func traits() async throws -> Traits { [:] }
    func configureVoice(_ voice: Voice, language: String) async {}
    func facts(localDay: String) async throws -> [StoredFact] { try await facts().filter { $0.day == localDay } }
    func voiceExclusions(localDay: String) async throws -> [String] { [] }
    func rememberVoice(_ line: String, localDay: String) async throws {}
}
