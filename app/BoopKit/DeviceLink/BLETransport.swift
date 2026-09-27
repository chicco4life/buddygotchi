@preconcurrency import CoreBluetooth
import Foundation

/// The device over Bluetooth: a Nordic UART central (PROTOCOL.md §2). Finds
/// a `Boop-*` device, connects without pairing, subscribes to TX, writes
/// lines to RX in pieces no bigger than the link allows, and reconnects
/// after a drop (PROTOCOL.md §2, "Reconnecting").
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
    /// An attempt that can't carry lines this long after it started is
    /// given up and tried again (PROTOCOL.md §2).
    public static let connectTimeout: TimeInterval = 10

    /// Read from any thread, so it's kept apart from `peripheral`.
    public var name: String { nameLock.withLock { linkName } }
    let nameLock = NSLock()
    var linkName = "ble"

    let log: @Sendable (String) -> Void
    // Touched only on `queue`, which is also CoreBluetooth's delegate queue.
    let queue = DispatchQueue(label: "boop.ble", qos: .userInitiated)
    var central: CBCentralManager?
    /// The device being connected to, or connected. Callbacks about any
    /// other peripheral are left over from an attempt already given up.
    var peripheral: CBPeripheral?
    var rxCharacteristic: CBCharacteristic?
    /// Subscribed to TX, so lines flow both ways.
    var up = false
    var framer = LineFramer()
    /// Lines waiting for CoreBluetooth to take them.
    var outbox = BLEOutbox()
    var onLine: (@Sendable (String) -> Void)?
    var onConnection: (@Sendable (Bool) -> Void)?
    var running = false
    var backoff = ReconnectBackoff()
    /// Bumps on every attempt and drop, so an old attempt's timeout does nothing.
    var attempt = 0

    public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
        super.init()
    }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            self.onLine = onLine
            self.onConnection = onConnection
            running = true
            if central == nil { central = CBCentralManager(delegate: self, queue: queue) } else { findDevice() }
        }
    }

    /// Writes without response are dropped once CoreBluetooth's queue is
    /// full, which would splice lines on the device, so each piece waits
    /// until `canSendWriteWithoutResponse`, and `peripheralIsReady` sends
    /// the rest.
    public func send(_ line: String) {
        queue.async { [self] in
            guard up, let peripheral, rxCharacteristic != nil, peripheral.state == .connected else { return }
            outbox.add(line, size: peripheral.maximumWriteValueLength(for: .withoutResponse))
            drain()
        }
    }

    func drain() {
        guard up, let peripheral, let rxCharacteristic else { return }
        while peripheral.canSendWriteWithoutResponse, let chunk = outbox.next() {
            peripheral.writeValue(chunk, for: rxCharacteristic, type: .withoutResponse)
        }
    }

    public func reconnect() {
        queue.async { [self] in
            guard running else { return }
            log("ble: reconnecting on request")
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            forget()
            backoff.reset()
            findDevice()
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        }
    }

    /// Takes over a link macOS already holds, or scans. A device that's
    /// still connected to the Mac isn't advertising, so after the app is
    /// killed and restarted a scan alone would never find it.
    func findDevice() {
        guard running, let central, central.state == .poweredOn, peripheral == nil else { return }
        let held = central.retrieveConnectedPeripherals(withServices: [Self.service])
        if let device = held.first(where: { $0.name?.hasPrefix("Boop-") == true }) {
            log("ble: taking over macOS's connection to \(device.name ?? "Boop")")
            connect(device)
        } else {
            central.scanForPeripherals(withServices: [Self.service], options: nil)
        }
    }

    func connect(_ device: CBPeripheral) {
        central?.stopScan()
        peripheral = device
        nameLock.withLock { linkName = "ble" + (device.name.map { ":" + $0 } ?? "") }
        device.delegate = self
        central?.connect(device, options: nil)
        attempt += 1
        let this = attempt
        queue.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, attempt == this, peripheral === device, !up else { return }
            log("ble: \(device.name ?? "Boop") not ready after \(Int(Self.connectTimeout)) s, trying again")
            giveUp(device)
        }
    }

    /// Ends this attempt or connection and looks again after the backoff.
    func giveUp(_ device: CBPeripheral) {
        central?.cancelPeripheralConnection(device)
        dropped()
    }

    func dropped() {
        forget()
        queue.asyncAfter(deadline: .now() + backoff.next()) { [weak self] in self?.findDevice() }
    }
}

