import Foundation
import Hummingbird

actor RankingStore {
    let db: Database
    init(path: String) throws {
        db = try Database(path: path)
        try db.run("PRAGMA journal_mode=WAL")
        try db.run("CREATE TABLE IF NOT EXISTS units(unit TEXT PRIMARY KEY, pub TEXT NOT NULL, alg TEXT NOT NULL, buddy_name TEXT NOT NULL, silhouette TEXT NOT NULL, total INTEGER NOT NULL, latest_day TEXT NOT NULL)")
        try db.run("CREATE TABLE IF NOT EXISTS signatures(unit TEXT NOT NULL, day TEXT NOT NULL, xp INTEGER NOT NULL, nonce TEXT NOT NULL, sig TEXT NOT NULL, PRIMARY KEY(unit,day,nonce))")
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    func submit(_ body: LeaderboardSubmission, now: Date = .now) throws {
        let identity = DeviceIdentity(unit: body.unit, pub: body.pub, alg: body.alg)
        guard identity.valid, (1...80).contains(body.buddyName.utf8.count), !body.buddyName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              ["default", "round", "tall"].contains(body.silhouette), body.xpTotal >= 0, (1...400).contains(body.signatures.count) else { throw HTTPError(.badRequest) }
        let signatures = body.signatures.map { LedgerSignature(day: $0.day, xp: $0.xp, nonce: $0.nonce, sig: $0.sig, unit: body.unit) }.sorted { $0.day < $1.day }
        // Day labels originate on the owner's local calendar; allow tomorrow in UTC.
        let tomorrow = Self.day(now.addingTimeInterval(86400))
        guard signatures.allSatisfy({ $0.verified(by: identity) && $0.day <= tomorrow }),
              Set(signatures.map(\.day)).count == signatures.count,
              signatures.last?.xp == body.xpTotal else { throw HTTPError(.badRequest) }
        try db.transaction {
            let old = try db.run("SELECT pub,alg,total,latest_day FROM units WHERE unit=?", [body.unit]).first
            if let old, old[0] != body.pub || old[1] != body.alg { throw HTTPError(.conflict) }
            var prior = old.flatMap { Int($0[2]) } ?? 0
            for signature in signatures {
                guard try db.run("SELECT nonce FROM signatures WHERE unit=? AND day=? AND nonce=?", [body.unit, signature.day, signature.nonce]).isEmpty else { throw HTTPError(.conflict) }
                guard signature.xp >= prior, old.map({ signature.day > $0[3] }) ?? true else { throw HTTPError(.conflict) }
                prior = signature.xp
                try db.run("INSERT INTO signatures VALUES(?,?,?,?,?)", [body.unit, signature.day, String(signature.xp), signature.nonce, signature.sig])
            }
            try db.run("INSERT INTO units VALUES(?,?,?,?,?,?,?) ON CONFLICT(unit) DO UPDATE SET buddy_name=excluded.buddy_name,silhouette=excluded.silhouette,total=excluded.total,latest_day=excluded.latest_day",
                       [body.unit, body.pub, body.alg, body.buddyName, body.silhouette, String(body.xpTotal), signatures.last!.day])
        }
    }
    func rank(unit: String, view: RankView, friends: [String], now: Date = .now) throws -> LeaderboardSnapshot {
        let month = String(Self.day(now).prefix(7)) + "-01"
        var entries: [LeaderboardEntry] = []
        for row in try db.run("SELECT unit,buddy_name,silhouette,total FROM units") {
            if view == .friends && row[0] != unit && !friends.contains(String(row[0].prefix(6)).uppercased()) { continue }
            var total = Int(row[3])!
            if view == .month {
                let baseline = try db.run("SELECT xp FROM signatures WHERE unit=? AND day<? ORDER BY day DESC LIMIT 1", [row[0], month]).first?.first
                total = max(0, total - (baseline.flatMap(Int.init) ?? 0))
            }
            entries.append(.init(unit: row[0], buddyName: row[1], silhouette: row[2], xpTotal: total, rank: 0))
        }
        entries.sort { $0.xpTotal == $1.xpTotal ? $0.unit < $1.unit : $0.xpTotal > $1.xpTotal }
        for i in entries.indices { entries[i].rank = i + 1 }
        return LeaderboardSnapshot(view: view, rank: entries.first(where: { $0.unit == unit })?.rank, entries: Array(entries.prefix(100)))
    }
}

func makeRouter(store: RankingStore) -> Router<BasicRequestContext> {
    let router = Router()
    router.get("/healthz") { _, _ in "ok" }
    router.post("/submit") { request, _ -> Response in
        let buffer = try await request.body.collect(upTo: 200_000)
        let data = Data(buffer.readableBytesView)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(json.keys) == Set(["buddyName", "silhouette", "xpTotal", "signatures", "unit", "pub", "alg"]),
              let xp = json["xpTotal"] as? NSNumber, !["d", "f"].contains(String(cString: xp.objCType)),
              let signatures = json["signatures"] as? [[String: Any]],
              signatures.allSatisfy({ item in
                  guard let xp = item["xp"] as? NSNumber else { return false }
                  return !["d", "f"].contains(String(cString: xp.objCType)) && Set(item.keys) == Set(["day", "xp", "nonce", "sig"])
              }),
              let body = try? JSONDecoder().decode(LeaderboardSubmission.self, from: data) else { throw HTTPError(.badRequest) }
        try await store.submit(body)
        return Response(status: .created)
    }
    router.get("/rank") { request, _ -> LeaderboardSnapshot in
        let query = request.uri.queryParameters
        guard let unit = query["unit"].map(String.init), unit.utf8.count == 16, unit.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              let view = RankView(rawValue: query["view"].map(String.init) ?? "all") else { throw HTTPError(.badRequest) }
        let code = query["code"].map(String.init) ?? String(unit.prefix(6)).uppercased()
        guard code == String(unit.prefix(6)).uppercased() else { throw HTTPError(.badRequest) }
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
