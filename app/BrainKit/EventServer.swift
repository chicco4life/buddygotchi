#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// A way in for other processes (kit/BRAIN-KIT.md §3.3): a Unix socket that
/// takes one JSON event per line, `{"source":…,"kind":…,"data":{…}}`
/// (`line` and `at` optional), and hands each on. It never writes back.
/// `kit-emit` sends to it from a shell.
public final class EventServer: @unchecked Sendable {
    public let path: String
    private let onEvent: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var listener: Int32 = -1

    /// `onEvent` gets each event on the server's own thread; hop to the
    /// kit's queue to emit it.
    public init(path: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    public enum Failure: Error { case pathTooLong, socket(Int32), bind(Int32), listen(Int32), send }

    public func start() throws {
        guard var address = EventServer.address(path) else { throw Failure.pathTooLong }
        unlink(path)
        #if canImport(Darwin)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw Failure.socket(errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw Failure.bind(error)
        }
        chmod(path, 0o600)
        guard listen(fd, 64) == 0 else {
            let error = errno
            close(fd)
            throw Failure.listen(error)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "brainkit.event-server"
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock { () -> Int32 in
            defer { listener = -1 }
            return listener
        }
        guard fd >= 0 else { return }
        shutdown(fd, Int32(SHUT_RDWR))
        close(fd)
        unlink(path)
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if lock.withLock({ listener }) != fd { return }  // stopped
                usleep(10_000)
                continue
            }
            autoreleasepool { handle(client) }
        }
    }

    /// Reads a connection's lines, with a short timeout so a stuck client
    /// can't hold up the next.
    private func handle(_ client: Int32) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 1 << 20 {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        for part in data.split(separator: 0x0A) where !part.isEmpty {
            if let e = EventServer.decode(Data(part)) { onEvent(e) }
        }
    }

    /// An event from a line: `source` and `kind` needed, `data`, `line` and
    /// `at` optional. Its `seq` is the log's to give.
    public static func decode(_ line: Data) -> Event? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let source = o["source"] as? String, let kind = o["kind"] as? String, !source.isEmpty, !kind.isEmpty
        else { return nil }
        let data = (o["data"] as? [String: Any] ?? [:]).mapValues { JSONValue(foundation: $0) }
        return Event(at: (o["at"] as? NSNumber)?.int64Value ?? 0, source: source, kind: kind, line: o["line"] as? String,
                     data: data)
    }

    /// An event from a command line's words, `SOURCE KIND [key=value ...]`
    /// (`kit-emit`): a value that reads as a whole number is one, `true` and
    /// `false` are yes and no, the rest strings. Nil without a source and a
    /// kind, or a word that isn't `key=value`.
    public static func event(from arguments: [String]) -> Event? {
        guard arguments.count >= 2 else { return nil }
        var data: [String: JSONValue] = [:]
        for word in arguments.dropFirst(2) {
            guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return nil }
            let key = String(word[..<eq]), value = String(word[word.index(after: eq)...])
            data[key] = Int64(value).map(JSONValue.int) ?? (value == "true" ? .bool(true) : value == "false" ? .bool(false) : .string(value))
        }
        return Event(source: arguments[0], kind: arguments[1], data: data)
    }

    /// The line for `e`, as `send` writes it.
    public static func encode(_ e: Event) -> String {
        var o: [String: Any] = ["source": e.source, "kind": e.kind, "data": e.data.mapValues(\.foundation)]
        if let line = e.line { o["line"] = line }
        if e.at != 0 { o["at"] = NSNumber(value: e.at) }
        return JSONLine.encode(o)
    }

    /// Sends one event to the socket at `path`.
    public static func send(_ e: Event, to path: String) throws {
        guard var address = address(path) else { throw Failure.pathTooLong }
        #if canImport(Darwin)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw Failure.socket(errno) }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure.send }
        let bytes = Array((encode(e) + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { throw Failure.send }
            offset += n
        }
    }

    /// A `sockaddr_un` for `path`, or nil if it doesn't fit.
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }
}