extension BLETransport {
    /// Lets go of the device, so callbacks about it are ignored from now on.
    func forget() {
        let wasUp = up
        peripheral = nil
        nameLock.withLock { linkName = "ble" }
        rxCharacteristic = nil
        up = false
        framer = LineFramer()
        outbox = BLEOutbox()
        attempt += 1
        if wasUp { onConnection?(false) }
    }
}

/// What waits to go out over Bluetooth, as whole lines cut into write-sized
/// pieces. A line that has started goes out whole. A newer `state` takes
/// the place of one still waiting, since only the latest matters, and past
/// `limit` bytes the oldest lines that haven't started are dropped: the next
/// `state` catches the device up (PROTOCOL.md §2).
struct BLEOutbox {
    static let limit = 4096
    private var lines: [(state: Bool, chunks: [Data])] = []
    /// Pieces of the first line already written.
    private var sent = 0

    var bytes: Int { lines.reduce(0) { $0 + $1.chunks.reduce(0) { $0 + $1.count } } }

    mutating func add(_ line: String, size: Int) {
        let state = line.hasPrefix(#"{"t":"state""#)
        let chunks = LineFramer.chunks(line, size: size)
        if state, let i = lines.indices.last(where: { lines[$0].state && ($0 > 0 || sent == 0) }) {
            lines[i].chunks = chunks
        } else {
            lines.append((state, chunks))
        }
        while bytes > Self.limit, lines.count > (sent > 0 ? 2 : 1) {
            lines.remove(at: sent > 0 ? 1 : 0)
        }
    }

    /// The next piece to write, or nil when nothing waits.
    mutating func next() -> Data? {
        guard let first = lines.first else { return nil }
        let chunk = first.chunks[sent]
        sent += 1
        if sent == first.chunks.count {
            lines.removeFirst()
            sent = 0
        }
        return chunk
    }
}

/// How long the Bluetooth link waits before looking for the device again
/// (PROTOCOL.md §2): 1 s after a drop, doubling up to 5 s while attempts
/// keep failing, and back to 1 s once a connection works.
struct ReconnectBackoff {
    static let first: TimeInterval = 1
    static let longest: TimeInterval = 5
    private(set) var delay = first

    mutating func next() -> TimeInterval {
        defer { delay = min(Self.longest, delay * 2) }
        return delay
    }

    mutating func reset() { delay = Self.first }
}

extension BLETransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            findDevice()
        } else if peripheral != nil {
            dropped()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("Boop-"), self.peripheral == nil else { return }
        log("ble: found \(name)")
        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        peripheral.discoverServices([Self.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        log("ble: connect failed: \(error.map { "\($0)" } ?? "no reason given")")
        dropped()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        guard peripheral === self.peripheral else { return }
        log("ble: disconnected" + (error.map { ": \($0)" } ?? ""))
        dropped()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            log("ble: no UART service" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        peripheral.discoverCharacteristics([Self.rx, Self.tx], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        let characteristics = service.characteristics ?? []
        guard error == nil, let rx = characteristics.first(where: { $0.uuid == Self.rx }),
              let tx = characteristics.first(where: { $0.uuid == Self.tx }) else {
            log("ble: no RX and TX" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        rxCharacteristic = rx
        peripheral.setNotifyValue(true, for: tx)
    }

    /// The link is up once the device's lines can reach the Mac.
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == Self.tx, !up else { return }
        guard error == nil, characteristic.isNotifying else {
            log("ble: can't subscribe to TX" + (error.map { ": \($0)" } ?? ""))
            return giveUp(peripheral)
        }
        up = true
        backoff.reset()
        log("ble: connected to \(peripheral.name ?? "Boop")")
        onConnection?(true)
    }

    /// A reflashed device whose GATT table changed: macOS's cached copy is
    /// stale, so start over.
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === self.peripheral, invalidatedServices.contains(where: { $0.uuid == Self.service }) else { return }
        log("ble: the device's services changed, reconnecting")
        giveUp(peripheral)
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        drain()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == Self.tx, let value = characteristic.value else { return }
        for line in framer.push(value) { onLine?(line) }
    }
}
