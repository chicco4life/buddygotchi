import Foundation
import Hummingbird

struct SubmittedSignature: Codable, Sendable, Equatable, ResponseCodable {
    var day: String, xp: Int, nonce: String, sig: String
    init(_ value: LedgerSignature) { day = value.day; xp = value.xp; nonce = value.nonce; sig = value.sig }
}
/// Deliberately independent of BuddyState, facts, profile and extractor types.
struct LeaderboardSubmission: Codable, Sendable, ResponseCodable {
    var buddyName: String, silhouette: String, xpTotal: Int
    var signatures: [SubmittedSignature]
    var unit: String, pub: String, alg: String
    init(buddyName: String, silhouette: String, signatures: [LedgerSignature], identity: DeviceIdentity) throws {
        guard !signatures.isEmpty, signatures.allSatisfy({ $0.verified(by: identity) }), let latest = signatures.max(by: { $0.day < $1.day }) else { throw LeaderboardError.invalidSignature }
        self.buddyName = buddyName; self.silhouette = silhouette; xpTotal = latest.xp
        self.signatures = signatures.map(SubmittedSignature.init)
        unit = identity.unit; pub = identity.pub; alg = identity.alg
    }
}
enum LeaderboardError: Error { case invalidSignature, unavailable, rejected(Int), identityChanged, replay }
enum RankView: String, Codable, CaseIterable, Sendable { case all, month, friends }
struct LeaderboardEntry: Codable, Sendable, Equatable, Identifiable {
    var unit: String, buddyName: String, silhouette: String, xpTotal: Int, rank: Int
    var id: String { unit }
}
struct LeaderboardSnapshot: Codable, Sendable, Equatable, ResponseCodable {
    var view: RankView, rank: Int?, entries: [LeaderboardEntry]
}
