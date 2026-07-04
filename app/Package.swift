// swift-tools-version: 6.0
import Foundation
import PackageDescription

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let hasAppleXCTest = FileManager.default.fileExists(
    atPath: "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
) || FileManager.default.fileExists(
    atPath: "\(developerDir)/Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
)
let useXCTestShim = ProcessInfo.processInfo.environment["BUDDYGOTCHI_USE_XCTEST_SHIM"] == "1" || !hasAppleXCTest

var packageTargets: [Target] = [
    .executableTarget(
        name: "Buddygotchi",
        dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
        ],
        path: "Buddygotchi",
        exclude: [
            "Resources/Info.plist",
        ],
        // Without full Xcode the tests run as an executable that `@testable
        // import`s this target, so it must be built with testability enabled.
        swiftSettings: useXCTestShim ? [.unsafeFlags(["-enable-testing"])] : [],
        linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate",
                          "-Xlinker", "__TEXT",
                          "-Xlinker", "__info_plist",
                          "-Xlinker", "Buddygotchi/Resources/Info.plist"]),
        ]
    ),
    .executableTarget(
        name: "BuddygotchiSignal",
        path: "BuddygotchiSignal"
    ),
]

if useXCTestShim {
    // No real XCTest here: SwiftPM's `swift test` would build these tests and
    // run NONE of them (a false green). Instead build the Tests directory as an
    // executable driven by the generated GeneratedTestRunner.swift, run via
    // `make test` → `swift run BuddygotchiTests`. See tools/gen-test-runner.py.
    packageTargets.append(
        .executableTarget(
            name: "BuddygotchiTests",
            dependencies: ["Buddygotchi", "XCTest"],
            path: "Tests",
            swiftSettings: [.define("BUDDYGOTCHI_SHIM_RUNNER")]
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
            name: "BuddygotchiTests",
            dependencies: ["Buddygotchi"],
            path: "Tests"
        )
    )
}

let package = Package(
    name: "Buddygotchi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Buddygotchi", targets: ["Buddygotchi"]),
        .executable(name: "BuddygotchiSignal", targets: ["BuddygotchiSignal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: packageTargets
)
