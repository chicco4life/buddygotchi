import Foundation
import Observation
import LeaderboardWire

/// The persistence capability needed for device-backed growth. The coordinator
/// does not depend on SQLite or on the engine's unrelated store operations.
protocol GrowthStore: Sendable {
    func deviceIdentity() async throws -> DeviceIdentity?
    func acceptIdentity(_ identity: DeviceIdentity, at: Double) async throws
    func hasSignature(day: String) async throws -> Bool
    func signatures() async throws -> [LedgerSignature]
    func unsentSignatures() async throws -> ([LedgerSignature], String)
    func saveSignature(_ signature: LedgerSignature) async throws
    func growth(localDay: String, at: Double) async throws -> GrowthSnapshot
    func claimSubmission(_ day: String) async throws -> Bool
    func releaseSubmission(_ day: String) async throws
    func markSubmittedThrough(_ day: String) async throws
}

/// Owns signing and leaderboard lifetimes. The persistence barrier runs before
/// reads; results return through a callback to reducer dispatch.
@Observable
@MainActor
final class GrowthCoordinator {
    // Enrolled identity survives disconnect for rank reads.
    private(set) var deviceIdentity: DeviceIdentity?
    var store: (any GrowthStore)?
    var prepare: () async -> Void = {}
    var presentation: () -> (name: String, silhouette: String) = { ("Boop", "") }
    var onSnapshot: ((LeaderboardSnapshot) -> Void)?
    private let growthSigner: any GrowthSigner
    private let leaderboardSession: URLSession
    private let defaults: UserDefaults
    private let clock: any Clock
    private let dayCalendar: any DayCalendar
    private var lastSignedDay: String?
    private var signing = false
    private var activeIdentityRequests = 0
    private var deviceGeneration = 0
    private var leaderboardSync: Task<LeaderboardSnapshot, Error>?
    private var lastLeaderboardFailureAt: Double = -.infinity
    private let leaderboardRetryMs: Double = 10 * 60_000
    private var growthGeneration = 0
    private var signingAttemptAt: Double = -.infinity
    private var connectedIdentity: DeviceIdentity?
    private var retiring = false

    init(store: (any GrowthStore)?, signer: any GrowthSigner, session: URLSession,
         defaults: UserDefaults, clock: any Clock, dayCalendar: any DayCalendar) {
        self.store = store
        self.growthSigner = signer
        self.leaderboardSession = session
        self.defaults = defaults
        self.clock = clock
        self.dayCalendar = dayCalendar
    }

    private var optedIn: Bool { defaults.object(forKey: DefaultsKey.leaderboardOptIn) as? Bool ?? false }
    private var leaderboardURL: String { defaults.string(forKey: DefaultsKey.leaderboardURL) ?? "" }
    private var friendsCodes: [String] { defaults.stringArray(forKey: DefaultsKey.leaderboardFriends) ?? [] }
    private func localDay(at: Double) -> String { dayCalendar.localDay(at: at) }
    func loadIdentity() async throws { deviceIdentity = try await store?.deviceIdentity() }
    func settingsChanged() { growthGeneration += 1 }

