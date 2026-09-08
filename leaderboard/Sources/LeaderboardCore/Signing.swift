import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import CSignature
#endif

struct DeviceIdentity: Codable, Sendable, Equatable {
    var unit: String, pub: String, alg: String
    var valid: Bool {
        guard alg == "p256", let bytes = Data(base64Encoded: pub), bytes.count == 65 else { return false }
        #if canImport(CryptoKit)
        return unit == SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined() && (try? P256.Signing.PublicKey(x963Representation: bytes)) != nil
        #else
        var digest = [UInt8](repeating: 0, count: 32)
        let valid = bytes.withUnsafeBytes { boop_public($0.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &digest) }
        return valid == 1 && unit == digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        #endif
    }
    var friendsCode: String { String(unit.prefix(6)).uppercased() }
}
struct LedgerSignature: Codable, Sendable, Equatable {
    var day: String, xp: Int, nonce: String, sig: String, unit: String
    func verified(by identity: DeviceIdentity) -> Bool {
        guard unit == identity.unit, xp >= 0, day.utf8.count == 10,
              day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              (2...64).contains(nonce.utf8.count), nonce.utf8.count.isMultiple(of: 2),
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              identity.valid, let bytes = Data(base64Encoded: sig), let pub = Data(base64Encoded: identity.pub) else { return false }
        let message = Data("\(unit)|\(day)|\(xp)|\(nonce)".utf8)
        #if canImport(CryptoKit)
        guard let key = try? P256.Signing.PublicKey(x963Representation: pub), let signature = try? P256.Signing.ECDSASignature(derRepresentation: bytes) else { return false }
        return key.isValidSignature(signature, for: message)
        #else
        return pub.withUnsafeBytes { p in bytes.withUnsafeBytes { s in message.withUnsafeBytes { m in
            boop_verify(p.bindMemory(to: UInt8.self).baseAddress!, pub.count, s.bindMemory(to: UInt8.self).baseAddress!, bytes.count, m.bindMemory(to: UInt8.self).baseAddress!, message.count) == 1
        } } }
        #endif
    }
}
