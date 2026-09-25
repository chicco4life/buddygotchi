import Foundation

/// Splits a byte stream into lines (PROTOCOL.md §2). A line can arrive in
/// several Bluetooth packets or serial reads; it's complete at `\n`. A line
/// longer than `maxLine` is dropped whole, so a screenshot passing through
/// the USB bridge can't grow the buffer without bound.
public struct LineFramer: Sendable {
    public let maxLine: Int
    var buffer: [UInt8] = []
    var skipping = false

    public init(maxLine: Int = 4096) {
        self.maxLine = maxLine
    }

    public mutating func push<Bytes: Sequence>(_ bytes: Bytes) -> [String] where Bytes.Element == UInt8 {
        var lines: [String] = []
        for byte in bytes {
            if byte == 0x0A {
                if !skipping {
                    if buffer.last == 0x0D { buffer.removeLast() }
                    if !buffer.isEmpty { lines.append(String(decoding: buffer, as: UTF8.self)) }
                }
                buffer.removeAll(keepingCapacity: true)
                skipping = false
            } else if !skipping {
                buffer.append(byte)
                if buffer.count > maxLine {
                    buffer.removeAll(keepingCapacity: true)
                    skipping = true
                }
            }
        }
        return lines
    }

    /// `line` and its newline cut into pieces of at most `size` bytes, for
    /// Bluetooth writes.
    public static func chunks(_ line: String, size: Int) -> [Data] {
        var data = Data(line.utf8)
        data.append(0x0A)
        let size = max(1, size)
        return stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min(data.count, $0 + size)) }
    }
}

/// The device's `status` message (PROTOCOL.md §4).
public struct DeviceStatus: Equatable, Sendable {
    /// `b00p-7f3a`: which Boop this body is.
    public var id: String
    public var fw: String
    /// Battery in mV.
    public var bat: Int
    public var usb: Bool

    public init(id: String, fw: String, bat: Int = 0, usb: Bool = true) {
        self.id = id
        self.fw = fw
        self.bat = bat
        self.usb = usb
    }
}

/// A line from the device.
public enum DeviceMessage: Equatable, Sendable {
    case status(DeviceStatus)
    case input(Core.Input)
    /// Anything else: debug replies passing through the bridge, unknown types.
    case other(String)

    public static func decode(_ line: String) -> DeviceMessage {
        guard line.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = object["t"] as? String
        else { return .other(line) }
        switch type {
        case "status":
            guard let id = object["id"] as? String else { return .other(line) }
            return .status(DeviceStatus(id: id, fw: object["fw"] as? String ?? "?",
                                        bat: (object["bat"] as? NSNumber)?.intValue ?? 0,
                                        usb: (object["usb"] as? NSNumber)?.intValue != 0))
        case "input":
            guard let input = (object["k"] as? String).flatMap(Core.Input.init(rawValue:)) else { return .other(line) }
            return .input(input)
        default:
            return .other(line)
        }
    }
}
