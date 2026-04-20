import Foundation

@MainActor
final class ESP32Output: OutputProvider, BLEManagerDelegate {
    let id = "esp32"
    private let bleManager = BLEManager()
    private var keepaliveTimer: Timer?
    private var lastState: BuddyState?

    func start(engine: BuddyEngine) async {
        bleManager.delegate = self
        if let uuidStr = UserDefaults.standard.string(forKey: "esp32PeripheralUUID"),
           let uuid = UUID(uuidString: uuidStr) {
            bleManager.connect(peripheralIdentifier: uuid)
        }
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendKeepalive() }
        }
    }

    func stop() async {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        bleManager.disconnect()
    }

    func stateDidChange(prev: BuddyState, next: BuddyState) {
        lastState = next
        guard bleManager.connectionState == .connected else { return }
        if let data = heartbeatData(from: next) {
            bleManager.send(data)
        }
    }

    func bleManager(_ manager: BLEManager, connectionStateChanged state: BLEConnectionState) {
        if state == .connected, let s = lastState, let data = heartbeatData(from: s) {
            bleManager.send(data)
        }
    }

    private func sendKeepalive() {
        guard bleManager.connectionState == .connected,
              let s = lastState,
              let data = heartbeatData(from: s) else { return }
        bleManager.send(data)
    }
}
