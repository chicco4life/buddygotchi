import Darwin
import Foundation

/// The app's hook socket, as seen from the client side.
public enum HookSocket {
    /// `~/Library/Application Support/Boop/boop.sock`, or `BOOP_SOCKET`.
    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let path = environment["BOOP_SOCKET"], !path.isEmpty { return path }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return home + "/Library/Application Support/Boop/boop.sock"
    }

    /// Writes `data` to the socket and returns whether it was sent. Gives up
    /// if the socket is missing or doesn't accept within `timeoutMs`; never
    /// blocks longer than that.
    @discardableResult
    public static func send(_ data: Data, to path: String, timeoutMs: Int32 = 50) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        guard var address = unixAddress(path) else { return false }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN, wait(fd, for: Int16(POLLOUT), ms: timeoutMs) else {
                return false
            }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
            guard error == 0 else { return false }
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
        var offset = 0
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                    continue
                }
                let now = DispatchTime.now().uptimeNanoseconds
                guard n < 0, errno == EAGAIN, now < deadline,
                      wait(fd, for: Int16(POLLOUT), ms: Int32((deadline - now) / 1_000_000) + 1) else { return false }
            }
            return true
        }
    }

    static func wait(_ fd: Int32, for events: Int16, ms: Int32) -> Bool {
        var entry = pollfd(fd: fd, events: events, revents: 0)
        return poll(&entry, 1, ms) == 1 && entry.revents & events != 0
    }

    /// A `sockaddr_un` for `path`, or nil if the path doesn't fit (104 bytes).
    public static func unixAddress(_ path: String) -> sockaddr_un? {
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
