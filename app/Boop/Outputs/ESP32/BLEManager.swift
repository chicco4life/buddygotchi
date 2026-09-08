import Foundation
import Observation
import os
@preconcurrency import CoreBluetooth

enum BLEConnectionState: String, Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
}

enum BLEAckError: Error {
    case notConnected
    case timeout
    case cancelled
    case ackFailure(message: String)   // device returned ok:false
}

struct BLEAckReply: Sendable, Equatable {
    struct StatusData: Sendable, Equatable {
        let firmware: String?
        let build: String?
        var board: String? = nil
        var contract: Int? = nil
    }

    let ack: String
    let count: Int?
    let errorMessage: String?
    let status: StatusData?
}

@MainActor
protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, connectionStateChanged state: BLEConnectionState)
    func bleManager(_ manager: BLEManager, didReceive command: DeviceCommand)
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

    // Reports whether the radio can scan (false for poweredOff/unauthorized/
    // unsupported). Called on bleQueue; set this before the first startScan()
    // and don't mutate it afterwards — the dispatch into bleQueue is what
    // makes the initial write visible there.
    var onBluetoothAvailabilityChange: (@Sendable (Bool) -> Void)?

    private var central: CBCentralManager?
    private let bleQueue = DispatchQueue(label: "boop.ble", qos: .userInitiated)

    private var targetPeripheralIdentifier: UUID?
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var scanContinuation: AsyncStream<DiscoveredPeripheral>.Continuation?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 1.0

    // Backoff only resets after a connection *survives* this long. Resetting
    // on didConnect (the old behavior) meant a device that crashed right
    // after connecting got re-hammered at 1s forever — the app amplified the
    // 2026-07 firmware bootloop instead of backing off.
    private static let stableConnectionSeconds: TimeInterval = 30
    private var connectedAt: Date?
    private var shortConnectionStreak = 0

    // Landing in the bug-report export is the point: DiagnosticLog collects
    // OSLog entries for this subsystem.
    private let log = Logger(subsystem: "com.boopcomputer.boop", category: "ble")

    private var rxBuffer = Data()

    // Outstanding ack waiters, keyed by the `ack` value the device echoes
    // back. Touched only on bleQueue. The OTA flow is strictly synchronous
    // (one outstanding "ota_chunk" at a time), so a single-slot-per-key
    // map is sufficient — second writer would clobber the first, which is
    // a programming error, not a runtime concern.
    /// A waiter plus the token identifying *which* wait it is.
    ///
    /// The timeout timer can't be cancelled once scheduled, so it must be able
    /// to tell whether the waiter it finds is still its own. Without the token
    /// every OTA died: each chunk reuses the key "ota_chunk", so chunk 0's 5s
    /// timer fired long after chunk 0 was acked and failed whichever chunk
    /// happened to be in flight at t+5s — no update could get past the first
    /// five seconds.
    private struct PendingAck {
        let token: UInt64
        let continuation: CheckedContinuation<BLEAckReply, Error>
    }
    private var pendingAcks: [String: PendingAck] = [:]
    private var nextAckToken: UInt64 = 0

    struct DiscoveredPeripheral: Sendable {
        let identifier: UUID
        let name: String
    }

    static let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusRxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusTxUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    override init() {
        super.init()
    }

    // MARK: - Public API

    func startScan() -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { continuation in
            let queue = self.bleQueue
            continuation.onTermination = { _ in
                queue.async { [weak self] in self?.central?.stopScan() }
            }
            bleQueue.async { [weak self] in
                guard let self else { return }
                let central = self.ensureCentral()
                self.scanContinuation = continuation
                guard central.state == .poweredOn else { return }
                central.scanForPeripherals(
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
            self.central?.stopScan()
        }
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(peripheralIdentifier: UUID) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.log.info("connect requested: \(peripheralIdentifier, privacy: .public)")
            self.targetPeripheralIdentifier = peripheralIdentifier
            self.reconnectDelay = 1.0
            self.shortConnectionStreak = 0
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
                self.central?.cancelPeripheralConnection(peripheral)
                self.connectedPeripheral = nil
            }
        }
        connectionState = .disconnected
    }

    // One ATT write must fit the negotiated MTU (~185 on macOS) minus the
    // 3-byte ATT header. Anything larger becomes a CoreBluetooth "long
    // write" (prepare/execute), which the NimBLE-backed Arduino stack on
    // the ws-amoled164 board never delivers — heartbeats silently vanish
    // while small frames (time sync, acks) arrive. Chunk exactly like
    // buddyctl does; .withResponse writes are serialized by CoreBluetooth,
    // and the firmware's line buffer reassembles on the trailing newline.
    private static let writeChunkSize = 180

    func send(_ data: Data) {
        bleQueue.async { [weak self] in
            guard let self,
                  let rx = self.rxCharacteristic,
                  let peripheral = self.connectedPeripheral else { return }
            // Frames go without response when the link allows it: a
            // with-response write costs about two connection intervals per
            // chunk, which is most of the hook-to-card latency. Falls back to
            // with-response whenever CoreBluetooth's outbound buffer is full.
            let fast = rx.properties.contains(.writeWithoutResponse)
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: Self.writeChunkSize, limitedBy: data.endIndex) ?? data.endIndex
                let type: CBCharacteristicWriteType = fast && peripheral.canSendWriteWithoutResponse ? .withoutResponse : .withResponse
                peripheral.writeValue(data.subdata(in: offset..<end), for: rx, type: type)
                offset = end
            }
        }
    }

    func sendTimeSync() {
        let epoch = Int(Date().timeIntervalSince1970)
        let tzOffset = TimeZone.current.secondsFromGMT()
        let json = "{\"time\":[\(epoch),\(tzOffset)]}\n"
        guard let data = json.data(using: .utf8) else { return }
        send(data)
    }

    // Write a frame and suspend until the device echoes back a JSON line
    // whose "ack" value equals `ackKey`. Used by the OTA flow as the
    // back-pressure primitive — every chunk waits for confirmation
    // before the next chunk goes out, mirroring xfer.h::_xAck.
    func sendAwaitingAck(_ data: Data, ackKey: String, timeout: TimeInterval) async throws -> BLEAckReply {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<BLEAckReply, Error>) in
            bleQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: BLEAckError.cancelled)
                    return
                }
                guard let rx = self.rxCharacteristic, let peripheral = self.connectedPeripheral else {
                    cont.resume(throwing: BLEAckError.notConnected)
                    return
                }
                if let stale = self.pendingAcks.removeValue(forKey: ackKey) {
                    // A previous waiter on this key is being abandoned. Don't
                    // leak the continuation — it would never resume.
                    stale.continuation.resume(throwing: BLEAckError.cancelled)
                }
                self.nextAckToken &+= 1
                let token = self.nextAckToken
                self.pendingAcks[ackKey] = PendingAck(token: token, continuation: cont)
                peripheral.writeValue(data, for: rx, type: .withResponse)
                self.bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    // Only time out the wait this timer was armed for; a later
                    // wait on the same key has its own timer already running.
                    guard self.pendingAcks[ackKey]?.token == token else { return }
                    if let pending = self.pendingAcks.removeValue(forKey: ackKey) {
                        pending.continuation.resume(throwing: BLEAckError.timeout)
                    }
                }
            }
        }
    }

    private func ackReply(from json: [String: Any], ackKey: String) -> BLEAckReply {
        let data = json["data"] as? [String: Any]
        let count = (json["n"] as? Int) ?? (json["n"] as? NSNumber)?.intValue
        let status = data.map {
            BLEAckReply.StatusData(
                firmware: $0["firmware"] as? String,
                build: $0["build"] as? String,
                board: $0["board"] as? String,
                contract: $0["contract"] as? Int
            )
        }
        return BLEAckReply(
            ack: ackKey,
            count: count,
            errorMessage: json["error"] as? String,
            status: status
        )
    }

    // Failing waiters on disconnect prevents UI states from hanging
    // forever when the device drops mid-OTA.
    private func failAllPendingAcks(with error: Error) {
        let waiters = pendingAcks
        pendingAcks.removeAll()
        for (_, pending) in waiters {
            pending.continuation.resume(throwing: error)
        }
    }

    // MARK: - Private

    private func startConnecting() {
        guard let targetId = targetPeripheralIdentifier else { return }
        let central = ensureCentral()
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
        log.info("reconnect scheduled in \(delay, format: .fixed(precision: 1))s")

        let work = DispatchWorkItem { [weak self] in
            self?.startConnecting()
        }
        reconnectWorkItem = work
        bleQueue.asyncAfter(deadline: .now() + delay, execute: work)
        Task { @MainActor [weak self] in self?.connectionState = .disconnected }
    }

    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let manager = CBCentralManager(delegate: self, queue: bleQueue)
        central = manager
        return manager
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("central state: \(central.state.rawValue)")
        // Only report definitive states; .unknown/.resetting are transient
        // and shouldn't flap the UI.
        switch central.state {
        case .poweredOn:
            onBluetoothAvailabilityChange?(true)
        case .poweredOff, .unauthorized, .unsupported:
            onBluetoothAvailabilityChange?(false)
        default:
            break
        }
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
        // Deliberately NOT resetting reconnectDelay here — the connection
        // hasn't proven itself yet. See stableConnectionSeconds.
        connectedAt = Date()
        log.info("connected to \(peripheral.identifier, privacy: .public)")
        peripheral.discoverServices([Self.nusServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.warning("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let lifetime = connectedAt.map { Date().timeIntervalSince($0) }
        connectedAt = nil
        if let lifetime, lifetime >= Self.stableConnectionSeconds {
            reconnectDelay = 1.0
            shortConnectionStreak = 0
        } else if lifetime != nil {
            // Connection died young: keep the backoff growing so a device
            // that crashes on connect isn't hammered into a crash loop.
            shortConnectionStreak += 1
            if shortConnectionStreak >= 3 {
                log.error("connection flapping: \(self.shortConnectionStreak) short-lived connections in a row — device may be crashing on connect")
            }
        }
        log.info("disconnected after \(lifetime.map { String(format: "%.1fs", $0) } ?? "n/a", privacy: .public): \(error?.localizedDescription ?? "clean", privacy: .public)")
        connectedPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        rxBuffer.removeAll()
        failAllPendingAcks(with: BLEAckError.notConnected)
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
        log.debug("rx: \(line, privacy: .public)")
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // The status ack carries the device's crash telemetry (reset reason,
        // panic count, safe-mode tier). Log it at info so it lands in the
        // OSLog window the bug-report export collects — the device's crash
        // history rides along without a serial cable.
        if (json["ack"] as? String) == "status" {
            log.info("device status: \(line, privacy: .public)")
        }

        // Ack frames resolve any matching waiter. ok:false is surfaced as a
        // throwing failure so the OTA flow can transition to .failed without
        // having to inspect the payload itself.
        if let ackKey = json["ack"] as? String,
           let pending = pendingAcks.removeValue(forKey: ackKey) {
            let ok = (json["ok"] as? Bool) ?? true
            if ok {
                pending.continuation.resume(returning: ackReply(from: json, ackKey: ackKey))
            } else {
                let msg = (json["error"] as? String) ?? "device rejected \(ackKey)"
                pending.continuation.resume(throwing: BLEAckError.ackFailure(message: msg))
            }
            return
        }

        if let command = parseDeviceLine(line) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.bleManager(self, didReceive: command)
            }
        }

    }
}

// MARK: - BLE Scanner (shared scan state for views)

@Observable
@MainActor
final class BLEScanner {
    private(set) var devices: [BLEManager.DiscoveredPeripheral] = []
    private(set) var isScanning = false
    /// True while the radio can't scan (Bluetooth off, or access denied).
    private(set) var bluetoothUnavailable = false

    private var bleManager: BLEManager?
    private var scanTask: Task<Void, Never>?

    func start() {
        stop()
        isScanning = true
        bluetoothUnavailable = false
        let manager = BLEManager()
        manager.onBluetoothAvailabilityChange = { [weak self] available in
            Task { @MainActor [weak self] in self?.bluetoothUnavailable = !available }
        }
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
        bluetoothUnavailable = false
        scanTask?.cancel()
        scanTask = nil
        bleManager?.stopScan()
        bleManager = nil
    }
}
