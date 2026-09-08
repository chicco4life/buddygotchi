import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import CSignature
#endif

public func friendsCode(_ unit: String) -> String { String(unit.prefix(6)).uppercased() }
public struct DeviceIdentity: Codable, Sendable, Equatable {
    public var unit: String, pub: String, alg: String
    public init(unit: String, pub: String, alg: String) { self.unit = unit; self.pub = pub; self.alg = alg }
    public static func unit(publicKey bytes: Data) -> String {
        #if canImport(CryptoKit)
        let digest = Array(SHA256.hash(data: bytes))
        #else
        var digest = [UInt8](repeating: 0, count: 32)
        bytes.withUnsafeBytes { _ = boop_public($0.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &digest) }
        #endif
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    public var publicKey: SigningPublicKey? {
        guard alg == "p256", let bytes = Data(base64Encoded: pub), bytes.count == 65,
              unit == Self.unit(publicKey: bytes) else { return nil }
        return SigningPublicKey(bytes: bytes, unit: unit)
    }
    public var valid: Bool { publicKey != nil }
    public var friendsCode: String { LeaderboardWire.friendsCode(unit) }
}
public struct SigningPublicKey: Sendable {
    let unit: String
    #if canImport(CryptoKit)
    let key: P256.Signing.PublicKey
    #else
    let bytes: Data
    #endif
    init?(bytes: Data, unit: String) {
        self.unit = unit
        #if canImport(CryptoKit)
        guard let key = try? P256.Signing.PublicKey(x963Representation: bytes) else { return nil }
        self.key = key
        #else
        var digest = [UInt8](repeating: 0, count: 32)
        guard bytes.withUnsafeBytes({ boop_public($0.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &digest) }) == 1 else { return nil }
        self.bytes = bytes
        #endif
    }
    func verify(_ signature: Data, message: Data) -> Bool {
        #if canImport(CryptoKit)
        guard let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
        return key.isValidSignature(sig, for: message)
        #else
        return bytes.withUnsafeBytes { p in signature.withUnsafeBytes { s in message.withUnsafeBytes { m in
            boop_verify(p.bindMemory(to: UInt8.self).baseAddress!, bytes.count, s.bindMemory(to: UInt8.self).baseAddress!, signature.count, m.bindMemory(to: UInt8.self).baseAddress!, message.count) == 1
        } } }
        #endif
    }
}
public struct LedgerSignature: Codable, Sendable, Equatable {
    public var day: String, xp: Int, nonce: String, sig: String, unit: String
    public init(day: String, xp: Int, nonce: String, sig: String, unit: String) {
        self.day = day; self.xp = xp; self.nonce = nonce; self.sig = sig; self.unit = unit
    }
    public func verified(by identity: DeviceIdentity) -> Bool {
        guard let key = identity.publicKey else { return false }
        return verified(by: key)
    }
    public func verified(by key: SigningPublicKey) -> Bool {
        guard unit == key.unit, xp >= 0, day.utf8.count == 10,
              day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              (2...64).contains(nonce.utf8.count), nonce.utf8.count.isMultiple(of: 2),
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let bytes = Data(base64Encoded: sig) else { return false }
        return key.verify(bytes, message: Data("\(unit)|\(day)|\(xp)|\(nonce)".utf8))
    }
}
