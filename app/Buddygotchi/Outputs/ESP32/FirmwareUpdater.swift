import Foundation
import Observation

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

    // Last known firmware version reported by the device's status reply.
    // Stays nil until the first successful status round-trip after connect.
    private(set) var deviceVersion: String?

    private let releaseService: FirmwareReleaseService
    private weak var bleManager: BLEManager?

    private var updateTask: Task<Void, Never>?

    // Per-chunk ack timeout. The device acks each chunk after a LittleFS
    // (now esp_ota) write — typically <100ms but flash erase can spike.
    private let chunkAckTimeout: TimeInterval = 5
    private let beginAckTimeout: TimeInterval = 10
    private let endAckTimeout: TimeInterval = 20

    init(releaseService: FirmwareReleaseService = FirmwareReleaseService()) {
        self.releaseService = releaseService
    }

    func attach(bleManager: BLEManager) {
        self.bleManager = bleManager
    }

    // MARK: - Status (called by ESP32Output on connect)

    func recordDeviceVersion(_ version: String?) {
        deviceVersion = version
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
        Task { [weak self] in
            guard let self else { return }
            self.state = .checking
            do {
                let latest = try await self.releaseService.latestRelease(forceRefresh: forceRefresh)
                let current = self.deviceVersion ?? "0.0.0"
                if firmwareVersionIsNewer(latest.version, than: current) {
                    self.state = .available(latest: latest, current: current)
                } else {
                    self.state = .upToDate(version: current)
                }
            } catch {
                self.state = .failed(reason: error.localizedDescription, recoverable: true)
            }
        }
    }

    func startUpdate() {
        guard case .available(let latest, let current) = state else { return }
        cancel()
        updateTask = Task { [weak self] in
            await self?.runUpdate(release: latest, currentVersion: current)
        }
    }

    func cancel() {
        updateTask?.cancel()
        updateTask = nil
    }

    func dismissTerminal() {
        switch state {
        case .success(let v):
            state = .upToDate(version: v)
        case .failed:
            // Re-evaluate against the cached device version so the row
            // doesn't get stuck showing "Failed" forever.
            if let v = deviceVersion {
                state = .upToDate(version: v)
            } else {
                state = .idle
            }
        default:
            break
        }
    }

    // MARK: - The main flow

    private func runUpdate(release: FirmwareRelease, currentVersion: String) async {
        // 1. Download the binary (with hash verification done inside the service).
        state = .downloading(progress: 0)
        let binary: Data
        do {
            binary = try await releaseService.downloadBinary(release)
        } catch {
            state = .failed(reason: error.localizedDescription, recoverable: true)
            return
        }
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
            state = .failed(reason: "Device refused update: \(message)", recoverable: true)
            return
        } catch {
            state = .failed(reason: ackErrorMessage(error, phase: "ota_begin"), recoverable: true)
            return
        }

        // 3. Stream chunks. Wall clock is dominated by per-chunk RTT — at
        //    ~96-byte payloads and ~50ms per chunk on BLE, a 1MB image is
        //    ~9 minutes. ETA recomputes from a moving start time.
        let chunks = OTAProtocol.chunks(of: binary)
        let totalChunks = chunks.count
        let started = Date()
        for (seq, chunk) in chunks.enumerated() {
            if Task.isCancelled {
                state = .failed(reason: "Update cancelled", recoverable: true)
                return
            }
            let frame = OTAProtocol.chunkFrame(seq: seq, payload: chunk)
            do {
                _ = try await ble.sendAwaitingAck(frame, ackKey: "ota_chunk", timeout: chunkAckTimeout)
            } catch let BLEAckError.ackFailure(message) {
                state = .failed(reason: "Chunk \(seq) rejected: \(message)", recoverable: true)
                return
            } catch {
                state = .failed(reason: ackErrorMessage(error, phase: "ota_chunk \(seq)"), recoverable: true)
                return
            }
            let progress = Double(seq + 1) / Double(totalChunks)
            let elapsed = Date().timeIntervalSince(started)
            let eta = progress > 0 ? Int((elapsed / progress) * (1 - progress)) : 0
            state = .uploading(progress: progress, etaSeconds: eta)
        }

        // 4. ota_end — device verifies and commits. Past this ack the device
        //    will reboot, so the connection drops. We don't retry past this point.
        state = .verifying
        let endFrame = OTAProtocol.endFrame(sha256: release.sha256)
        do {
            _ = try await ble.sendAwaitingAck(endFrame, ackKey: "ota_end", timeout: endAckTimeout)
        } catch let BLEAckError.ackFailure(message) {
            state = .failed(reason: "Verification failed: \(message)", recoverable: true)
            return
        } catch BLEAckError.notConnected {
            // Disconnect after ota_end is normal — the device reboots before
            // sending the ack on slower flash. Treat as success-pending and
            // let the reconnect prove it.
            state = .rebooting
            return
        } catch {
            state = .failed(reason: ackErrorMessage(error, phase: "ota_end"), recoverable: true)
            return
        }

        // 5. Reboot — BLEManager's auto-reconnect will rediscover the device
        //    and ESP32Output will refresh deviceVersion via status. We optimistically
        //    surface success now; the next status reply will confirm.
        state = .rebooting
        // Hold the rebooting state for ~5s, then declare success. If reconnect
        // brings back the OLD version, recordDeviceVersion will detect that
        // and re-check naturally.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if Task.isCancelled { return }
        state = .success(version: release.version)
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
