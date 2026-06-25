// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Buddygotchi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Buddygotchi", targets: ["Buddygotchi"]),
        .executable(name: "BuddygotchiHook", targets: ["BuddygotchiHook"]),
        .executable(name: "BuddygotchiSignal", targets: ["BuddygotchiSignal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Buddygotchi",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Buddygotchi",
            exclude: [
                "Resources/Info.plist",
                "Resources/Buddygotchi.entitlements",
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Buddygotchi/Resources/Info.plist"]),
            ]
        ),
        .executableTarget(
            name: "BuddygotchiHook",
            path: "BuddygotchiHook"
        ),
        .executableTarget(
            name: "BuddygotchiSignal",
            path: "BuddygotchiSignal"
        ),
        .testTarget(
            name: "BuddygotchiTests",
            dependencies: ["Buddygotchi"],
            path: "Tests"
        ),
    ]
)
