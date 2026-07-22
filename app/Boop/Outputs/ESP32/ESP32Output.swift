import Foundation
import Observation

let esp32PeripheralUUIDKey = DefaultsKey.esp32PeripheralUUID

@Observable
@MainActor
final class ESP32Output: OutputProvider, BLEManagerDelegate {
    let id = "esp32"
    private let bleManager = BLEManager()
    private var keepaliveTimer: Timer?
    private var lastState: BuddyState?
    private weak var engine: BuddyEngine?

    private(set) var connectionState: BLEConnectionState = .disconnected
    let firmwareUpdater = FirmwareUpdater()

    func start(engine: BuddyEngine) async {
        self.engine = engine
        bleManager.delegate = self
        firmwareUpdater.attach(bleManager: bleManager)
        connectToSavedDevice()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendNow() }
        }
    }

    func stop() async {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        bleManager.disconnect()
    }

    func connectToSavedDevice() {
        guard let uuidStr = UserDefaults.standard.string(forKey: DefaultsKey.esp32PeripheralUUID),
              let uuid = UUID(uuidString: uuidStr) else { return }
        bleManager.connect(peripheralIdentifier: uuid)
    }

    func connect(to uuid: UUID) {
        bleManager.connect(peripheralIdentifier: uuid)
    }

    func unpair() {
        if bleManager.connectionState == .connected {
            let json = "{\"cmd\":\"unpair\"}\n"
            if let data = json.data(using: .utf8) {
                bleManager.send(data)
            }
        }
        bleManager.disconnect()
        UserDefaults.standard.removeObject(forKey: DefaultsKey.esp32PeripheralUUID)
        connectionState = .disconnected
    }

    func sendTestCelebrate() {
        guard bleManager.connectionState == .connected else { return }
        var celebrateState = lastState ?? .initial
        celebrateState.pet = Pet(state: .celebrate, species: celebrateState.pet.species)
        celebrateState.celebrateUntil = Date().timeIntervalSince1970 + 5
        if let data = renderStateData(from: celebrateState) {
            bleManager.send(data)
        }
    }

    func sendNow() {
        guard bleManager.connectionState == .connected,
              let s = lastState,
              let data = renderStateData(from: s) else { return }
        bleManager.send(data)
    }

    func stateDidChange(prev: BuddyState, next: BuddyState) {
        lastState = next
        sendNow()
    }

    func bleManager(_ manager: BLEManager, connectionStateChanged state: BLEConnectionState) {
        connectionState = state
        if state == .connected {
            sendNow()
            Task { await refreshDeviceFirmware() }
        }
    }

    func bleManager(_ manager: BLEManager, didReceiveApproval requestId: String, decision: String) {
        let mapped: ApprovalDecision = (decision == "allow") ? .allow : .deny
        engine?.resolveApproval(requestId: requestId, decision: mapped)
    }

    func bleManagerDidReceiveBoop(_ manager: BLEManager) {
        engine?.boop()
    }

    // The device menu adopted a character. Mirror it into the desktop
    // preference and the engine so the next heartbeat carries the same
    // species instead of stomping the on-device choice on reconnect.
    func bleManager(_ manager: BLEManager, didAdoptSpecies species: String) {
        let name = species.lowercased()
        guard !name.isEmpty, name.count <= 16,
              name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        UserDefaults.standard.set(name, forKey: DefaultsKey.buddySpecies)
        engine?.setSpecies(name)
    }

    // Round-trips a {"cmd":"status"} request and reads firmware/build out of
    // the response so the updater can compare it against the latest manifest.
    // Failures here are silent — without a version we just don't surface a
    // badge. The next reconnect retries.
    private func refreshDeviceFirmware() async {
        let frame = "{\"cmd\":\"status\"}\n".data(using: .utf8) ?? Data()
        do {
            let reply = try await bleManager.sendAwaitingAck(frame, ackKey: "status", timeout: 3)
            let version = reply.status?.firmware
            firmwareUpdater.recordDeviceVersion(version)
            firmwareUpdater.checkForUpdates()
        } catch {
            // Swallow — old firmware doesn't include the `firmware` field, and
            // we don't want to spam the UI on a transient timeout.
            #if DEBUG
            print("[ESP32Output] firmware status query failed: \(error)")
            #endif
        }
    }
}
