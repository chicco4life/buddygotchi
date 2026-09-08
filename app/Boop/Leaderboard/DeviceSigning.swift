import Foundation
import CryptoKit

struct DeviceIdentity: Codable, Sendable, Equatable {
    var unit: String, pub: String, alg: String
    var publicKey: P256.Signing.PublicKey? {
        guard alg == "p256", let bytes = Data(base64Encoded: pub), bytes.count == 65,
              unit == SHA256.hash(data: bytes).prefix(8).map({ String(format: "%02x", $0) }).joined() else { return nil }
        return try? P256.Signing.PublicKey(x963Representation: bytes)
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
              let key = identity.publicKey, let bytes = Data(base64Encoded: sig),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: bytes) else { return false }
        return key.isValidSignature(signature, for: Data("\(unit)|\(day)|\(xp)|\(nonce)".utf8))
    }
}
struct SignRequest: Encodable, Sendable, Equatable {
    let cmd = "sign"
    var day: String, xp: Int, nonce: String
    init(day: String, xp: Int) {
        self.day = day; self.xp = xp
        var generator = SystemRandomNumberGenerator()
        nonce = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }
}
/// Software fixture. Constructed only by the explicitly gated headless route.
struct TestDeviceSigner {
    private let key = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x42, count: 32))
    var identity: DeviceIdentity {
        let pub = key.publicKey.x963Representation
        return DeviceIdentity(unit: SHA256.hash(data: pub).prefix(8).map { String(format: "%02x", $0) }.joined(), pub: pub.base64EncodedString(), alg: "p256")
    }
    func sign(_ request: SignRequest) throws -> LedgerSignature {
        let id = identity
        let bytes = Data("\(id.unit)|\(request.day)|\(request.xp)|\(request.nonce)".utf8)
        return LedgerSignature(day: request.day, xp: request.xp, nonce: request.nonce, sig: try key.signature(for: bytes).derRepresentation.base64EncodedString(), unit: id.unit)
    }
}
