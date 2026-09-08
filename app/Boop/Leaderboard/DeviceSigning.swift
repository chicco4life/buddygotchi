import Foundation
import CryptoKit
@_exported import LeaderboardWire
@_exported import BoopSQLite

struct SignRequest: Encodable, Sendable, Equatable {
    let cmd = "sign"
    var day: String, xp: Int, nonce: String
    init(day: String, xp: Int) {
        self.day = day; self.xp = xp
        var generator = SystemRandomNumberGenerator()
        nonce = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }
}
@MainActor protocol GrowthSigner {
    var signingIdentity: DeviceIdentity? { get }
    func sign(_ request: SignRequest) async throws -> LedgerSignature
}

/// The transport reply completes exactly one request; late replies are ignored.
@MainActor final class DeviceGrowthSigner: GrowthSigner {
    var signingIdentity: DeviceIdentity?
    var send: ((SignRequest) throws -> Void)?
    private var pending: (SignRequest, CheckedContinuation<LedgerSignature, any Error>)?
    func sign(_ request: SignRequest) async throws -> LedgerSignature {
        guard pending == nil, let send else { throw LeaderboardError.unavailable("no device output") }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            cancel(LeaderboardError.unavailable("signature timed out"))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            pending = (request, continuation)
            do { try send(request) } catch { cancel(error) }
        }
    }
    func accept(_ signature: LedgerSignature) throws {
        guard let (request, continuation) = pending,
              signature.day == request.day, signature.xp == request.xp, signature.nonce == request.nonce else { throw LeaderboardError.replay }
        guard let identity = signingIdentity, signature.verified(by: identity) else { throw LeaderboardError.invalidSignature }
        pending = nil; continuation.resume(returning: signature)
    }
    func cancel(_ error: any Error = LeaderboardError.cancelled) {
        let continuation = pending?.1; pending = nil
        continuation?.resume(throwing: error)
    }
}

/// Software fixture injected by the composition root or tests.

struct TestDeviceSigner: GrowthSigner {
    var signingIdentity: DeviceIdentity? { identity }
    private let key = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x42, count: 32))
    var identity: DeviceIdentity {
        let pub = key.publicKey.x963Representation
        return DeviceIdentity(unit: DeviceIdentity.unit(publicKey: pub), pub: pub.base64EncodedString(), alg: "p256")
    }
    func sign(_ request: SignRequest) throws -> LedgerSignature {
        let id = identity
        let bytes = Data("\(id.unit)|\(request.day)|\(request.xp)|\(request.nonce)".utf8)
        return LedgerSignature(day: request.day, xp: request.xp, nonce: request.nonce, sig: try key.signature(for: bytes).derRepresentation.base64EncodedString(), unit: id.unit)
    }
}
