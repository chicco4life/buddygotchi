import Foundation

// Manifest fetched from a static URL. We keep the parsing tolerant —
// the manifest can grow new fields without breaking older clients.
struct FirmwareRelease: Sendable, Equatable {
    let version: String          // "1.3.0"
    let downloadURL: URL         // direct link to the .bin
    let sha256: String           // hex, lowercase
    let releaseNotes: String     // markdown
    let publishedAt: Date?       // optional, surfaced if present
}

// Errors are exposed verbatim to the UI's failure state so users have
// something concrete to copy/paste into a bug report.
enum FirmwareReleaseError: LocalizedError {
    case manifestUnreachable(underlying: Error)
    case manifestMalformed(reason: String)
    case downloadFailed(underlying: Error)
    case hashMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .manifestUnreachable(let e): return "Couldn't fetch the firmware manifest: \(e.localizedDescription)"
        case .manifestMalformed(let r):   return "Firmware manifest is malformed: \(r)"
        case .downloadFailed(let e):      return "Couldn't download the firmware binary: \(e.localizedDescription)"
        case .hashMismatch(let exp, let act): return "Downloaded firmware hash mismatch.\nExpected: \(exp)\nActual:   \(act)"
        }
    }
}

@MainActor
final class FirmwareReleaseService {
    // The manifest URL is the single tunable for ops. Override per-build by
    // setting BUDDY_FIRMWARE_MANIFEST_URL in Info.plist or the environment;
    // falls back to the GitHub Pages location.
    private static let defaultManifestURL = URL(string: "https://adoptaboop.com/firmware/manifest.json")!
    private static let cacheKey = DefaultsKey.firmwareManifestCache
    private static let cacheTTL: TimeInterval = 60 * 60   // 1 hour

    private let session: URLSession
    private let manifestURL: URL

    init(session: URLSession = .shared, manifestURL: URL? = nil) {
        self.session = session
        self.manifestURL = manifestURL ?? Self.resolveManifestURL()
    }

    func latestRelease(forceRefresh: Bool = false) async throws -> FirmwareRelease {
        if !forceRefresh, let cached = readCache(), cached.fetchedAt.timeIntervalSinceNow > -Self.cacheTTL {
            return cached.release
        }
        let release = try await fetchManifest()
        writeCache(release)
        return release
    }

    func downloadBinary(_ release: FirmwareRelease) async throws -> Data {
        let data: Data
        do {
            (data, _) = try await session.data(from: release.downloadURL)
        } catch {
            throw FirmwareReleaseError.downloadFailed(underlying: error)
        }
        let actual = OTAProtocol.sha256Hex(data)
        guard actual.lowercased() == release.sha256.lowercased() else {
            throw FirmwareReleaseError.hashMismatch(expected: release.sha256, actual: actual)
        }
        return data
    }

    // MARK: - Private

    private func fetchManifest() async throws -> FirmwareRelease {
        let payload: Data
        do {
            (payload, _) = try await session.data(from: manifestURL)
        } catch {
            throw FirmwareReleaseError.manifestUnreachable(underlying: error)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw FirmwareReleaseError.manifestMalformed(reason: "not a JSON object")
        }
        guard let version = obj["version"] as? String,
              let urlStr = obj["url"] as? String,
              let url = URL(string: urlStr),
              let sha = obj["sha256"] as? String
        else {
            throw FirmwareReleaseError.manifestMalformed(reason: "missing version/url/sha256")
        }
        let notes = obj["notes"] as? String ?? ""
        let published = (obj["published_at"] as? String).flatMap(ISO8601DateFormatter().date(from:))
        return FirmwareRelease(
            version: version,
            downloadURL: url,
            sha256: sha,
            releaseNotes: notes,
            publishedAt: published
        )
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let version: String
        let url: URL
        let sha256: String
        let notes: String
        let publishedAt: Date?
        let fetchedAt: Date

        var release: FirmwareRelease {
            FirmwareRelease(version: version, downloadURL: url, sha256: sha256, releaseNotes: notes, publishedAt: publishedAt)
        }
    }

    private func readCache() -> CacheEntry? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func writeCache(_ release: FirmwareRelease) {
        let entry = CacheEntry(
            version: release.version,
            url: release.downloadURL,
            sha256: release.sha256,
            notes: release.releaseNotes,
            publishedAt: release.publishedAt,
            fetchedAt: Date()
        )
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private static func resolveManifestURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["BUDDY_FIRMWARE_MANIFEST_URL"],
           let url = URL(string: env) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "BUDDY_FIRMWARE_MANIFEST_URL") as? String,
           let url = URL(string: plist) {
            return url
        }
        return defaultManifestURL
    }
}

// Semver compare that treats missing components as 0. Returns true iff
// `a` is strictly newer than `b`. Tolerates "v" prefixes and trailing
// pre-release tags by stripping anything after the first non-digit/dot.
func firmwareVersionIsNewer(_ a: String, than b: String) -> Bool {
    let lhs = parseSemver(a)
    let rhs = parseSemver(b)
    let count = max(lhs.count, rhs.count)
    for i in 0..<count {
        let l = i < lhs.count ? lhs[i] : 0
        let r = i < rhs.count ? rhs[i] : 0
        if l != r { return l > r }
    }
    return false
}

private func parseSemver(_ s: String) -> [Int] {
    var trimmed = s
    if trimmed.hasPrefix("v") { trimmed.removeFirst() }
    let core = trimmed.prefix { $0.isNumber || $0 == "." }
    return core.split(separator: ".").compactMap { Int($0) }
}
