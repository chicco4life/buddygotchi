import Foundation
import Observation
@preconcurrency import CoreBluetooth

enum BLEConnectionState: String, Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
}

@MainActor
protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, connectionStateChanged state: BLEConnectionState)
    func bleManager(_ manager: BLEManager, didReceiveApproval requestId: String, decision: String)
}

// Threading model: all BLE/peripheral state (target id, peripherals, characteristics,
// reconnect bookkeeping, scan continuation, rx buffer) is touched ONLY on `bleQueue` —
// both the public API and the CoreBluetooth delegate callbacks. `connectionState` is the
// single published property and is only ever written on the main actor (delegate-driven
// writes hop there via `Task { @MainActor }`).
final class BLEManager: NSObject, @unchecked Sendable {
    weak var delegate: BLEManagerDelegate?
    private(set) var connectionState: BLEConnectionState = .disconnected {
        didSet {
            guard connectionState != oldValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.bleManager(self, connectionStateChanged: self.connectionState)
            }
        }
    }

    private var central: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "buddygotchi.ble", qos: .userInitiated)

    private var targetPeripheralIdentifier: UUID?
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var scanContinuation: AsyncStream<DiscoveredPeripheral>.Continuation?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 1.0

    private var rxBuffer = Data()

    struct DiscoveredPeripheral: Sendable {
        let identifier: UUID
        let name: String
    }

    static let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusRxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusTxUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public API

    func startScan() -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { continuation in
            let queue = self.bleQueue
            let central = self.central!
            continuation.onTermination = { _ in
                queue.async { central.stopScan() }
            }
            bleQueue.async { [weak self] in
                guard let self else { return }
                self.scanContinuation = continuation
                guard self.central.state == .poweredOn else { return }
                self.central.scanForPeripherals(
                    withServices: [Self.nusServiceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
            self.connectionState = .scanning
        }
    }

    func stopScan() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.scanContinuation?.finish()
            self.scanContinuation = nil
            self.central.stopScan()
        }
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(peripheralIdentifier: UUID) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.targetPeripheralIdentifier = peripheralIdentifier
            self.reconnectDelay = 1.0
            self.startConnecting()
        }
    }

    func disconnect() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.targetPeripheralIdentifier = nil
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            if let peripheral = self.connectedPeripheral {
                self.central.cancelPeripheralConnection(peripheral)
                self.connectedPeripheral = nil
            }
        }
        connectionState = .disconnected
    }

    func send(_ data: Data) {
        bleQueue.async { [weak self] in
            guard let self,
                  let rx = self.rxCharacteristic,
                  let peripheral = self.connectedPeripheral else { return }
            peripheral.writeValue(data, for: rx, type: .withResponse)
        }
    }

    func sendTimeSync() {
        let epoch = Int(Date().timeIntervalSince1970)
        let tzOffset = TimeZone.current.secondsFromGMT()
        let json = "{\"time\":[\(epoch),\(tzOffset)]}\n"
        guard let data = json.data(using: .utf8) else { return }
        send(data)
    }

    // MARK: - Private

    private func startConnecting() {
        guard let targetId = targetPeripheralIdentifier else { return }
        guard central.state == .poweredOn else { return }

        let known = central.retrievePeripherals(withIdentifiers: [targetId])
        if let peripheral = known.first {
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            Task { @MainActor [weak self] in self?.connectionState = .connecting }
        } else {
            central.scanForPeripherals(
                withServices: [Self.nusServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            Task { @MainActor [weak self] in self?.connectionState = .scanning }
        }
    }

    private func scheduleReconnect() {
        guard targetPeripheralIdentifier != nil else { return }
        let delay = min(reconnectDelay, 30.0)
        reconnectDelay = min(reconnectDelay * 2, 30.0)

        let work = DispatchWorkItem { [weak self] in
            self?.startConnecting()
        }
        reconnectWorkItem = work
        bleQueue.asyncAfter(deadline: .now() + delay, execute: work)
        Task { @MainActor [weak self] in self?.connectionState = .disconnected }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if targetPeripheralIdentifier != nil {
                startConnecting()
            } else if scanContinuation != nil {
                central.scanForPeripherals(
                    withServices: [Self.nusServiceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

        if let continuation = scanContinuation {
            continuation.yield(DiscoveredPeripheral(identifier: peripheral.identifier, name: name))
        }

        if let targetId = targetPeripheralIdentifier, peripheral.identifier == targetId {
            central.stopScan()
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            Task { @MainActor [weak self] in self?.connectionState = .connecting }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectDelay = 1.0
        peripheral.discoverServices([Self.nusServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        rxBuffer.removeAll()
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.nusServiceUUID }) else {
            return
        }
        peripheral.discoverCharacteristics([Self.nusRxUUID, Self.nusTxUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == Self.nusRxUUID { rxCharacteristic = c }
            if c.uuid == Self.nusTxUUID {
                txCharacteristic = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
        if rxCharacteristic != nil {
            Task { @MainActor [weak self] in self?.connectionState = .connected }
            sendTimeSync()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.nusTxUUID, let data = characteristic.value else { return }
        rxBuffer.append(data)

        if rxBuffer.count > 4096 {
            rxBuffer.removeAll()
            return
        }

        while let newlineIndex = rxBuffer.firstIndex(of: 0x0A) {
            let lineData = rxBuffer[rxBuffer.startIndex..<newlineIndex]
            rxBuffer = Data(rxBuffer[(newlineIndex + 1)...])

            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                handleIncomingLine(line)
            }
        }
    }

    private func handleIncomingLine(_ line: String) {
        #if DEBUG
        print("[BLE RX] \(line)")
        #endif
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = json["cmd"] as? String,
              cmd == "permission",
              let id = json["id"] as? String,
              let decision = json["decision"] as? String
        else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didReceiveApproval: id, decision: decision)
        }
    }
}

// MARK: - BLE Scanner (shared scan state for views)

@Observable
@MainActor
final class BLEScanner {
    private(set) var devices: [BLEManager.DiscoveredPeripheral] = []
    private(set) var isScanning = false

    private var bleManager: BLEManager?
    private var scanTask: Task<Void, Never>?

    func start() {
        stop()
        isScanning = true
        let manager = BLEManager()
        bleManager = manager
        devices = []
        let stream = manager.startScan()
        scanTask = Task {
            for await device in stream {
                if !devices.contains(where: { $0.identifier == device.identifier }) {
                    devices.append(device)
                }
            }
        }
    }

    func stop() {
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        bleManager?.stopScan()
        bleManager = nil
    }
}
