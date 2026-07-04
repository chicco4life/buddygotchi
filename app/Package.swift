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
    .testTarget(
        name: "BuddygotchiTests",
        dependencies: ["Buddygotchi"] + (useXCTestShim ? ["XCTest"] : []),
        path: "Tests"
    ),
]

if useXCTestShim {
    packageTargets.append(
        .target(
            name: "XCTest",
            path: "TestSupport/XCTestShim"
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
