// swift-tools-version: 6.0
import PackageDescription
import Foundation
#if os(Linux)
let useShim = false
#else
let developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let useShim = !FileManager.default.fileExists(atPath: developer + "/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule") && !FileManager.default.fileExists(atPath: developer + "/Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule")
#endif
let testDependencies: [Target.Dependency] = ["LeaderboardCore", .product(name: "HummingbirdTesting", package: "hummingbird")]
let testingTargets: [Target] = useShim ? [
    .target(name: "XCTest", path: "TestSupport/XCTestShim"),
    .executableTarget(name: "LeaderboardTests", dependencies: testDependencies + ["XCTest"], path: "Tests/LeaderboardTests", swiftSettings: [.define("BOOP_SHIM_RUNNER")])
] : [.testTarget(name: "LeaderboardTests", dependencies: testDependencies, path: "Tests/LeaderboardTests")]

let package = Package(name: "Leaderboard", platforms: [.macOS(.v14)], products: [.executable(name: "leaderboard", targets: ["Leaderboard"])], dependencies: [
    .package(path: "../wire"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
], targets: [
    .target(name: "LeaderboardCore", dependencies: [.product(name: "LeaderboardWire", package: "wire"), .product(name: "BoopSQLite", package: "wire"), .product(name: "Hummingbird", package: "hummingbird")], swiftSettings: useShim ? [.unsafeFlags(["-enable-testing"])] : []),
    .executableTarget(name: "Leaderboard", dependencies: ["LeaderboardCore"])
] + testingTargets)
