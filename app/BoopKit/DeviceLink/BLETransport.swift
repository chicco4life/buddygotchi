@preconcurrency import CoreBluetooth
import Foundation

/// The device over Bluetooth: a Nordic UART central (PROTOCOL.md §2). Scans
/// for `Boop-*` advertising the NUS service, connects without pairing,
/// subscribes to TX, writes lines to RX in pieces no bigger than the link
/// allows, and reconnects with a backoff.
///
/// Only the menu-bar app creates this. An agent's shell must never start it:
/// macOS kills a process that touches Bluetooth without the right to
/// (CLAUDE.md), which is why tests use `USBTransport`.
public final class BLETransport: NSObject, DeviceTransport, @unchecked Sendable {
    public static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Mac → device.
    public static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Device → Mac.
    public static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    public var name: String { "ble" + (peripheral?.name.map { ":" + $0 } ?? "") }

    // Touched only on `queue`, which is also CoreBluetooth's delegate queue.
    let queue = DispatchQueue(label: "boop.ble", qos: .userInitiated)
    var central: CBCentralManager?
    var peripheral: CBPeripheral?
    var rxCharacteristic: CBCharacteristic?
    var framer = LineFramer()
    var onLine: (@Sendable (String) -> Void)?
    var onConnection: (@Sendable (Bool) -> Void)?
    var running = false
    var retryDelay: TimeInterval = 1
    var connectedAt: Date?

    public override init() {
        super.init()
    }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            self.onLine = onLine
            self.onConnection = onConnection
            running = true
            if central == nil { central = CBCentralManager(delegate: self, queue: queue) } else { scan() }
        }
    }

    public func send(_ line: String) {
        queue.async { [self] in
            guard let peripheral, let rxCharacteristic, peripheral.state == .connected else { return }
            let size = peripheral.maximumWriteValueLength(for: .withoutResponse)
            for chunk in LineFramer.chunks(line, size: size) {
                peripheral.writeValue(chunk, for: rxCharacteristic, type: .withoutResponse)
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        }
    }

    func scan() {
        guard running, let central, central.state == .poweredOn, peripheral == nil else { return }
        central.scanForPeripherals(withServices: [Self.service], options: nil)
    }

    func dropped() {
        let wasUp = rxCharacteristic != nil
        peripheral = nil
        rxCharacteristic = nil
        framer = LineFramer()
        if wasUp { onConnection?(false) }
        // A connection that died quickly backs off, up to 30 s, so a board
        // stuck rebooting isn't hammered.
        if let connectedAt, Date().timeIntervalSince(connectedAt) > 30 { retryDelay = 1 }
        connectedAt = nil
        let delay = retryDelay
        retryDelay = min(30, retryDelay * 2)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scan() }
    }
}

extension BLETransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scan()
        } else if peripheral != nil {
            dropped()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("Boop-"), self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedAt = Date()
        peripheral.discoverServices([Self.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dropped()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        dropped()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.rx, Self.tx], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard let rx = characteristics.first(where: { $0.uuid == Self.rx }),
              let tx = characteristics.first(where: { $0.uuid == Self.tx }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        rxCharacteristic = rx
        peripheral.setNotifyValue(true, for: tx)
        onConnection?(true)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.tx, let value = characteristic.value else { return }
        for line in framer.push(value) { onLine?(line) }
    }
}
