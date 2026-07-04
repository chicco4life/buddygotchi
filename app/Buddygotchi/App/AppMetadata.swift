import Foundation

enum AppMetadata {
    static var displayVersion: String {
        let version = rawVersion
        let build = rawBuild
        if let build, build != version {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }

    static var rawVersion: String {
        value(for: "CFBundleShortVersionString") ?? "0.3.0"
    }

    static var rawBuild: String? {
        value(for: "CFBundleVersion")
    }

    static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    static var supportURL: URL {
        URL(string: "https://buddygotchi.github.io/help/")!
    }

    static var flashURL: URL {
        URL(string: "https://buddygotchi.github.io/flash/")!
    }

    static var updateFeedURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
    }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }
}
