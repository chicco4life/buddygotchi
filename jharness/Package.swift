// swift-tools-version: 6.0
import PackageDescription

// JHarness: give anything a personality with Markdown and multiple choice
// (README.md). Foundation only, and nothing outside this folder: apps
// depend on it, never the other way round.
let package = Package(
    name: "jharness",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JHarness", targets: ["JHarness"]),
        .executable(name: "jharness-emit", targets: ["JHarnessEmit"]),
        .executable(name: "beacon", targets: ["BeaconDemo"]),
    ],
    targets: [
        // What apps link: events and the log, the harness, the brains,
        // `Choice`, steering and the socket in.
        .target(name: "JHarness"),
        // `jharness-emit`: sends one event to a harness's socket.
        .executableTarget(name: "JHarnessEmit", dependencies: ["JHarness"]),
        // The worked example, Beacon (SPEC.md §11), its steering folder read
        // from the source tree, and `beacon`, which runs it.
        .target(name: "Beacon", dependencies: ["JHarness"], path: "Examples/Beacon", exclude: ["steering"]),
        .executableTarget(name: "BeaconDemo", dependencies: ["Beacon", "JHarness"], path: "Examples/BeaconDemo"),
        .testTarget(name: "JHarnessTests", dependencies: ["JHarness", "Beacon"]),
    ]
)
