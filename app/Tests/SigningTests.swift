import Foundation
import CryptoKit
import XCTest
@testable import BoopCore

final class SigningTests: XCTestCase {
    func testDeviceSignatureRejectsTampering() throws {
        let signer = TestDeviceSigner(), request = SignRequest(day: "2026-09-09", xp: 456)
        let signature = try signer.sign(request)
        XCTAssertTrue(signature.verified(by: signer.identity))
        XCTAssertEqual(request.nonce.count, 16)
        XCTAssertNotEqual(request.nonce, SignRequest(day: request.day, xp: request.xp).nonce)
        var bad = signature; bad.xp += 1; XCTAssertFalse(bad.verified(by: signer.identity))
        bad = signature; bad.day = "2026-09-10"; XCTAssertFalse(bad.verified(by: signer.identity))
        bad = signature; bad.nonce = "00"; XCTAssertFalse(bad.verified(by: signer.identity))
        bad = signature; bad.sig = "garbage"; XCTAssertFalse(bad.verified(by: signer.identity))
        var malformed = request; malformed.day += "\n"
        let newlineDay = try signer.sign(malformed); XCTAssertFalse(newlineDay.verified(by: signer.identity))
        malformed = request; malformed.nonce += "\n"
        let newlineNonce = try signer.sign(malformed); XCTAssertFalse(newlineNonce.verified(by: signer.identity))
        var id = signer.identity; id.unit = "0000000000000000"; XCTAssertNil(id.publicKey)
        id = signer.identity; id.alg = "ed25519"; XCTAssertNil(id.publicKey)
    }
    func testWireAcknowledgementsAreStrict() throws {
        let signer = TestDeviceSigner()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(signer.identity)) as! [String: Any]
        object["ack"] = "unit"; object["ok"] = true
        func line(_ value: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
        guard case .identity(let identity) = parseDeviceLine(try line(object)) else { XCTFail("Missing identity"); return }
        XCTAssertEqual(identity, signer.identity)
        object["ok"] = false; try XCTAssertNil(parseDeviceLine(try line(object)))
        let signature = try signer.sign(SignRequest(day: "2026-09-09", xp: 12))
        object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(signature)) as! [String: Any]
        object["ack"] = "sign"; object["ok"] = true
        guard case .signature(let decoded) = parseDeviceLine(try line(object)) else { XCTFail("Missing signature"); return }
        XCTAssertEqual(decoded, signature)
        let integralFloat = try line(object).replacingOccurrences(of: "\"xp\":12", with: "\"xp\":12.0")
        XCTAssertNil(parseDeviceLine(integralFloat))
        object["xp"] = true; try XCTAssertNil(parseDeviceLine(try line(object)))
        object["xp"] = 1.5; try XCTAssertNil(parseDeviceLine(try line(object)))
    }
    func testStorePinsIdentityVerifiesAndRejectsReplayAcrossReopen() async throws {
        let (store, dir, cleanup) = try makeStore(); defer { cleanup() }
        let signer = TestDeviceSigner()
        try await store.acceptIdentity(signer.identity, at: 123)
        let key = P256.Signing.PrivateKey().publicKey.x963Representation
        let other = DeviceIdentity(unit: SHA256.hash(data: key).prefix(8).map { String(format: "%02x", $0) }.joined(), pub: key.base64EncodedString(), alg: "p256")
        do { try await store.acceptIdentity(other, at: 124); XCTFail("Changed identity accepted") } catch {}
        let signature = try signer.sign(SignRequest(day: "2026-09-09", xp: 10))
        var bad = signature; bad.xp = 11
        do { try await store.saveSignature(bad); XCTFail("Unverified signature stored") } catch {}
        let empty = try await store.signatures(); XCTAssertTrue(empty.isEmpty)
        try await store.saveSignature(signature)
        let reopened = try Store(stateDir: dir.path, now: 0)
        let identity = try await reopened.deviceIdentity(); XCTAssertEqual(identity, signer.identity)
        do { try await reopened.saveSignature(signature); XCTFail("Replay stored") } catch {}
        try await reopened.retire()
        try await reopened.acceptIdentity(other, at: 125)
        let newIdentity = try await reopened.deviceIdentity(); XCTAssertEqual(newIdentity, other)
        let cleared = try await reopened.signatures(); XCTAssertTrue(cleared.isEmpty)
    }
    func testSubmissionKeySetAndSoftwareOnlyCannotRank() throws {
        let signer = TestDeviceSigner()
        let signature = try signer.sign(SignRequest(day: "2026-09-09", xp: 12))
        let body = try LeaderboardSubmission(buddyName: "Mochi", silhouette: "default", signatures: [signature], identity: signer.identity)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), Set(["buddyName", "silhouette", "xpTotal", "signatures", "unit", "pub", "alg"]))
        let signatures = json["signatures"] as! [[String: Any]]
        XCTAssertEqual(Set(signatures[0].keys), Set(["day", "xp", "nonce", "sig"]))
        try XCTAssertThrowsError(try LeaderboardSubmission(buddyName: "Mochi", silhouette: "default", signatures: [], identity: signer.identity))
    }
    @MainActor func testNoSignerAndUnsolicitedReply() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let (engine, _) = makeEngine(store: store)
        do { _ = try await engine.signGrowth(); XCTFail("Signed without an injected signer or device") } catch {}
        engine.handleDeviceCommand(.signature(try TestDeviceSigner().sign(SignRequest(day: "2026-09-09", xp: 2))))
        await Task.yield()
        let signatures = try await store.signatures(); XCTAssertTrue(signatures.isEmpty)
        do { _ = try await engine.syncLeaderboard(); XCTFail("Software-only submitted") } catch {}
    }
    @MainActor func testInjectedSignerSignsOnceAndUsesDisplayName() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "signer-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = BuddyEngine(store: store, defaults: defaults, growthSigner: TestDeviceSigner())
        XCTAssertEqual(engine.displayName, "Boop")
        defaults.set("  Mochi \n", forKey: DefaultsKey.buddyName)
        XCTAssertEqual(engine.displayName, "Mochi")
        let first = try await engine.signGrowth()
        let second = try await engine.signGrowth()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first[0].verified(by: TestDeviceSigner().identity))
        let submission = try LeaderboardSubmission(buddyName: "", silhouette: "default", signatures: first, identity: TestDeviceSigner().identity)
        XCTAssertEqual(submission.buddyName, "")
        let unicode = try LeaderboardSubmission(buddyName: String(repeating: "보", count: 30), silhouette: "default", signatures: first, identity: TestDeviceSigner().identity)
        XCTAssertTrue(unicode.buddyName.utf8.count <= 80)
        XCTAssertFalse(unicode.buddyName.contains("�"))
    }
    @MainActor func testDeviceSignerContinuationReplyAndCancellation() async throws {
        let signer = DeviceGrowthSigner(), fixture = TestDeviceSigner()
        signer.signingIdentity = fixture.identity
        signer.send = { request in try signer.accept(fixture.sign(request)) }
        let request = SignRequest(day: "2026-09-09", xp: 12)
        let signature = try await signer.sign(request)
        XCTAssertTrue(signature.verified(by: fixture.identity))
        signer.send = { _ in signer.cancel() }
        do { _ = try await signer.sign(request); XCTFail("Cancelled signing succeeded") }
        catch LeaderboardError.cancelled {} catch { XCTFail("Unexpected error: \(error)") }
        try XCTAssertThrowsError(try signer.accept(signature))
    }

}