    func beginRetirement() {
        retiring = true
        growthGeneration += 1
        signingDeviceDisconnected()
        deviceIdentity = nil
        lastSignedDay = nil
    }
    func drain() async {
        while signing || leaderboardSync != nil || activeIdentityRequests > 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
    func endRetirement() { retiring = false }

    func shouldMaintain() -> Bool {
        guard connectedIdentity != nil || growthSigner.signingIdentity != nil,
              !signing, !retiring, clock.now() - signingAttemptAt >= 60_000 else { return false }
        signingAttemptAt = clock.now()
        return true
    }
    func maintain() async throws {
        if lastSignedDay != localDay(at: clock.now()) { _ = try await signGrowth() }
        _ = try? await syncLeaderboard()
    }

    func signingDeviceDisconnected() {
        deviceGeneration += 1
        connectedIdentity = nil
        if let signer = growthSigner as? any DeviceReplySigner {
            signer.signingIdentity = nil
            signer.cancel(LeaderboardError.cancelled)
        }
    }
    func acceptDeviceIdentity(_ identity: DeviceIdentity) async throws {
        await prepare()
        guard !retiring, let store else { throw LeaderboardError.unavailable("no store") }
        let generation = deviceGeneration
        activeIdentityRequests += 1; defer { activeIdentityRequests -= 1 }
        try await store.acceptIdentity(identity, at: clock.now())
        guard !retiring, generation == deviceGeneration else { throw LeaderboardError.unavailable("device changed") }
        deviceIdentity = identity; connectedIdentity = identity
        (growthSigner as? any DeviceReplySigner)?.signingIdentity = identity
    }
    private func requireCurrent(_ generation: Int) throws {
        guard generation == growthGeneration, !retiring else { throw LeaderboardError.cancelled }
    }
    func acceptSignature(_ signature: LedgerSignature) throws {
        guard !retiring, let signer = growthSigner as? any DeviceReplySigner else { throw LeaderboardError.replay }
        try signer.accept(signature)
    }
    @discardableResult func signGrowth() async throws -> [LedgerSignature] {
        await prepare()
        guard !retiring, !signing, let store else { throw LeaderboardError.unavailable("signing busy or no store") }
        signing = true; defer { signing = false }
        let generation = growthGeneration
        if let identity = growthSigner.signingIdentity, connectedIdentity == nil {
            try await acceptDeviceIdentity(identity)
        }
        let day = localDay(at: clock.now())
        if try await store.hasSignature(day: day) {
            lastSignedDay = day
            return try await store.signatures()
        }
        guard connectedIdentity != nil else { throw LeaderboardError.unavailable("no signing device connected") }
        let growth = try await store.growth(localDay: day, at: clock.now())
        try requireCurrent(generation)
        let request = SignRequest(day: day, xp: growth.xp)
        let signature = try await growthSigner.sign(request)
        try requireCurrent(generation)
        try await store.saveSignature(signature)
        try requireCurrent(generation)
        lastSignedDay = day
        return try await store.signatures()
    }
    /// Concurrent callers (the maintenance tick, the sheet, the headless route)
    /// queue behind the in-flight sync, retaining each caller's requested view.
    /// `force` skips the failure backoff: a person asked for it, so try now.
    @discardableResult func syncLeaderboard(view: RankView = .all, force: Bool = false) async throws -> LeaderboardSnapshot {
        let previous = leaderboardSync
        let task = Task { @MainActor in
            _ = try? await previous?.value
            return try await self.performLeaderboardSync(view: view, force: force)
        }
        leaderboardSync = task
        defer { if leaderboardSync == task { leaderboardSync = nil } }
        return try await task.value
    }
    private func performLeaderboardSync(view: RankView, force: Bool) async throws -> LeaderboardSnapshot {
        await prepare()
        guard !retiring, optedIn,
              !leaderboardURL.isEmpty, let url = URL(string: leaderboardURL), ["http", "https"].contains(url.scheme),
              let store else { throw LeaderboardError.unavailable("opt-in, url, or store missing") }
        let generation = growthGeneration, client = LeaderboardClient(url: url, session: leaderboardSession)
        guard let identity = deviceIdentity else { throw LeaderboardError.unavailable("no enrolled identity") }
        try requireCurrent(generation)
        let day = localDay(at: clock.now())
        let (unsent, _) = try await store.unsentSignatures()
        // At-most-once is already guaranteed by the sent-through marker; a failed
        // upload must not burn the day, it just backs off for a while.
        if !unsent.isEmpty, force || clock.now() - lastLeaderboardFailureAt >= leaderboardRetryMs, try await store.claimSubmission(day) {
            let body = try LeaderboardSubmission(buddyName: presentation().name, silhouette: presentation().silhouette, signatures: unsent, identity: identity, verifySignatures: false)
            try requireCurrent(generation)
            do { try await client.submit(body) } catch {
                // Release the day so the next tick can retry after the backoff.
                lastLeaderboardFailureAt = clock.now(); try? await store.releaseSubmission(day); throw error
            }
            try requireCurrent(generation)
            try await store.markSubmittedThrough(unsent.map(\.day).max()!)
        }
        try requireCurrent(generation)
        let snapshot = try await client.rank(unit: identity.unit, view: view, code: identity.friendsCode, friends: friendsCodes)
        try requireCurrent(generation)
        onSnapshot?(snapshot)
        return snapshot
    }
    @discardableResult func refreshRank(view: RankView) async throws -> LeaderboardSnapshot {
        await prepare()
        guard optedIn, let identity = deviceIdentity,
              let url = URL(string: leaderboardURL), ["http", "https"].contains(url.scheme) else { throw LeaderboardError.unavailable("opt-in, url, or identity missing") }
        let generation = growthGeneration
        try requireCurrent(generation)
        let snapshot = try await LeaderboardClient(url: url, session: leaderboardSession).rank(unit: identity.unit, view: view, code: identity.friendsCode, friends: friendsCodes)
        try requireCurrent(generation)
        onSnapshot?(snapshot)
        return snapshot
    }
    func submissionPreview(headless: Bool) async throws -> LeaderboardSubmission {
        await prepare()
        guard headless, let store, let identity = try await store.deviceIdentity() else { throw LeaderboardError.unavailable("preview requires headless store and identity") }
        return try await LeaderboardSubmission(buddyName: presentation().name, silhouette: presentation().silhouette, signatures: store.signatures(), identity: identity)
    }

}
