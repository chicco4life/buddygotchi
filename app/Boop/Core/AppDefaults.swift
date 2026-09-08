import Foundation

/// The app's preferences. Headless runs (e2e, doctor, packaged-app smoke)
/// get a scratch suite so tests never read or write the owner's real
/// settings; `tools/headless.sh` clears the suite on start and stop.
enum AppDefaults {
    static let headlessSuite = "com.boopcomputer.boop.headless"
    // UserDefaults is thread-safe in practice; the compiler cannot see that.
    nonisolated(unsafe) static let shared: UserDefaults = {
        let headless = CommandLine.arguments.contains("--headless") || ProcessInfo.processInfo.environment["BOOP_HEADLESS"] == "1"
        return headless ? UserDefaults(suiteName: headlessSuite)! : .standard
    }()
}
