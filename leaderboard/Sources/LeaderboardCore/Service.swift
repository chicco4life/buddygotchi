import BoopSQLite
import LeaderboardWire
import Foundation
import Hummingbird

actor RankingStore {
    let db: Database
    init(path: String) throws {
        db = try Database(path: path)
        try db.run("PRAGMA journal_mode=WAL")
        try db.run("CREATE TABLE IF NOT EXISTS units(unit TEXT PRIMARY KEY, pub TEXT NOT NULL, alg TEXT NOT NULL, buddy_name TEXT NOT NULL, silhouette TEXT NOT NULL, total INTEGER NOT NULL, latest_day TEXT NOT NULL)")
        try db.run("CREATE TABLE IF NOT EXISTS signatures(unit TEXT NOT NULL, day TEXT NOT NULL, xp INTEGER NOT NULL, nonce TEXT NOT NULL, sig TEXT NOT NULL, PRIMARY KEY(unit,day,nonce))")
        try db.run("CREATE INDEX IF NOT EXISTS signatures_unit_day ON signatures(unit,day)")
    }
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    func submit(_ body: LeaderboardSubmission, now: Date = .now) throws {
        let identity = DeviceIdentity(unit: body.unit, pub: body.pub, alg: body.alg)
        guard let key = identity.publicKey, (1...80).contains(body.buddyName.utf8.count), !body.buddyName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              ["default", "round", "tall"].contains(body.silhouette), body.xpTotal >= 0, (1...400).contains(body.signatures.count) else { throw HTTPError(.badRequest) }
        let signatures = body.signatures.map { LedgerSignature(day: $0.day, xp: $0.xp, nonce: $0.nonce, sig: $0.sig, unit: body.unit) }.sorted { $0.day < $1.day }
        // Day labels originate on the owner's local calendar; allow tomorrow in UTC.
        let tomorrow = Self.day(now.addingTimeInterval(86400))
        guard signatures.allSatisfy({ $0.verified(by: key) && $0.day <= tomorrow }),
              Set(signatures.map(\.day)).count == signatures.count,
              signatures.last?.xp == body.xpTotal else { throw HTTPError(.badRequest) }
        try db.transaction {
            let old = try db.run("SELECT pub,alg,total,latest_day FROM units WHERE unit=?", [body.unit]).first
            if let old, old[0] != body.pub || old[1] != body.alg { throw HTTPError(.conflict) }
            var prior = old.flatMap { Int($0[2]) } ?? 0
            for signature in signatures {
                guard signature.xp >= prior, old.map({ signature.day > $0[3] }) ?? true else { throw HTTPError(.conflict) }
                prior = signature.xp
                do { try db.run("INSERT INTO signatures VALUES(?,?,?,?,?)", [body.unit, signature.day, String(signature.xp), signature.nonce, signature.sig]) }
                catch let error as StoreError where error.code == 19 { throw HTTPError(.conflict) }
            }
            try db.run("INSERT INTO units VALUES(?,?,?,?,?,?,?) ON CONFLICT(unit) DO UPDATE SET buddy_name=excluded.buddy_name,silhouette=excluded.silhouette,total=excluded.total,latest_day=excluded.latest_day",
                       [body.unit, body.pub, body.alg, body.buddyName, body.silhouette, String(body.xpTotal), signatures.last!.day])
        }
    }
    func rank(unit: String, view: RankView, friends: [String], now: Date = .now) throws -> LeaderboardSnapshot {
        let month = String(Self.day(now).prefix(7)) + "-01"
        let total = view == .month ? "MAX(0, u.total - COALESCE((SELECT xp FROM signatures s WHERE s.unit=u.unit AND s.day<? ORDER BY day DESC LIMIT 1),0))" : "u.total"
        var values = view == .month ? [month] : []
        var filter = ""
        if view == .friends {
            filter = "WHERE u.unit=? OR UPPER(SUBSTR(u.unit,1,6)) IN (" + Array(repeating: "?", count: friends.count).joined(separator: ",") + ")"
            values += [unit] + friends
        }
        let ranked = "WITH scores AS (SELECT u.unit,u.buddy_name,u.silhouette, \(total) AS total FROM units u \(filter)), ranked AS (SELECT *, ROW_NUMBER() OVER (ORDER BY total DESC,unit) AS rank FROM scores) "
        let entries = try db.run(ranked + "SELECT unit,buddy_name,silhouette,total,rank FROM ranked ORDER BY total DESC,unit LIMIT 100", values).map {
            LeaderboardEntry(unit: $0[0], buddyName: $0[1], silhouette: $0[2], xpTotal: Int($0[3])!, rank: Int($0[4])!)
        }
        let ownRank = try db.run(ranked + "SELECT rank FROM ranked WHERE unit=? LIMIT 1", values + [unit]).first?.first.flatMap(Int.init)
        return LeaderboardSnapshot(view: view, rank: ownRank, entries: entries)
    }
}

func makeRouter(store: RankingStore) -> Router<BasicRequestContext> {
    let router = Router()
    router.get("/healthz") { _, _ in "ok" }
    router.post("/submit") { request, _ -> Response in
        let buffer = try await request.body.collect(upTo: 200_000)
        let data = Data(buffer.readableBytesView)
        guard let body = try? SubmissionDecoder.decode(data) else { throw HTTPError(.badRequest) }
        try await store.submit(body)
        return Response(status: .created)
    }
    router.get("/rank") { request, _ -> LeaderboardSnapshot in
        let query = request.uri.queryParameters
        guard let unit = query["unit"].map(String.init), unit.utf8.count == 16, unit.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              let view = RankView(rawValue: query["view"].map(String.init) ?? "all") else { throw HTTPError(.badRequest) }
        let code = query["code"].map(String.init) ?? friendsCode(unit)
        guard code == friendsCode(unit) else { throw HTTPError(.badRequest) }
        let raw = query["friends"].map(String.init) ?? "[]"
        guard raw.utf8.count <= 4096, let friends = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)), friends.count <= 100,
              friends.allSatisfy({ $0.utf8.count == 6 && $0.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil }) else { throw HTTPError(.badRequest) }
        return try await store.rank(unit: unit, view: view, friends: friends)
    }
    return router
}

public func runLeaderboard(port: Int, database: String) async throws {
    let store = try RankingStore(path: database)
    let app = Application(router: makeRouter(store: store), configuration: .init(address: .hostname("0.0.0.0", port: port)))
    try await app.runService()
}
