import Foundation

struct SubmittedSignature: Codable, Sendable, Equatable {
    var day: String, xp: Int, nonce: String, sig: String
    init(_ value: LedgerSignature) { day = value.day; xp = value.xp; nonce = value.nonce; sig = value.sig }
}
/// Deliberately independent of BuddyState, facts, profile and extractor types.
struct LeaderboardSubmission: Codable, Sendable {
    var buddyName: String, silhouette: String, xpTotal: Int
    var signatures: [SubmittedSignature]
    var unit: String, pub: String, alg: String
    init(buddyName: String, silhouette: String, signatures: [LedgerSignature], identity: DeviceIdentity) throws {
        guard !signatures.isEmpty, signatures.allSatisfy({ $0.verified(by: identity) }), let latest = signatures.max(by: { $0.day < $1.day }) else { throw LeaderboardError.invalidSignature }
        // The service requires a 1–80 byte name; an unnamed buddy is shown as "Boop".
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.buddyName = trimmed.isEmpty ? "Boop" : String(decoding: trimmed.utf8.prefix(80), as: UTF8.self)
        self.silhouette = silhouette; xpTotal = latest.xp
        self.signatures = signatures.map(SubmittedSignature.init)
        unit = identity.unit; pub = identity.pub; alg = identity.alg
    }
}
enum LeaderboardError: Error, CustomStringConvertible {
    case invalidSignature, unavailable(String), rejected(Int), identityChanged, replay
    var description: String {
        switch self {
        case .invalidSignature: return "invalid signature"
        case .unavailable(let why): return "unavailable: \(why)"
        case .rejected(let code): return "rejected: \(code)"
        case .identityChanged: return "identity changed"
        case .replay: return "replay"
        }
    }
}
enum RankView: String, Codable, CaseIterable, Sendable { case all, month, friends }
struct LeaderboardEntry: Codable, Sendable, Equatable, Identifiable {
    var unit: String, buddyName: String, silhouette: String, xpTotal: Int, rank: Int
    var id: String { unit }
}
struct LeaderboardSnapshot: Codable, Sendable, Equatable {
    var view: RankView, rank: Int?, entries: [LeaderboardEntry]
}
struct LeaderboardClient: Sendable {
    var url: URL
    var session: URLSession = .shared
    func submit(_ body: LeaderboardSubmission) async throws {
        var request = URLRequest(url: url.appendingPathComponent("submit"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw LeaderboardError.unavailable("service http \(String(describing: (response as? HTTPURLResponse)?.statusCode))") }
    }
    func rank(unit: String, view: RankView, code: String, friends: [String]) async throws -> LeaderboardSnapshot {
        var parts = URLComponents(url: url.appendingPathComponent("rank"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "unit", value: unit), .init(name: "view", value: view.rawValue), .init(name: "code", value: code),
                            .init(name: "friends", value: String(decoding: try JSONEncoder().encode(friends), as: UTF8.self))]
        let (data, response) = try await session.data(from: parts.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LeaderboardError.unavailable("service http \(String(describing: (response as? HTTPURLResponse)?.statusCode))") }
        return try JSONDecoder().decode(LeaderboardSnapshot.self, from: data)
    }
}
