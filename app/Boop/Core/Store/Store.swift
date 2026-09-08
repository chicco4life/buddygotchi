import Foundation
import SQLite3

struct StoredFact: Codable, Sendable, Equatable {
    var fact: Fact, sessionId: String, project: String, at: Double, day: String
}
struct ProfileLine: Codable, Sendable, Equatable {
    var id: Int, line: String, source: String, confidence: Double, createdAt: Double
}
struct StoreError: Error, Sendable { var message: String }
/// Owned exclusively by Store. Statements never escape the actor.
private final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            sqlite3_close(handle); handle = nil; throw StoreError(message: message)
        }
        sqlite3_busy_timeout(handle, 5000)
    }
    deinit { sqlite3_close(handle) }
    @discardableResult func run(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let rc = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard rc == SQLITE_OK else { throw failure() }
        }
        var rows: [[String]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
                })
            case SQLITE_DONE: return rows
            default: throw failure()
            }
        }
    }
    private func failure() -> StoreError { StoreError(message: String(cString: sqlite3_errmsg(handle))) }
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do { let result = try operation(); try run("COMMIT"); return result }
        catch { _ = try? run("ROLLBACK"); throw error }
    }
}

actor Store {
    private let db: Database
    init(stateDir: String, now: Double, temperament: String? = nil) throws {
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        db = try Database(path: stateDir + "/boop.sqlite")
        try db.run("PRAGMA journal_mode=WAL")
        try db.run("PRAGMA secure_delete=ON")
        try db.run("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        let version = Int(try db.run("SELECT value FROM meta WHERE key='schema_version'").first?.first ?? "0") ?? 0
        guard version <= 1 else { throw StoreError(message: "Unsupported store schema \(version)") }
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
        try db.run("DELETE FROM facts WHERE at < ?", [String(now - 30 * 86_400_000)])
        let legacy = URL(fileURLWithPath: stateDir + "/pet-memory.json")
        if FileManager.default.fileExists(atPath: legacy.path) {
            // Commit before rename. A crash between them retries only the rename.
            if try db.run("SELECT key FROM meta WHERE key='memory_migrated'").isEmpty {
                // Leave an unreadable legacy file for recovery without disabling SQLite.
                guard let data = try? Data(contentsOf: legacy), let memory = try? JSONDecoder().decode(PetMemory.self, from: data) else { return }
                let object = try JSONDecoder().decode([String: HookJSON].self, from: JSONEncoder().encode(memory))
                try db.transaction {
                    for (key, value) in object { try db.run("INSERT OR REPLACE INTO memory VALUES(?,?)", [key, String(decoding: try JSONEncoder().encode(value), as: UTF8.self)]) }
                    try db.run("INSERT INTO meta VALUES('memory_migrated','1')")
                }
            }
            if !FileManager.default.fileExists(atPath: legacy.path + ".migrated") { try FileManager.default.moveItem(atPath: legacy.path, toPath: legacy.path + ".migrated") }
        }
    }
    func loadMemory() throws -> PetMemory? {
        let rows = try db.run("SELECT key,json FROM memory")
        guard !rows.isEmpty else { return nil }
        let object = try Dictionary(uniqueKeysWithValues: rows.map { ($0[0], try JSONDecoder().decode(HookJSON.self, from: Data($0[1].utf8))) })
        return try JSONDecoder().decode(PetMemory.self, from: JSONEncoder().encode(object))
    }
    func saveMemory(_ memory: PetMemory) throws {
        let object = try JSONDecoder().decode([String: HookJSON].self, from: JSONEncoder().encode(memory))
        try db.transaction {
            try db.run("DELETE FROM memory")
            for (key, value) in object { try db.run("INSERT OR REPLACE INTO memory VALUES(?,?)", [key, String(decoding: try JSONEncoder().encode(value), as: UTF8.self)]) }
        }
    }
    func appendFacts(_ facts: [StoredFact]) throws {
        try db.transaction {
            for f in facts {
                let json = try JSONEncoder().encode(f.fact)
                let kind = try JSONDecoder().decode([String: HookJSON].self, from: json).keys.first ?? "unknown"
                try db.run("INSERT INTO facts(kind,session_id,project,at,day,payload_json) VALUES(?,?,?,?,?,?)", [kind, f.sessionId, f.project, String(f.at), f.day, String(decoding: json, as: UTF8.self)])
            }
        }
    }
    func facts(limit: Int = 500) throws -> [StoredFact] {
        try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts ORDER BY at DESC,id DESC LIMIT ?", [String(max(0, limit))]))
    }
    private func decodeFacts(_ rows: [[String]]) throws -> [StoredFact] {
        try rows.map { StoredFact(fact: try JSONDecoder().decode(Fact.self, from: Data($0[0].utf8)), sessionId: $0[1], project: $0[2], at: Double($0[3])!, day: $0[4]) }
    }
    func prune(now: Double, localDay: String) throws {
        guard try meta("pruned_day") != localDay else { return }
        try db.run("DELETE FROM facts WHERE at < ?", [String(now - 30 * 86_400_000)])
        try setMeta("pruned_day", localDay)
    }
    func ledger() throws -> [LedgerRow] {
        try db.run("SELECT at,source,amount,session_id,day FROM ledger ORDER BY at,id").map {
            guard let source = XPSource(rawValue: $0[1]) else { throw StoreError(message: "Unknown XP source") }
            return LedgerRow(at: Double($0[0])!, source: source, amount: Int($0[2])!, sessionId: $0[3], day: $0[4])
        }
    }
    func award(_ rows: [LedgerRow], active: Bool, at: Double, localDay: String) throws -> GrowthSnapshot {
        try db.transaction {
            if active, try db.run("SELECT id FROM ledger WHERE source='activeDay' AND day=? LIMIT 1", [localDay]).isEmpty {
                try append(LedgerRow(at: at, source: .activeDay, day: localDay))
                let days = try db.run("SELECT day FROM ledger WHERE source='activeDay'").map { $0[0] }
                try append(LedgerRow(at: at, source: .streakBonus, amount: Streak.calculate(days: days, through: localDay).current, day: localDay))
                try incrementBond(1)
            }
            for row in rows { try append(row) }
        }
        return try growth(localDay: localDay, at: at)
    }
    private func append(_ row: LedgerRow) throws {
        try db.run("INSERT INTO ledger(at,source,amount,session_id,day) VALUES(?,?,?,?,?)", [String(row.at), row.source.rawValue, String(max(0,row.amount)), row.sessionId, row.day])
    }
    func growth(localDay: String, at: Double, formula: GrowthFormula = GrowthFormula()) throws -> GrowthSnapshot {
        let biggest = CheerSize(rawValue: try meta("biggest") ?? "hop") ?? .hop
        let result = formula.snapshot(try ledger(), localDay: localDay, biggest: biggest)
        for unlock in CosmeticUnlock.schedule where unlock.level <= result.level {
            try db.run("INSERT OR IGNORE INTO inventory VALUES(?,?,?)", [unlock.kind, unlock.name, String(at)])
        }
        for (met, name) in [(biggest == .dance, "first-dance"), (result.tasks >= 100, "100th-task"), (result.bestStreak >= 30, "30-day-streak")] where met {
            try db.run("INSERT OR IGNORE INTO inventory VALUES('keepsake',?,?)", [name, String(at)])
        }
        return result
    }
    func recordCheer(_ size: CheerSize) throws {
        let old = CheerSize(rawValue: try meta("biggest") ?? "hop") ?? .hop
        if size.intensity > old.intensity { try setMeta("biggest", size.rawValue) }
    }
    func cosmetic() throws -> EquippedCosmetic {
        guard let text = try meta("equipped") else { return EquippedCosmetic() }
        return try JSONDecoder().decode(EquippedCosmetic.self, from: Data(text.utf8))
    }
    func equip(_ cosmetic: EquippedCosmetic) throws {
        for (kind,name) in [("skin",cosmetic.skin),("accessory",cosmetic.accessory),("silhouette",cosmetic.silhouette)] {
            guard try !db.run("SELECT name FROM inventory WHERE kind=? AND name=?", [kind,name]).isEmpty else { throw StoreError(message: "Cosmetic is locked") }
        }
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
    func traits() throws -> [String: Int] { Dictionary(uniqueKeysWithValues: try db.run("SELECT axis,value FROM traits").map { ($0[0], Int($0[1])!) }) }
    func applyDrift(_ deltas: [String: Int], localDay: String) throws {
        try db.transaction { try drift(deltas, localDay: localDay) }
    }
    private func drift(_ deltas: [String: Int], localDay: String) throws {
        for axis in ["energy", "cheek", "warmth", "curiosity"] {
            let prior = Int(try db.run("SELECT delta FROM drift WHERE day=? AND axis=?", [localDay,axis]).first?.first ?? "0") ?? 0
            let total = min(3,max(-3, prior + min(3,max(-3,deltas[axis,default:0]))))
            try db.run("UPDATE traits SET value=max(0,min(255,value+?)) WHERE axis=?", [String(total-prior),axis])
            try db.run("INSERT OR REPLACE INTO drift VALUES(?,?,?)", [localDay,axis,String(total)])
        }
    }
    private func incrementBond(_ amount: Int) throws { try db.run("UPDATE traits SET value=min(255,value+?) WHERE axis='bond'", [String(max(0,amount))]) }
    func bond(collected: Bool, greetAfterAbsence: Bool, localDay: String) throws {
        try db.transaction {
            if collected {
                let count = Int(try meta("collect_" + localDay) ?? "0") ?? 0
                if count < 3 { try incrementBond(1); try setMeta("collect_" + localDay, String(count+1)) }
            }
            if greetAfterAbsence { try incrementBond(2) }
        }
    }
    func reflect(localDay: String, at: Double) throws -> [ProfileLine] {
        guard try meta("reflected_" + localDay) == nil else { return try profile() }
        let history = try decodeFacts(db.run("SELECT payload_json,session_id,project,at,day FROM facts WHERE day<=? ORDER BY at,id", [localDay]))
        let daily = history.filter { $0.day == localDay }
        let candidates = Reflection.candidates(day: daily, history: history, localDay: localDay)
        try db.transaction {
            for line in candidates.prefix(5) { try addProfileLine(line, source: "rules", at: at) }
            try drift(DailyDrift.calculate(daily, history: history), localDay: localDay)
            if daily.contains(where: { $0.fact == .moment(.lateNight) }) { try db.run("INSERT OR IGNORE INTO inventory VALUES('keepsake','first-late-night',?)", [String(at)]) }
            try setMeta("reflected_" + localDay, "1")
        }
        return try profile()
    }
    private func meta(_ key: String) throws -> String? { try db.run("SELECT value FROM meta WHERE key=?", [key]).first?.first }
    private func setMeta(_ key: String, _ value: String) throws { try db.run("INSERT OR REPLACE INTO meta VALUES(?,?)", [key,value]) }
}
