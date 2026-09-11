import Foundation
import Observation

protocol FirmwareUpdateTransport: AnyObject, Sendable {
    func sendAwaitingAck(_ data: Data, ackKey: String, timeout: TimeInterval) async throws -> BLEAckReply
}

// State machine for the OTA flow. The updater is owned by ESP32Output and
// outlives any UI presentation — the popover can close mid-update; the
// task keeps running and the FirmwareUpdateView reattaches when reopened.
@Observable
@MainActor
final class FirmwareUpdater {
    enum UpdateState: Equatable {
        case idle
        case checking
        case available(latest: FirmwareRelease, current: String)
        case upToDate(version: String)
        case downloading(progress: Double)
        case uploading(progress: Double, etaSeconds: Int)
        case verifying
        case rebooting
        case success(version: String)
        case checkFailed(reason: String)
        case failed(reason: String, recoverable: Bool)

        // Convenience for the SettingsView badge.
        var isMidFlight: Bool {
            switch self {
            case .downloading, .uploading, .verifying, .rebooting: return true
            default: return false
            }
        }

        var midFlightProgress: Double? {
            switch self {
            case .downloading(let p): return p
            case .uploading(let p, _): return p
            case .verifying, .rebooting: return 1.0
            default: return nil
            }
        }
    }

    private(set) var state: UpdateState = .idle

    /// Snapshot harness only. FirmwareUpdateView is presented with `.sheet`, so it
    /// is the one dense surface no harness could reach; this parks an updater in a
    /// given state so the renderer can photograph it. Never called by the app.
    static func preview(state: UpdateState) -> FirmwareUpdater {
        let updater = FirmwareUpdater()
        updater.state = state
        return updater
    }

    /// The visually distinct OTA states, minus the ones that need a live release.
    static var snapshotStates: [(String, UpdateState)] {
        [
            ("checking", .checking),
            ("uploading", .uploading(progress: 0.42, etaSeconds: 95)),
            ("verifying", .verifying),
            ("success", .success(version: "0.4.1")),
            ("failed", .failed(reason: "the device stopped acknowledging chunks", recoverable: true)),
        ]
    }

    // Last known firmware version reported by the device's status reply.
    // Stays nil until the first successful status round-trip after connect.
    private(set) var deviceVersion: String?

    private let releaseService: any FirmwareReleaseProviding
    private weak var bleManager: (any FirmwareUpdateTransport)?

    private var updateTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var checkGeneration = 0
    private var offeredRelease: FirmwareRelease?
    private var expectedRestartVersion: String?
    private var restartTask: Task<Void, Never>?
    private let restartTimeout: TimeInterval
    private var lastAutoCheckAttemptAt: Date?

    // Per-chunk ack timeout. The device acks each chunk after a LittleFS
    // (now esp_ota) write — typically <100ms but flash erase can spike.
    private let autoCheckCooldown: TimeInterval = 15 * 60
    private let chunkAckTimeout: TimeInterval = 5
    private let beginAckTimeout: TimeInterval = 10
    private let endAckTimeout: TimeInterval = 20

    init(releaseService: any FirmwareReleaseProviding = FirmwareReleaseService(), restartTimeout: TimeInterval = 45) {
        self.releaseService = releaseService
        self.restartTimeout = restartTimeout
    }

    func attach(bleManager: any FirmwareUpdateTransport) {
        self.bleManager = bleManager
    }

    // MARK: - Status (called by ESP32Output on connect)

    func recordDeviceVersion(_ version: String?) {
        deviceVersion = version
        if let expected = expectedRestartVersion, let version {
            clearRestartExpectation()
            if version.removingFirmwarePrefix == expected.removingFirmwarePrefix {
                state = .success(version: version)
            } else {
                state = .failed(reason: "Device restarted with \(version); expected \(expected).", recoverable: true)
            }
            return
        }
        // If we already had a release in `.available` for a different version,
        // re-evaluate against the new device version.
        if case .available(let latest, _) = state, let v = version {
            if firmwareVersionIsNewer(latest.version, than: v) {
                state = .available(latest: latest, current: v)
            } else {
                state = .upToDate(version: v)
            }
        }
    }

    // MARK: - Public API

