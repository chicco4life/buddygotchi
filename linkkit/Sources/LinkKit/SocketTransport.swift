import Darwin
import Foundation

/// The device over USB, through a bridge process's Unix socket (SPEC.md
/// §8). The bridge owns the board's serial port and passes lines both ways,
/// so tools and the app can share it and the app never opens the port
/// itself. Reconnects every second while the bridge is away.
///
/// `send` runs on the caller's queue (the app's), so a write never waits
/// more than `sendTimeoutMs`, and a dropped link waits a second before
/// connecting again: a bridge that stops reading costs at most one
/// timed-out write a second, not a frozen app.
public final class SocketTransport: Transport, @unchecked Sendable {
    public static let sendTimeoutMs = 250
    public let path: String
    /// `usb:<path>` unless `init` is given another.
    public let name: String
    let lock = NSLock()
    var fd: Int32 = -1
    var running = false
    var thread: Thread?

    /// `path` is the bridge's socket, under 104 bytes.
    public init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? "usb:" + path
    }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { running = true }
        let thread = Thread { [weak self] in self?.loop(onLine: onLine, onConnection: onConnection) }
        thread.name = "linkkit.socket"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func send(_ line: String) {
        var data = Data(line.utf8)
        data.append(0x0A)
        lock.withLock {
            guard fd >= 0 else { return }
            let ok = data.withUnsafeBytes { raw -> Bool in
                var offset = 0
                while offset < raw.count {
                    // Each write waits at most sendTimeoutMs (SO_SNDTIMEO).
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n <= 0 { return false }
                    offset += n
                }
                return true
            }
            if !ok { shutdown(fd, SHUT_RDWR) }  // the reader sees it and reconnects
        }
    }

    /// The reader sees the socket close and connects to the bridge again.
    public func reconnect() {
        lock.withLock {
            if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        }
    }

    public func stop() {
        lock.withLock {
            running = false
            if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        }
    }

    func loop(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while lock.withLock({ running }) {
            guard let socket = connectOnce() else {
                usleep(1_000_000)
                continue
            }
            lock.withLock { fd = socket }
            onConnection(true)
            var framer = LineFramer()
            while true {
                let n = read(socket, &buffer, buffer.count)
                if n <= 0 { break }
                for line in framer.push(buffer[0..<n]) { onLine(line) }
            }
            lock.withLock {
                close(fd)
                fd = -1
            }
            onConnection(false)
            usleep(1_000_000)
        }
    }

    func connectOnce() -> Int32? {
        guard var address = UnixSocket.address(path) else { return nil }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: 0, tv_usec: Int32(Self.sendTimeoutMs * 1000))
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            close(socket)
            return nil
        }
        return socket
    }
}

/// A Unix socket's address.
enum UnixSocket {
    /// `path` as a `sockaddr_un`, or nil when it's empty or too long: the
    /// address has room for 103 bytes and the closing zero.
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
