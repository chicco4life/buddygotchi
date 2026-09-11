import Foundation
import XCTest
@testable import BoopCore

@MainActor
private final class TestReleaseProvider: FirmwareReleaseProviding {
    let release = FirmwareRelease(version: "1.2.0", downloadURL: URL(string: "https://example.invalid/firmware.bin")!, sha256: "fixture", releaseNotes: "", publishedAt: nil)
    var holdDownload = false
    var download: CheckedContinuation<Data, Error>?
    var holdChecks = false
    var checks: [CheckedContinuation<FirmwareRelease, Error>] = []
    func latestRelease(forceRefresh: Bool) async throws -> FirmwareRelease {
        if holdChecks { return try await withCheckedThrowingContinuation { checks.append($0) } }
        return release
    }
    func downloadBinary(_ release: FirmwareRelease) async throws -> Data {
        if holdDownload { return try await withCheckedThrowingContinuation { download = $0 } }
        return Data([1, 2, 3])
    }
}

@MainActor
private final class TestUpdateTransport: FirmwareUpdateTransport {
    var endDisconnects = false
    var sent: [String] = []
    func sendAwaitingAck(_ data: Data, ackKey: String, timeout: TimeInterval) async throws -> BLEAckReply {
        sent.append(ackKey)
        if ackKey == "ota_end", endDisconnects { throw BLEAckError.notConnected }
        return BLEAckReply(ack: ackKey, count: nil, errorMessage: nil, status: nil)
    }
}

@MainActor
final class FirmwareUpdaterTests: XCTestCase {
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Updater did not reach the expected state")
    }

    private func begin(_ updater: FirmwareUpdater) async throws {
        updater.recordDeviceVersion("1.0.0")
        updater.checkForUpdates(forceRefresh: true)
        try await waitFor { if case .available = updater.state { return true }; return false }
        updater.startUpdate()
        try await waitFor { updater.state == .rebooting }
    }

    func testSuccessRequiresFreshMatchingDeviceVersion() async throws {
        let updater = FirmwareUpdater(releaseService: TestReleaseProvider())
        let transport = TestUpdateTransport()
        updater.attach(bleManager: transport)
        try await begin(updater)
        XCTAssertEqual(transport.sent, ["ota_begin", "ota_chunk", "ota_end"])
        updater.recordDeviceVersion(nil)
        XCTAssertEqual(updater.state, .rebooting)
        updater.recordDeviceVersion("v1.2.0")
        XCTAssertEqual(updater.state, .success(version: "v1.2.0"))
        updater.checkForUpdates()
        XCTAssertEqual(updater.state, .success(version: "v1.2.0"))
    }

    func testOldVersionIsFailureAndDismissalAllowsRetry() async throws {
        let updater = FirmwareUpdater(releaseService: TestReleaseProvider())
        let transport = TestUpdateTransport()
        updater.attach(bleManager: transport)
        try await begin(updater)
        updater.recordDeviceVersion("1.0.0")
        if case .failed(_, let recoverable) = updater.state { XCTAssertTrue(recoverable) }
        else { XCTFail("Old firmware cannot count as update success") }
        updater.dismissTerminal()
        if case .available(_, let current) = updater.state { XCTAssertEqual(current, "1.0.0") }
        else { XCTFail("The known update should remain retryable") }
    }

    func testEndDisconnectStillRequiresVersionConfirmation() async throws {
        let updater = FirmwareUpdater(releaseService: TestReleaseProvider())
        let transport = TestUpdateTransport(); transport.endDisconnects = true
        updater.attach(bleManager: transport)
        try await begin(updater)
        updater.recordDeviceVersion("1.2.0")
        XCTAssertEqual(updater.state, .success(version: "1.2.0"))
    }

    func testMissingReconnectTimesOutInsteadOfInventingSuccess() async throws {
        let updater = FirmwareUpdater(releaseService: TestReleaseProvider(), restartTimeout: 0.05)
        let transport = TestUpdateTransport()
        updater.attach(bleManager: transport)
        try await begin(updater)
        try await waitFor { if case .failed = updater.state { return true }; return false }
        XCTAssertEqual(updater.deviceVersion, "1.0.0")
    }

    func testStaleCheckCannotOverwriteNewerResult() async throws {
        let provider = TestReleaseProvider(); provider.holdChecks = true
        let updater = FirmwareUpdater(releaseService: provider)
        updater.checkForUpdates(forceRefresh: true)
        try await waitFor { provider.checks.count == 1 }
        updater.checkForUpdates(forceRefresh: true)
        try await waitFor { provider.checks.count == 2 }
        provider.checks[1].resume(returning: provider.release)
        try await waitFor { if case .available = updater.state { return true }; return false }
        provider.checks[0].resume(throwing: BLEAckError.timeout)
        try await Task.sleep(for: .milliseconds(10))
        if case .available = updater.state {} else { XCTFail("A superseded check overwrote the latest result") }
    }

    func testDismissingCheckErrorDoesNotClaimFirmwareIsCurrent() {
        let updater = FirmwareUpdater.preview(state: .checkFailed(reason: "Offline"))
        updater.recordDeviceVersion("1.0.0")
        updater.dismissTerminal()
        XCTAssertEqual(updater.state, .idle)
    }

    func testCancelledDownloadCannotStartTransferOrOverwriteRetry() async throws {
        let provider = TestReleaseProvider(); provider.holdDownload = true
        let updater = FirmwareUpdater(releaseService: provider)
        let transport = TestUpdateTransport()
        updater.attach(bleManager: transport)
        updater.recordDeviceVersion("1.0.0")
        updater.checkForUpdates(forceRefresh: true)
        try await waitFor { if case .available = updater.state { return true }; return false }
        updater.startUpdate()
        try await waitFor { provider.download != nil }
        updater.cancel()
        updater.dismissTerminal()
        provider.download?.resume(returning: Data([1, 2, 3]))
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(transport.sent.isEmpty)
        if case .available = updater.state {} else { XCTFail("Cancelled download overwrote the retry state") }
    }

    func testPopoverHeightSharesGrowthAndScreenBounds() {
        XCTAssertEqual(PopoverLayout.overviewHeight(sessionCount: 1, hasRequest: false, availableHeight: 1000), 548)
        XCTAssertEqual(PopoverLayout.overviewHeight(sessionCount: 6, hasRequest: false, availableHeight: 1000), 778)
        XCTAssertEqual(PopoverLayout.overviewHeight(sessionCount: 30, hasRequest: false, availableHeight: 1000), 962)
        XCTAssertEqual(PopoverLayout.overviewHeight(sessionCount: 1, hasRequest: true, availableHeight: 400), 400)
    }
}
