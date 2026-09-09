import Foundation
import XCTest
@testable import BoopCore

/// Deliberately holds HTTP responses so lifecycle changes happen during I/O.
private final class GrowthHTTPGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [GrowthGateProtocol] = []
    private var seen: [URLRequest] = []
    func append(_ connection: GrowthGateProtocol) {
        lock.lock(); defer { lock.unlock() }
        waiting.append(connection); seen.append(connection.request)
    }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    var pending: Int { lock.lock(); defer { lock.unlock() }; return waiting.count }
    func complete(status: Int = 200) {
        lock.lock()
        let connection = waiting.removeFirst()
        lock.unlock()
        connection.complete(status: status)
    }
    func reset() { lock.lock(); defer { lock.unlock() }; waiting = []; seen = [] }
}
private final class GrowthGateProtocol: URLProtocol, @unchecked Sendable {
    static let gate = GrowthHTTPGate()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.gate.append(self) }
    override func stopLoading() {}
    func complete(status: Int) {
        let view = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "view" }?.value ?? "all"
        let body = Data("{\"view\":\"\(view)\",\"rank\":1,\"entries\":[]}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    static func session() -> URLSession {
        gate.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        return URLSession(configuration: config)
    }
}

@MainActor
private final class HeldGrowthSigner: GrowthSigner {
    let fixture = TestDeviceSigner()
    var signingIdentity: DeviceIdentity? { fixture.identity }
    private(set) var pending: (SignRequest, CheckedContinuation<LedgerSignature, any Error>)?
    func sign(_ request: SignRequest) async throws -> LedgerSignature {
        try await withCheckedThrowingContinuation { pending = (request, $0) }
    }
    func complete() throws {
        let (request, continuation) = pending!
        pending = nil
        continuation.resume(returning: try fixture.sign(request))
    }
}

@MainActor
private final class SigningOutputFixture: OutputProvider, GrowthDeviceOutput {
    let id = "signing-fixture"
    weak var engine: BuddyEngine?
    var sent = 0
    func start(engine: BuddyEngine) async { self.engine = engine }
    func stop() async {}
    func stateDidChange(prev: BuddyState, next: BuddyState) {}
    func sendSign(_ request: SignRequest) {
        sent += 1
        engine?.handleDeviceCommand(.signature(try! TestDeviceSigner().sign(request)))
    }
}


/// This store exposes only the growth capability and suspends enrollment.
private actor HeldIdentityStore: GrowthStore {
    let base: Store
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    init(_ base: Store) { self.base = base }
    func acceptIdentity(_ identity: DeviceIdentity, at: Double) async throws {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        try await base.acceptIdentity(identity, at: at)
    }
    func release() { continuation?.resume(); continuation = nil }
    func deviceIdentity() async throws -> DeviceIdentity? { try await base.deviceIdentity() }
    func hasSignature(day: String) async throws -> Bool { try await base.hasSignature(day: day) }
    func signatures() async throws -> [LedgerSignature] { try await base.signatures() }
    func unsentSignatures() async throws -> ([LedgerSignature], String) { try await base.unsentSignatures() }
    func saveSignature(_ signature: LedgerSignature) async throws { try await base.saveSignature(signature) }
    func growth(localDay: String, at: Double) async throws -> GrowthSnapshot { try await base.growth(localDay: localDay, at: at) }
    func claimSubmission(_ day: String) async throws -> Bool { try await base.claimSubmission(day) }
    func releaseSubmission(_ day: String) async throws { try await base.releaseSubmission(day) }
    func markSubmittedThrough(_ day: String) async throws { try await base.markSubmittedThrough(day) }
}

