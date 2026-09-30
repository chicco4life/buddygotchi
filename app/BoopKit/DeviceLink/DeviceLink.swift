import Foundation

/// One way to reach the device: Bluetooth or the USB bridge. Both carry the
/// same lines (PROTOCOL.md §2), so nothing above this knows which it is.
public protocol DeviceTransport: AnyObject, Sendable {
    /// For logs and a bug report's `about.json`: `ble`, or `usb:<bridge socket>`.
    var name: String { get }
    /// Why it can't look for the device at all, in plain words for the
    /// popover with what to do (`Bluetooth is off. …`), or nil. Read from
    /// any thread; the runtime looks once a second.
    var trouble: String? { get }
    /// `onLine` gets each complete line from the device, and `onConnection`
    /// each change of connection, both on the transport's own thread.
    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void)
    /// Sends one line (without its newline). Dropped when not connected:
    /// the next snapshot catches the device up.
    func send(_ line: String)
    /// Drops the connection or attempt in progress and looks for the
    /// device again at once (the settings screen's Reconnect).
    func reconnect()
    func stop()
}

extension DeviceTransport {
    public var trouble: String? { nil }
}

/// The device link (ARCHITECTURE.md §3.7): sends `state` on every change and
/// every 10 s, sends moments, answers `status` with a `state`, and hands
/// `input` on. Call everything on one queue; the transport may call back on
/// any thread, so the owner hops to that queue before calling `receive`.
public final class DeviceLink {
    /// A `state` goes out at least this often (PROTOCOL.md §3).
    public static let keepaliveMs: Int64 = 10_000

    public let transport: DeviceTransport?
    let log: (String) -> Void
    /// The newest snapshot, sent again on `status` and on reconnect.
    public private(set) var latest: StateSnapshot?
    var lastSent: StateSnapshot?
    /// Nil until the first `state` goes out.
    var lastSentAt: Int64?
    public private(set) var status: DeviceStatus?
    public private(set) var connected = false
    /// Called with every line sent and who sent it (debug mode's
    /// tracing); nil does nothing.
    public var onSend: ((String, Sender) -> Void)?

    /// Who asked for a line, passed through to `onSend` as it is: the link
    /// makes nothing of it. Every `state` is the rules'.
    public enum Sender: String, Sendable {
        case rule, brain
    }

    public init(transport: DeviceTransport?, log: @escaping (String) -> Void = { _ in }) {
        self.transport = transport
        self.log = log
    }

    /// A snapshot from the core. Sent only if something on it changed.
    public func update(_ snapshot: StateSnapshot, now: Int64) {
        latest = snapshot
        guard snapshot != lastSent else { return }
        sendState(snapshot, now: now)
    }

    /// Once a second: the 10 s keepalive sends the latest `state` again.
    public func tick(now: Int64) {
        guard let latest, lastSentAt.map({ now - $0 >= DeviceLink.keepaliveMs }) ?? true else { return }
        sendState(latest, now: now)
    }

    public func play(_ moment: DeviceMoment, by sender: Sender = .rule) {
        send(moment.jsonLine, by: sender)
    }

    /// A line from the device. Replies to `status` with the latest `state`
    /// and returns the message for the owner.
    @discardableResult
    public func receive(_ line: String, now: Int64) -> DeviceMessage {
        let message = DeviceMessage.decode(line)
        if case .status(let s) = message {
            if status != s {
                log("device: \(s.id) firmware \(s.fw)" + (s.voice.map { " voice \($0)" } ?? ""))
                if !s.hasTheVoice {
                    log("device: its card's voice is \(s.voice!), the app's \(Take.packVersion): Boop says nothing until they match (VOICE.md §8)")
                }
            }
            status = s
            if let latest { sendState(latest, now: now) }
        }
        return message
    }

    /// The transport connected or dropped. On connect the device gets the
    /// whole picture at once.
    public func connection(_ up: Bool, now: Int64) {
        guard up != connected else { return }
        connected = up
        log("device link: \(up ? "connected" : "disconnected") (\(transport?.name ?? "none"))")
        if up, let latest { sendState(latest, now: now) }
        if !up { status = nil }
    }

    func sendState(_ snapshot: StateSnapshot, now: Int64) {
        lastSent = snapshot
        lastSentAt = now
        send(snapshot.jsonLine, by: .rule)
    }

    func send(_ line: String, by sender: Sender) {
        onSend?(line, sender)
        transport?.send(line)
    }
}

/// `--link` values: `usb:<bridge socket>`, `ble` or `none`.
public enum LinkSetting: Equatable, Sendable {
    case usb(String)
    case bluetooth
    case none

    public init?(_ text: String) {
        if text.hasPrefix("usb:"), text.count > 4 {
            self = .usb(String(text.dropFirst(4)))
        } else if text == "ble" {
            self = .bluetooth
        } else if text == "none" {
            self = .none
        } else {
            return nil
        }
    }
}
