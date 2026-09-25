// swift-tools-version: 6.2
import Foundation
import PackageDescription

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let hasAppleXCTest = FileManager.default.fileExists(
    atPath: "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
) || FileManager.default.fileExists(
    atPath: "\(developerDir)/Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
)
let useXCTestShim = ProcessInfo.processInfo.environment["BOOP_USE_XCTEST_SHIM"] == "1" || !hasAppleXCTest

var packageTargets: [Target] = [
    // Everything that isn't the app shell: Adapters, Core, Harness, Brains,
    // Actions, Voice, Memory, DeviceLink, Talk (plan/ARCHITECTURE.md §3).
    .target(
        name: "BoopKit",
        path: "BoopKit",
        // Without full Xcode the tests run as an executable that `@testable
        // import`s this target, so it must be built with testability enabled.
        swiftSettings: useXCTestShim ? [.unsafeFlags(["-enable-testing"])] : []
    ),
    // The menu-bar app; `Boop --headless` runs it without UI or Bluetooth.
    .executableTarget(
        name: "Boop",
        dependencies: ["BoopKit"],
        path: "Boop"
    ),
    // The hook client agents call. Never prints, always exits 0.
    .executableTarget(
        name: "BoopHook",
        path: "BoopHook"
    ),
    // Developer CLI: replay, talk, brain runs, memory dump.
    .executableTarget(
        name: "BoopDev",
        dependencies: ["BoopKit"],
        path: "BoopDev"
    ),
]

if useXCTestShim {
    // No real XCTest here: SwiftPM's `swift test` would build these tests and
    // run NONE of them (a false green). Instead build the Tests directory as an
    // executable driven by the generated GeneratedTestRunner.swift, run via
    // `make test` → `swift run BoopTests`. See tools/gen-test-runner.py.
    packageTargets.append(
        .executableTarget(
            name: "BoopTests",
            dependencies: ["BoopKit", "XCTest"],
            path: "Tests",
            exclude: ["Fixtures"],
            swiftSettings: [.define("BOOP_SHIM_RUNNER")]
        )
    )
    packageTargets.append(
        .target(
            name: "XCTest",
            path: "TestSupport/XCTestShim"
        )
    )
} else {
    packageTargets.append(
        .testTarget(
            name: "BoopTests",
            dependencies: ["BoopKit"],
            path: "Tests",
            exclude: ["Fixtures"]
        )
    )
}

let package = Package(
    name: "Boop",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BoopKit", targets: ["BoopKit"]),
        .executable(name: "Boop", targets: ["Boop"]),
        .executable(name: "boop-hook", targets: ["BoopHook"]),
        .executable(name: "boopdev", targets: ["BoopDev"]),
    ],
    targets: packageTargets
)
