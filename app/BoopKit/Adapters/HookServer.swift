import Darwin
import Foundation
import HookWire

/// The app side of the hook socket: accepts `boop-hook` connections and hands
/// each line on. It never writes anything back, so a hook can't be answered.
public final class HookServer: @unchecked Sendable {
    public let path: String
    private let onLine: @Sendable (HookLine, Int64) -> Void
    private let onOther: (@Sendable (Data) -> Void)?
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var thread: Thread?

    /// `onLine` gets each line with the time it arrived, in milliseconds, on
    /// the server's own thread. `onOther` gets lines that aren't hook lines
    /// (headless mode's `boopdev talk`); without it they're dropped.
    public init(path: String, onLine: @escaping @Sendable (HookLine, Int64) -> Void,
                onOther: (@Sendable (Data) -> Void)? = nil) {
        self.path = path
        self.onLine = onLine
        self.onOther = onOther
    }

    public enum StartError: Error { case pathTooLong, socket(Int32), bind(Int32), listen(Int32) }

    public func start() throws {
        guard var address = HookSocket.unixAddress(path) else { throw StartError.pathTooLong }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socket(errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw StartError.bind(error)
        }
        chmod(path, 0o600)
        guard listen(fd, 128) == 0 else {
            let error = errno
            close(fd)
            throw StartError.listen(error)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "boop.hook-server"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock { () -> Int32 in
            let fd = listener
            listener = -1
            return fd
        }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(path)
    }

    deinit { stop() }

    /// Runs until `stop()`. Any other failed `accept` (out of file
    /// descriptors, an aborted connection) is waited out, so hooks keep
    /// arriving once it passes.
    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                let error = errno
                if lock.withLock({ listener }) != fd { return }  // closed by stop()
                if error != EINTR { usleep(10_000) }
                continue
            }
            handle(client)
        }
    }

    /// A hook writes one short line and closes. Read it with a short timeout
    /// so a stuck client can't hold up the next one.
    private func handle(_ client: Int32) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 64 * 1024 {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        let received = Int64(Date().timeIntervalSince1970 * 1000)
        for part in data.split(separator: 0x0A) where !part.isEmpty {
            if let line = HookLine.decode(Data(part)) {
                onLine(line, received)
            } else {
                onOther?(Data(part))
            }
        }
    }
}