    func checkForUpdates(forceRefresh: Bool = false) {
        guard !state.isMidFlight else { return }
        if !forceRefresh {
            // A reconnect status callback must not erase the just-confirmed
            // installation outcome with an automatic manifest check.
            switch state { case .success, .failed: return; default: break }
            if let lastAutoCheckAttemptAt,
               Date().timeIntervalSince(lastAutoCheckAttemptAt) < autoCheckCooldown {
                return
            }
            lastAutoCheckAttemptAt = Date()
        }
        checkTask?.cancel()
        checkGeneration += 1
        let generation = checkGeneration
        state = .checking
        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let latest = try await self.releaseService.latestRelease(forceRefresh: forceRefresh)
                guard !Task.isCancelled, generation == self.checkGeneration, !self.state.isMidFlight else { return }
                self.offeredRelease = latest
                let current = self.deviceVersion ?? "0.0.0"
                if firmwareVersionIsNewer(latest.version, than: current) {
                    self.state = .available(latest: latest, current: current)
                } else {
                    self.state = .upToDate(version: current)
                }
            } catch {
                guard !Task.isCancelled, generation == self.checkGeneration, !self.state.isMidFlight else { return }
                self.state = .checkFailed(reason: error.localizedDescription)
            }
        }
    }

    func startUpdate() {
        guard case .available(let latest, _) = state else { return }
        checkTask?.cancel()
        checkGeneration += 1
        updateTask?.cancel()
        clearRestartExpectation()
        state = .downloading(progress: 0)
        updateTask = Task { [weak self] in
            await self?.runUpdate(release: latest)
        }
    }

    func cancel() {
        updateTask?.cancel()
        updateTask = nil
        clearRestartExpectation()
        if state.isMidFlight { state = .failed(reason: "Update cancelled", recoverable: true) }
    }

    func dismissTerminal() {
        switch state {
        case .success(let v):
            state = .upToDate(version: v)
        case .failed, .checkFailed:
            if let release = offeredRelease, let current = deviceVersion,
               firmwareVersionIsNewer(release.version, than: current) {
                state = .available(latest: release, current: current)
            } else {
                // Knowing the installed version does not prove it is current.
                state = .idle
            }
        default:
            break
        }
    }

    // MARK: - The main flow

    private func runUpdate(release: FirmwareRelease) async {
        guard !Task.isCancelled else { return }
        // 1. Download the binary (with hash verification done inside the service).
        state = .downloading(progress: 0)
        let binary: Data
        do {
            binary = try await releaseService.downloadBinary(release)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(reason: error.localizedDescription, recoverable: true)
            return
        }
        guard !Task.isCancelled else { return }
        state = .downloading(progress: 1.0)

        guard let ble = bleManager else {
            state = .failed(reason: "BLE manager unavailable", recoverable: false)
            return
        }

        // 2. ota_begin — device decides if it has space, battery, etc.
        let beginFrame = OTAProtocol.beginFrame(
            size: binary.count,
            sha256: release.sha256,
            version: release.version
        )
        do {
            _ = try await ble.sendAwaitingAck(beginFrame, ackKey: "ota_begin", timeout: beginAckTimeout)
        } catch let BLEAckError.ackFailure(message) {
            guard !Task.isCancelled else { return }
            clearRestartExpectation()
            state = .failed(reason: "Device refused update: \(message)", recoverable: true)
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(reason: ackErrorMessage(error, phase: "ota_begin"), recoverable: true)
            return
        }

        guard !Task.isCancelled else { return }

        // 3. Stream chunks. Wall clock is dominated by per-chunk RTT — at
        //    ~96-byte payloads and ~50ms per chunk on BLE, a 1MB image is
        //    ~9 minutes. ETA recomputes from a moving start time.
        let chunks = OTAProtocol.chunks(of: binary)
        let totalChunks = chunks.count
        let started = Date()
        for (seq, chunk) in chunks.enumerated() {
            guard !Task.isCancelled else { return }
            let frame = OTAProtocol.chunkFrame(seq: seq, payload: chunk)
            do {
                _ = try await ble.sendAwaitingAck(frame, ackKey: "ota_chunk", timeout: chunkAckTimeout)
            } catch let BLEAckError.ackFailure(message) {
                guard !Task.isCancelled else { return }
                state = .failed(reason: "Chunk \(seq) rejected: \(message)", recoverable: true)
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(reason: ackErrorMessage(error, phase: "ota_chunk \(seq)"), recoverable: true)
                return
            }
            guard !Task.isCancelled else { return }
            let progress = Double(seq + 1) / Double(totalChunks)
            let elapsed = Date().timeIntervalSince(started)
            let eta = progress > 0 ? Int((elapsed / progress) * (1 - progress)) : 0
            state = .uploading(progress: progress, etaSeconds: eta)
        }

        // 4. ota_end — device verifies and commits. Past this ack the device
        //    will reboot, so the connection drops. We don't retry past this point.
        guard !Task.isCancelled else { return }
        state = .verifying
        expectRestart(version: release.version)
        let endFrame = OTAProtocol.endFrame(sha256: release.sha256)
        do {
            _ = try await ble.sendAwaitingAck(endFrame, ackKey: "ota_end", timeout: endAckTimeout)
        } catch let BLEAckError.ackFailure(message) {
            guard !Task.isCancelled else { return }
            clearRestartExpectation()
            state = .failed(reason: "Verification failed: \(message)", recoverable: true)
            return
        } catch BLEAckError.notConnected {
            // A disconnect may mean reboot, but only a fresh version reply
            // can establish success. The same bounded confirmation handles
            // both an end acknowledgment and an early disconnect.
        } catch {
            guard !Task.isCancelled else { return }
            clearRestartExpectation()
            state = .failed(reason: ackErrorMessage(error, phase: "ota_end"), recoverable: true)
            return
        }
        guard !Task.isCancelled else { return }
        if expectedRestartVersion != nil { state = .rebooting }
    }

    private func clearRestartExpectation() {
        expectedRestartVersion = nil
        restartTask?.cancel()
        restartTask = nil
    }

    private func expectRestart(version: String) {
        clearRestartExpectation()
        expectedRestartVersion = version
        let timeout = restartTimeout
        restartTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            guard let self, self.expectedRestartVersion == version else { return }
            self.clearRestartExpectation()
            self.state = .failed(reason: "Could not confirm the device restarted with \(version). Reconnect and check its version.", recoverable: true)
        }
    }

    private func ackErrorMessage(_ error: Error, phase: String) -> String {
        switch error {
        case BLEAckError.notConnected: return "Device disconnected during \(phase)"
        case BLEAckError.timeout:      return "Device didn't respond to \(phase)"
        case BLEAckError.cancelled:    return "\(phase) cancelled"
        default:                       return "\(phase) failed: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var removingFirmwarePrefix: String { hasPrefix("v") ? String(dropFirst()) : self }
}