final class GrowthCoordinatorTests: XCTestCase {
    @MainActor private func waitFor(_ predicate: () async throws -> Bool) async throws {
        for _ in 0..<400 {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for controlled operation")
        throw LeaderboardError.unavailable("test timeout")
    }

    @MainActor func testEngineRoutesSigningThroughOutputCapability() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "growth-output-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = BuddyEngine(store: store, defaults: defaults)
        let output = SigningOutputFixture()
        await output.start(engine: engine)
        engine.register(output: output)
        engine.handleDeviceCommand(.identity(TestDeviceSigner().identity))
        try await waitFor { try await store.signatures().count == 1 }
        XCTAssertEqual(output.sent, 1)
        XCTAssertEqual(engine.deviceIdentity, TestDeviceSigner().identity)
    }

    @MainActor func testDisconnectCancelsReplyAndReconnectSigns() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let signer = DeviceGrowthSigner(), fixture = TestDeviceSigner()
        let coordinator = GrowthCoordinator(store: store, signer: signer, session: .shared,
            defaults: .standard, clock: MockClock(), dayCalendar: LocalDayCalendar())
        try await coordinator.acceptDeviceIdentity(fixture.identity)
        var sent: SignRequest?
        signer.send = { sent = $0 }
        let signing = Task { try await coordinator.signGrowth() }
        try await waitFor { sent != nil }
        coordinator.signingDeviceDisconnected()
        do { _ = try await signing.value; XCTFail("Disconnected signing succeeded") }
        catch LeaderboardError.cancelled {}
        XCTAssertEqual(coordinator.deviceIdentity, fixture.identity)
        XCTAssertNil(signer.signingIdentity)
        let late = try fixture.sign(try XCTUnwrap(sent))
        try XCTAssertThrowsError(try coordinator.acceptSignature(late))
        let empty = try await store.signatures(); XCTAssertTrue(empty.isEmpty)
        try await coordinator.acceptDeviceIdentity(fixture.identity)
        signer.send = { try coordinator.acceptSignature(fixture.sign($0)) }
        let signatures = try await coordinator.signGrowth()
        XCTAssertEqual(signatures.count, 1)
    }

    @MainActor func testRetireDrainsUncooperativeSignerWithoutSavingLateReply() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "growth-retire-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let signer = HeldGrowthSigner()
        let engine = BuddyEngine(store: store, defaults: defaults, growthSigner: signer)
        let signing = Task { try await engine.signGrowth() }
        try await waitFor { signer.pending != nil }
        var retired = false
        let retirement = Task { try await engine.retire(); retired = true }
        try await waitFor { engine.deviceIdentity == nil }
        XCTAssertFalse(retired)
        try signer.complete()
        do { _ = try await signing.value; XCTFail("Retired signing succeeded") }
        catch LeaderboardError.cancelled {}
        try await retirement.value
        XCTAssertTrue(retired)
        let signatures = try await store.signatures(); XCTAssertTrue(signatures.isEmpty)
        let identity = try await store.deviceIdentity(); XCTAssertNil(identity)
    }

    @MainActor func testDisconnectDuringEnrollmentCannotRestoreConnection() async throws {
        let (base, _, cleanup) = try makeStore(); defer { cleanup() }
        let store = HeldIdentityStore(base), signer = DeviceGrowthSigner()
        let coordinator = GrowthCoordinator(store: store, signer: signer, session: .shared,
            defaults: .standard, clock: MockClock(), dayCalendar: LocalDayCalendar())
        let enrollment = Task { try await coordinator.acceptDeviceIdentity(TestDeviceSigner().identity) }
        try await waitFor { await store.entered }
        coordinator.signingDeviceDisconnected()
        await store.release()
        do { try await enrollment.value; XCTFail("Disconnected enrollment restored connection") }
        catch LeaderboardError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(coordinator.deviceIdentity)
        XCTAssertNil(signer.signingIdentity)
        let enrolled = try await base.deviceIdentity()
        XCTAssertEqual(enrolled, TestDeviceSigner().identity)
    }

    @MainActor func testThreeSyncCallersSerializeAndPreserveViews() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "growth-queue-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DefaultsKey.leaderboardOptIn)
        defaults.set("https://leaderboard.invalid", forKey: DefaultsKey.leaderboardURL)
        let session = GrowthGateProtocol.session(); defer { session.invalidateAndCancel() }
        let coordinator = GrowthCoordinator(store: store, signer: TestDeviceSigner(), session: session,
            defaults: defaults, clock: MockClock(), dayCalendar: LocalDayCalendar())
        try await coordinator.acceptDeviceIdentity(TestDeviceSigner().identity)
        let first = Task { try await coordinator.syncLeaderboard(view: .all) }
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        let second = Task { try await coordinator.syncLeaderboard(view: .month) }
        await Task.yield()
        let third = Task { try await coordinator.syncLeaderboard(view: .friends) }
        await Task.yield()
        GrowthGateProtocol.gate.complete()
        _ = try await first.value
        try await waitFor { GrowthGateProtocol.gate.requests.count == 2 }
        XCTAssertEqual(GrowthGateProtocol.gate.pending, 1)
        GrowthGateProtocol.gate.complete()
        try await waitFor { GrowthGateProtocol.gate.requests.count == 3 }
        XCTAssertEqual(GrowthGateProtocol.gate.pending, 1)
        GrowthGateProtocol.gate.complete()
        _ = try await second.value
        _ = try await third.value
        let views = GrowthGateProtocol.gate.requests.map {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "view" }!.value!
        }
        XCTAssertEqual(views.first, "all")
        XCTAssertEqual(Set(views.dropFirst()), Set(["month", "friends"]))
    }

    @MainActor func testOptOutRejectsInFlightRankResult() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "growth-opt-out-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GrowthGateProtocol.session(); defer { session.invalidateAndCancel() }
        let engine = BuddyEngine(store: store, defaults: defaults, leaderboardSession: session, growthSigner: TestDeviceSigner())
        _ = try await engine.signGrowth()
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: true)
        let rank = Task { try await engine.refreshRank(view: .all) }
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: false)
        GrowthGateProtocol.gate.complete()
        do { _ = try await rank.value; XCTFail("Opt-out accepted stale rank") }
        catch LeaderboardError.cancelled {}
        XCTAssertNil(engine.state.leaderboard)
    }

    @MainActor func testSubmissionFailureBackoffAndForcedRetry() async throws {
        let (store, _, cleanup) = try makeStore(); defer { cleanup() }
        let suite = "growth-retry-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = GrowthGateProtocol.session(); defer { session.invalidateAndCancel() }
        let engine = BuddyEngine(store: store, defaults: defaults, leaderboardSession: session, growthSigner: TestDeviceSigner())
        _ = try await engine.signGrowth()
        engine.configureLeaderboard(url: "https://leaderboard.invalid", optIn: true)
        let failed = Task { try await engine.syncLeaderboard() }
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        XCTAssertEqual(GrowthGateProtocol.gate.requests.last?.httpMethod, "POST")
        GrowthGateProtocol.gate.complete(status: 503)
        do { _ = try await failed.value; XCTFail("Failed submit succeeded") } catch {}
        let backedOff = Task { try await engine.syncLeaderboard() }
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        XCTAssertEqual(GrowthGateProtocol.gate.requests.last?.httpMethod, "GET")
        GrowthGateProtocol.gate.complete()
        _ = try await backedOff.value
        let forced = Task { try await engine.syncLeaderboard(force: true) }
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        XCTAssertEqual(GrowthGateProtocol.gate.requests.last?.httpMethod, "POST")
        GrowthGateProtocol.gate.complete(status: 201)
        try await waitFor { GrowthGateProtocol.gate.pending == 1 }
        XCTAssertEqual(GrowthGateProtocol.gate.requests.last?.httpMethod, "GET")
        GrowthGateProtocol.gate.complete()
        _ = try await forced.value
        let (unsent, _) = try await store.unsentSignatures(); XCTAssertTrue(unsent.isEmpty)
    }
}
