// swift-tools-version: 6.0
import PackageDescription

// LinkKit: a Mac app talking to a small device with a screen, over
// Bluetooth or a USB bridge (SPEC.md). Foundation and CoreBluetooth only,
// and nothing outside this folder: apps depend on it, never the other way
// round. The device's half, in C++, is in device/, which SwiftPM ignores.
// JHarnessLink, the optional glue to JHarness (../jharness), is the one
// target that looks outside it; LinkKit itself never imports JHarness.
// SwiftPM resolves the dependency for either product, so ../jharness must
// be beside this folder even for an app that takes LinkKit alone.
let package = Package(
    name: "linkkit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LinkKit", targets: ["LinkKit"]),
        .library(name: "JHarnessLink", targets: ["JHarnessLink"]),
    ],
    dependencies: [.package(path: "../jharness")],
    targets: [
        // The four messages, the transports and the host's side of the
        // protocol (`Link`).
        .target(name: "LinkKit", linkerSettings: [.linkedFramework("CoreBluetooth")]),
        // A device in a JHarness app: a `do` that finishes a `Pending`, the
        // device's events in the log, and `Play`, an output of its names.
        .target(name: "JHarnessLink", dependencies: ["LinkKit", .product(name: "JHarness", package: "jharness")]),
        .testTarget(name: "LinkKitTests", dependencies: ["LinkKit"]),
        .testTarget(name: "JHarnessLinkTests",
                    dependencies: ["JHarnessLink", "LinkKit", .product(name: "JHarness", package: "jharness")]),
    ]
)
