import Foundation
public enum WireError: Error { case invalidSignature }
public struct SubmittedSignature: Codable, Sendable, Equatable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(["day", "xp", "nonce", "sig"]) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected wire fields")) }
        day = try container.decode(String.self, forKey: WireKey("day"))
        xp = try container.decode(Int.self, forKey: WireKey("xp"))
        nonce = try container.decode(String.self, forKey: WireKey("nonce"))
        sig = try container.decode(String.self, forKey: WireKey("sig"))
    }
    public var day: String, xp: Int, nonce: String, sig: String
    public init(_ value: LedgerSignature) { day = value.day; xp = value.xp; nonce = value.nonce; sig = value.sig }
}
/// Deliberately independent of BuddyState, facts, profile and extractor types.
public struct LeaderboardSubmission: Codable, Sendable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(["buddyName", "silhouette", "xpTotal", "signatures", "unit", "pub", "alg"]) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected wire fields")) }
        buddyName = try container.decode(String.self, forKey: WireKey("buddyName"))
        silhouette = try container.decode(String.self, forKey: WireKey("silhouette"))
        xpTotal = try container.decode(Int.self, forKey: WireKey("xpTotal"))
        signatures = try container.decode([SubmittedSignature].self, forKey: WireKey("signatures"))
        unit = try container.decode(String.self, forKey: WireKey("unit"))
        pub = try container.decode(String.self, forKey: WireKey("pub"))
        alg = try container.decode(String.self, forKey: WireKey("alg"))
    }
    public var buddyName: String, silhouette: String, xpTotal: Int
    public var signatures: [SubmittedSignature]
    public var unit: String, pub: String, alg: String
    public init(buddyName: String, silhouette: String, signatures: [LedgerSignature], identity: DeviceIdentity, verifySignatures: Bool = true) throws {
        guard let latest = signatures.max(by: { $0.day < $1.day }) else { throw WireError.invalidSignature }
        if verifySignatures {
            guard let key = identity.publicKey, signatures.allSatisfy({ $0.verified(by: key) }) else { throw WireError.invalidSignature }
        }
        var name = String(buddyName.prefix(80))
        while name.utf8.count > 80 { name.removeLast() }
        self.buddyName = name
        self.silhouette = silhouette; xpTotal = latest.xp
        self.signatures = signatures.map(SubmittedSignature.init)
        unit = identity.unit; pub = identity.pub; alg = identity.alg
    }
}
public enum RankView: String, Codable, CaseIterable, Sendable { case all, month, friends }
public struct LeaderboardEntry: Codable, Sendable, Equatable, Identifiable {
    public var unit: String, buddyName: String, silhouette: String, xpTotal: Int, rank: Int
    public var id: String { unit }
    public init(unit: String, buddyName: String, silhouette: String, xpTotal: Int, rank: Int) { self.unit = unit; self.buddyName = buddyName; self.silhouette = silhouette; self.xpTotal = xpTotal; self.rank = rank }
}
public struct LeaderboardSnapshot: Codable, Sendable, Equatable {
    public var view: RankView, rank: Int?, entries: [LeaderboardEntry]
    public init(view: RankView, rank: Int?, entries: [LeaderboardEntry]) { self.view = view; self.rank = rank; self.entries = entries }
}

private struct WireKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
