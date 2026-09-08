#if BOOP_SHIM_RUNNER
import Foundation
@main struct Runner {
    @MainActor static func main() async throws {
        let tests = LeaderboardTests()
        try await tests.testVerifyAndRejectTamperedTotalKeyAndAlgorithm()
        try await tests.testDuplicatesRejectAndTransactionRollsBack()
        try await tests.testRankOrderingMonthAndFriends()
        try await tests.testRoutesVerifyBodyKeysAndRankWithoutSockets()
        print("LeaderboardTests: 4 passed, 0 failed")
    }
}
#endif
