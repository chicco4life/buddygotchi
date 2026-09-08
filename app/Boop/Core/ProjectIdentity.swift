import Foundation
import CryptoKit

func cwdLabel(_ cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    return (cwd as NSString).lastPathComponent
}

func stableHashCwd(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "unknown" }
    let digest = SHA256.hash(data: Data(cwd.utf8))
    return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

