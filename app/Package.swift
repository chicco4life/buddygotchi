// swift-tools-version: 6.0
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
    .target(
        name: "BoopCore",
        dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
        ],
        path: "Boop",
        exclude: [
            "Resources/Info.plist",
        ],
        resources: [
            .copy("Resources/runners.json"),
            .copy("Resources/Fonts"),
            .copy("Resources/Sounds"),
        ],
        // Without full Xcode the tests run as an executable that `@testable
        // import`s this target, so it must be built with testability enabled.
        swiftSettings: useXCTestShim ? [.unsafeFlags(["-enable-testing"])] : []
    ),
    .executableTarget(
        name: "Boop",
        dependencies: ["BoopCore"],
        path: "BoopLauncher",
        linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate",
                          "-Xlinker", "__TEXT",
                          "-Xlinker", "__info_plist",
                          "-Xlinker", "Boop/Resources/Info.plist"]),
        ]
    ),
    .executableTarget(
        name: "BoopSignal",
        path: "BoopSignal"
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
            dependencies: ["BoopCore", "XCTest", .product(name: "HummingbirdTesting", package: "hummingbird")],
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
            dependencies: ["BoopCore", .product(name: "HummingbirdTesting", package: "hummingbird")],
            path: "Tests",
            exclude: ["Fixtures"]
        )
    )
}

let package = Package(
    name: "Boop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Boop", targets: ["Boop"]),
        .executable(name: "BoopSignal", targets: ["BoopSignal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: packageTargets
)
