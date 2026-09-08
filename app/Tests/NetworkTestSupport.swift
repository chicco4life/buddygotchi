import Darwin
import XCTest

/// A restricted test host can prohibit sockets entirely. Skip only that
/// environmental denial; server startup and protocol failures still fail tests.
func requireLocalNetworking() throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0 && errno == EPERM { try XCTSkipUnless(false, "Sandbox prohibits localhost sockets") }
    guard fd >= 0 else { return }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if result < 0 && errno == EPERM { try XCTSkipUnless(false, "Sandbox prohibits localhost sockets") }
}
