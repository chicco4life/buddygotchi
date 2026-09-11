import Foundation
import XCTest
@testable import BoopCore

private final class ReleaseHTTPStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: (Int, Data)] = [:]
    static func set(_ url: URL, status: Int, data: Data) { lock.withLock { replies[url.absoluteString] = (status, data) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let reply = Self.lock.withLock { Self.replies[url.absoluteString] } ?? (404, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class FirmwareReleaseServiceTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseHTTPStub.self]
        return URLSession(configuration: config)
    }
    private func manifest(version: String) -> Data {
        Data("{\"version\":\"\(version)\",\"url\":\"https://example.invalid/firmware.bin\",\"sha256\":\"fixture\"}".utf8)
    }
    func testHTTPFailureCannotMasqueradeAsManifestOrBinary() async throws {
        let url = URL(string: "https://example.invalid/\(UUID().uuidString)")!
        let network = session(); defer { network.invalidateAndCancel() }
        let service = FirmwareReleaseService(session: network, manifestURL: url)
        ReleaseHTTPStub.set(url, status: 404, data: manifest(version: "999.0.0"))
        do { _ = try await service.latestRelease(forceRefresh: true); XCTFail("Accepted HTTP 404 manifest") }
        catch { XCTAssertTrue(error.localizedDescription.contains("HTTP 404")) }
        let bytes = Data([1, 2, 3])
        ReleaseHTTPStub.set(url, status: 503, data: bytes)
        let release = FirmwareRelease(version: "1", downloadURL: url, sha256: OTAProtocol.sha256Hex(bytes), releaseNotes: "", publishedAt: nil)
        do { _ = try await service.downloadBinary(release); XCTFail("Accepted HTTP 503 binary despite matching hash") }
        catch { XCTAssertTrue(error.localizedDescription.contains("HTTP 503")) }
    }
    func testManifestCacheIsScopedToItsSourceURL() async throws {
        let previous = AppDefaults.shared.object(forKey: DefaultsKey.firmwareManifestCache)
        defer {
            if let previous { AppDefaults.shared.set(previous, forKey: DefaultsKey.firmwareManifestCache) }
            else { AppDefaults.shared.removeObject(forKey: DefaultsKey.firmwareManifestCache) }
        }
        let a = URL(string: "https://example.invalid/a/\(UUID().uuidString)")!
        let b = URL(string: "https://example.invalid/b/\(UUID().uuidString)")!
        let network = session(); defer { network.invalidateAndCancel() }
        ReleaseHTTPStub.set(a, status: 200, data: manifest(version: "1.0.0"))
        ReleaseHTTPStub.set(b, status: 200, data: manifest(version: "2.0.0"))
        let first = try await FirmwareReleaseService(session: network, manifestURL: a).latestRelease(forceRefresh: true)
        let second = try await FirmwareReleaseService(session: network, manifestURL: b).latestRelease(forceRefresh: false)
        XCTAssertEqual(first.version, "1.0.0")
        XCTAssertEqual(second.version, "2.0.0")
    }
}
