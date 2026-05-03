import Foundation
import Observation

let esp32PeripheralUUIDKey = "esp32PeripheralUUID"

@Observable
@MainActor
final class ESP32Output: OutputProvider, BLEManagerDelegate {
    let id = "esp32"
    private let bleManager = BLEManager()
    private var keepaliveTimer: Timer?
    private var lastState: BuddyState?
    private weak var engine: BuddyEngine?

    private(set) var connectionState: BLEConnectionState = .disconnected

    func start(engine: BuddyEngine) async {
        self.engine = engine
        bleManager.delegate = self
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
        guard let uuidStr = UserDefaults.standard.string(forKey: esp32PeripheralUUIDKey),
              let uuid = UUID(uuidString: uuidStr) else { return }
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
        UserDefaults.standard.removeObject(forKey: esp32PeripheralUUIDKey)
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
        if state == .connected { sendNow() }
    }

    func bleManager(_ manager: BLEManager, didReceiveApproval requestId: String, decision: String) {
        let mapped: ApprovalDecision = (decision == "allow") ? .allow : .deny
        engine?.resolveApproval(requestId: requestId, decision: mapped)
    }
}
