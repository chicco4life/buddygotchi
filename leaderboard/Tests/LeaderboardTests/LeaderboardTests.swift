import Foundation
import XCTest
import Hummingbird
import HummingbirdTesting
@testable import LeaderboardCore

@MainActor
final class LeaderboardTests: XCTestCase {
    nonisolated static let fixtures = [
        #"{"buddyName":"Buddy42","silhouette":"default","xpTotal":100,"signatures":[{"day":"2026-08-31","xp":100,"nonce":"0123456789abcdef","sig":"MEUCIQC7roaWyr+DAYb2imcPJGlJ8KVfTGnBUSEf5xF1XXe5egIgM4Djs807InKhHQU0QXlH89nZ0LdO2/IcVyoRZm6V02U="}],"unit":"6a4a68e95d18c8b1","pub":"BGeAxfxwJ14scGGg54d7sXTereuYhwJ/P6g2VBWLp/UMPLqMNLw10g6B9zCsHHvW1mGpQvkMapylXFEvnkoAEmY=","alg":"p256"}"#,
        #"{"buddyName":"Buddy42","silhouette":"default","xpTotal":150,"signatures":[{"day":"2026-09-09","xp":150,"nonce":"0123456789abcdef","sig":"MEYCIQCRxSJH3EhQF+6PUXODzRwiC8ac0mvn/r052HQBvZ26SQIhAIlwE3Yza1r3/cFfXnFzapw4df76SZN0HMifFnMm4iab"}],"unit":"6a4a68e95d18c8b1","pub":"BGeAxfxwJ14scGGg54d7sXTereuYhwJ/P6g2VBWLp/UMPLqMNLw10g6B9zCsHHvW1mGpQvkMapylXFEvnkoAEmY=","alg":"p256"}"#,
        #"{"buddyName":"Buddy43","silhouette":"default","xpTotal":200,"signatures":[{"day":"2026-09-09","xp":200,"nonce":"0123456789abcdef","sig":"MEYCIQDB3L35JITkCG67ECcFXQfHNTnFyxSOBe17/5W++l49cAIhAKbLoMb0B4M2GgTNizws6kdIikcoMJ8y6mN7GitcgsrH"}],"unit":"aea24a2f2a2034cc","pub":"BJhq4lBvH/EE0EIwhh2PS0mPS8TG0AmzD3VE3BKbgtKNADzMwKZGDgrjKKTZfTx7YdhvxiicGJ8lJREMRBuwfpc=","alg":"p256"}"#
    ]
    func fixture(_ i: Int) throws -> LeaderboardSubmission { try JSONDecoder().decode(LeaderboardSubmission.self, from: Data(Self.fixtures[i].utf8)) }
    var now: Date { Date(timeIntervalSince1970: 1788998400) }
    func testVerifyAndRejectTamperedTotalKeyAndAlgorithm() async throws {
        let store = try RankingStore(path: ":memory:")
        let good = try fixture(0)
        try await store.submit(good, now: now)
        for change in 0..<4 {
            var bad = try fixture(1)
            switch change {
            case 0: bad.xpTotal += 1
            case 1: bad.signatures[0].xp += 1; bad.xpTotal += 1
            case 2: bad.unit = "0000000000000000"
            default: bad.alg = "ed25519"
            }
            do { try await store.submit(bad, now: now); XCTFail("Accepted invalid submission") } catch {}
        }
    }
    func testDuplicatesRejectAndTransactionRollsBack() async throws {
        let store = try RankingStore(path: ":memory:")
        let good = try fixture(0)
        try await store.submit(good, now: now)
        do { try await store.submit(good, now: now); XCTFail("Accepted replay") } catch {}
        var batch = try fixture(1)
        batch.signatures.append(good.signatures[0])
        do { try await store.submit(batch, now: now); XCTFail("Accepted duplicate batch") } catch {}
        let before = try await store.rank(unit: good.unit, view: .all, friends: [], now: now)
        XCTAssertTrue(before.entries[0].xpTotal == 100)
        try await store.submit(fixture(1), now: now)
    }
    func testRankOrderingMonthAndFriends() async throws {
        let store = try RankingStore(path: ":memory:")
        for i in 0..<3 { try await store.submit(fixture(i), now: now) }
        let a = try fixture(0), b = try fixture(2)
        let all = try await store.rank(unit: a.unit, view: .all, friends: [], now: now)
        XCTAssertTrue(all.rank == 2); XCTAssertTrue(all.entries.map(\.xpTotal) == [200, 150])
        let month = try await store.rank(unit: a.unit, view: .month, friends: [], now: now)
        XCTAssertTrue(month.entries.map(\.xpTotal) == [200, 50])
        let solo = try await store.rank(unit: a.unit, view: .friends, friends: [], now: now)
        XCTAssertTrue(solo.rank == 1); XCTAssertTrue(solo.entries.count == 1)
        let friends = try await store.rank(unit: a.unit, view: .friends, friends: [String(b.unit.prefix(6)).uppercased()], now: now)
        XCTAssertTrue(friends.entries.count == 2); XCTAssertTrue(friends.rank == 2)
    }
    func testRoutesVerifyBodyKeysAndRankWithoutSockets() async throws {
        let store = try RankingStore(path: ":memory:")
        let app = Application(router: makeRouter(store: store))
        let unit = try fixture(0).unit
        try await app.test(.router) { client in
            try await client.execute(uri: "/healthz", method: .get) { response in XCTAssertTrue(response.status == .ok) }
            try await client.execute(uri: "/submit", method: .post, body: ByteBuffer(string: Self.fixtures[0])) { response in XCTAssertTrue(response.status == .created) }
            try await client.execute(uri: "/submit", method: .post, body: ByteBuffer(string: Self.fixtures[0])) { response in XCTAssertTrue(response.status == .conflict) }
            let floatXP = Self.fixtures[2].replacingOccurrences(of: "\"xp\":200", with: "\"xp\":200.0")
            try await client.execute(uri: "/submit", method: .post, body: ByteBuffer(string: floatXP)) { response in XCTAssertTrue(response.status == .badRequest) }
            let polluted = String(Self.fixtures[2].dropLast()) + ",\"project\":\"PRIVATE\"}"
            try await client.execute(uri: "/submit", method: .post, body: ByteBuffer(string: polluted)) { response in XCTAssertTrue(response.status == .badRequest) }
            try await client.execute(uri: "/rank?unit=\(unit)&view=all", method: .get) { response in
                XCTAssertTrue(response.status == .ok)
                let rank = try JSONDecoder().decode(LeaderboardSnapshot.self, from: Data(response.body.readableBytesView))
                XCTAssertTrue(rank.rank == 1)
            }
        }
    }
    func testRankBeyondTopHundredAndTieOrder() async throws {
        let store = try RankingStore(path: ":memory:")
        let db = await store.db
        for i in 0..<105 {
            try db.run("INSERT INTO units VALUES(?,?,?,?,?,?,?)", [String(format: "%016x", i), "pub", "p256", "Buddy", "default", "100", "2026-09-09"])
        }
        let snapshot = try await store.rank(unit: String(format: "%016x", 104), view: .all, friends: [], now: now)
        XCTAssertEqual(snapshot.entries.count, 100)
        XCTAssertEqual(snapshot.rank, 105)
        XCTAssertEqual(snapshot.entries.first?.unit, "0000000000000000")
        XCTAssertEqual(snapshot.entries.last?.rank, 100)
    }
    func testStrictSubmissionNumericTypesAndNestedKeys() throws {
        for (field, value) in [("xp", "200.0"), ("xp", "2e2"), ("xp", "true"), ("xpTotal", "200.0"), ("xpTotal", "true")] {
            let data = Self.fixtures[2].replacingOccurrences(of: "\"\(field)\":200", with: "\"\(field)\":\(value)")
            try XCTAssertThrowsError(try SubmissionDecoder.decode(Data(data.utf8)))
        }
        let nested = Self.fixtures[2].replacingOccurrences(of: "\"xp\":200", with: "\"private\":true,\"xp\":200")
        try XCTAssertThrowsError(try SubmissionDecoder.decode(Data(nested.utf8)))
        let valid = try SubmissionDecoder.decode(Data(Self.fixtures[2].utf8))
        XCTAssertEqual(valid.xpTotal, 200)
    }

}
