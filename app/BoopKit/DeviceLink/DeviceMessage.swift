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
    /// The version of the voice pack on its card (VOICE.md §8), `none`
    /// with no card or none readable, or nil from firmware that doesn't say.
    public var voice: String?

    public init(id: String, fw: String, voice: String? = nil) {
        self.id = id
        self.fw = fw
        self.voice = voice
    }

    /// Whether it plays the takes the app picks from: its card has the
    /// same pack as `Take.all`, or it doesn't say.
    public var hasTheVoice: Bool { voice.map { $0 == Take.packVersion } ?? true }
}

/// The device's `ended` message (PROTOCOL.md §4): a moment the app waited
/// on is over.
public struct MomentEnded: Equatable, Sendable {
    public enum How: String, Sendable {
        /// It played to the end.
        case done
        /// Something stopped it early: `why` says what.
        case cut
        /// None of it played: something needed you.
        case skipped
    }

    /// The moment's `id`, as the app sent it.
    public var id: Int
    public var how: How
    /// With `cut`: `tap`, `moment`, `needs_you` or `reset`; nil when the
    /// device doesn't say.
    public var why: String?

    public init(id: Int, how: How, why: String? = nil) {
        self.id = id
        self.how = how
        self.why = why
    }
}

/// A line from the device.
public enum DeviceMessage: Equatable, Sendable {
    case status(DeviceStatus)
    /// An `input` whose `k` is `tap`.
    case tap
    /// An `input` whose `k` is `talk_on` (true) or `talk_off`: the BOOT
    /// button held for push-to-talk, or let go (PROTOCOL.md §4).
    case talk(Bool)
    case ended(MomentEnded)
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
            return .status(DeviceStatus(id: id, fw: object["fw"] as? String ?? "?", voice: object["voice"] as? String))
        case "input":
            switch object["k"] as? String {
            case "tap": return .tap
            case "talk_on": return .talk(true)
            case "talk_off": return .talk(false)
            default: return .other(line)
            }
        case "ended":
            guard let id = (object["id"] as? NSNumber)?.intValue, id > 0,
                  let how = (object["how"] as? String).flatMap(MomentEnded.How.init(rawValue:))
            else { return .other(line) }
            return .ended(MomentEnded(id: id, how: how, why: object["why"] as? String))
        default:
            return .other(line)
        }
    }
}
