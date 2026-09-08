import Foundation
import XCTest
@testable import BoopCore

final class LeaderboardCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; requests.append(request) }
    func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    var captured: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
final class LeaderboardURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = LeaderboardCapture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096), body = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count))
            }
            captured.httpBody = body
        }
        Self.capture.append(captured)
        let view = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "view" })?.value ?? "all"
        let body = Data("{\"view\":\"\(view)\",\"rank\":1,\"entries\":[]}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "POST" ? 201 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Self.self]
        return URLSession(configuration: config)
    }
}
final class LeaderboardClientTests: XCTestCase {
    @MainActor func testOptInDailyReservationAndFriendsStayInRankQuery() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "leaderboard-" + UUID().uuidString, signer = TestDeviceSigner()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        let session = LeaderboardURLProtocol.session(); defer { session.invalidateAndCancel() }
        LeaderboardURLProtocol.capture.reset()
        let engine = BuddyEngine(store: store, defaults: defaults, leaderboardSession: session)
        try await store.acceptIdentity(signer.identity, at: 0)
        try await store.saveSignature(signer.sign(SignRequest(day: "2026-09-09", xp: 10)))
        engine.start(); defer { engine.stop() }; await engine.flushStore()
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: false)
        do { _ = try await engine.syncLeaderboard(); XCTFail("Opt-out made a request") } catch {}
        XCTAssertTrue(LeaderboardURLProtocol.capture.captured.isEmpty)
        engine.configureLeaderboard(url: "", optIn: true)
        do { _ = try await engine.syncLeaderboard(); XCTFail("Empty URL made a request") } catch {}
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: true)
        engine.addFriend("abcdef")
        let concurrent = BuddyEngine(store: store, defaults: defaults, leaderboardSession: session)
        concurrent.start(); defer { concurrent.stop() }; await concurrent.flushStore()
        async let first = engine.syncLeaderboard(view: .friends)
        async let second = concurrent.syncLeaderboard(view: .friends)
        _ = try await (first, second)
        _ = try await engine.syncLeaderboard(view: .all)
        _ = try await engine.refreshRank(view: .month)
        let requests = LeaderboardURLProtocol.capture.captured
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
        let body = try XCTUnwrap(requests.first(where: { $0.httpMethod == "POST" })?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(Set(object.keys), Set(["buddyName", "silhouette", "xpTotal", "signatures", "unit", "pub", "alg"]))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("ABCDEF"))
        let query = URLComponents(url: requests.first(where: { $0.httpMethod != "POST" })!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "friends" })?.value, "[\"ABCDEF\"]")
        XCTAssertEqual(query.first(where: { $0.name == "code" })?.value, signer.identity.friendsCode)
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: false)
        XCTAssertNil(engine.state.leaderboard)
        let reopened = BuddyEngine(store: store, defaults: defaults, leaderboardSession: session)
        reopened.start(); defer { reopened.stop() }; await reopened.flushStore()
        reopened.configureLeaderboard(url: "https://leaderboard.invalid", optIn: true)
        _ = try await reopened.syncLeaderboard()
        XCTAssertEqual(LeaderboardURLProtocol.capture.captured.filter { $0.httpMethod == "POST" }.count, 1)
    }
}
