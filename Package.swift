// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The package sits at the repo root because SwiftPM won't take a target
// outside its root, and the app's targets live in both app/ (what ships)
// and internal/ (what doesn't). Production targets (HookWire, BoopKit, Boop,
// BoopHook) never depend on internal ones (internal/README.md).

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let hasAppleXCTest = FileManager.default.fileExists(
    atPath: "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
) || FileManager.default.fileExists(
    atPath: "\(developerDir)/Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule"
)
// internal/app/tools/test.py's uses_shim() makes the same test; change the two together.
let useXCTestShim = ProcessInfo.processInfo.environment["BOOP_USE_XCTEST_SHIM"] == "1" || !hasAppleXCTest

// Without full Xcode the tests run as an executable that `@testable
// import`s the libraries, so they must be built with testability enabled.
let testable: [SwiftSetting] = useXCTestShim ? [.unsafeFlags(["-enable-testing"])] : []

/// Everything in the repo except `kept` and the directories leading to them,
/// for a target whose path is the repo root: SwiftPM warns about each file
/// under a target's path that no rule handles. Hidden entries (.git,
/// .build) are left out, as SwiftPM skips them itself.
func excludingAllBut(_ kept: [String]) -> [String] {
    var parents: Set<String> = [""]
    for path in kept {
        var parent = ""
        for part in path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(part) : parent + "/" + part
            parents.insert(parent)
        }
    }
    return parents.sorted().flatMap { parent -> [String] in
        let dir = parent.isEmpty ? Context.packageDirectory : Context.packageDirectory + "/" + parent
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return entries.filter { !$0.hasPrefix(".") }.sorted().compactMap { entry in
            let path = parent.isEmpty ? entry : parent + "/" + entry
            return kept.contains(path) || parents.contains(path) ? nil : path
        }
    }
}

var packageTargets: [Target] = [
    // What boop-hook and the app share: the hook line, topic tags and the
    // socket. Foundation only, so the hook client stays small and fast.
    .target(
        name: "HookWire",
        path: "app/HookWire",
        swiftSettings: testable
    ),
    // Everything that isn't the app shell: Adapters, Core, Harness, Brains,
    // Actions, Voice, Memory, DeviceLink, the hook installer (Install) and
    // the Runtime that wires them together (App) (plan/ARCHITECTURE.md §3).
    .target(
        name: "BoopKit",
        dependencies: ["HookWire"],
        path: "app/BoopKit",
        swiftSettings: testable
    ),
    // The menu-bar app. `Boop --headless` runs it without UI or Bluetooth
    // and `Boop --snapshots` draws its panes; both ship in the binary, but
    // their sources are in internal/app/Boop.
    // Push-to-talk's mic lives in the app, in app/Boop/Talk.swift.
    // Info.plist is linked into the binary so macOS finds the Bluetooth,
    // microphone and speech usage descriptions without an app bundle.
    .executableTarget(
        name: "Boop",
        dependencies: ["BoopKit"],
        path: ".",
        exclude: excludingAllBut(["app/Boop", "internal/app/Boop"])
            + ["app/Boop/Info.plist", "app/Boop/Resources"],
        sources: ["app/Boop", "internal/app/Boop"],
        resources: [.copy("app/Boop/Resources/steering")],
        linkerSettings: [.unsafeFlags([
            "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
            "-Xlinker", Context.packageDirectory + "/app/Boop/Info.plist",
        ])]
    ),
    // The hook client agents call. Never prints, always exits 0.
    .executableTarget(
        name: "BoopHook",
        dependencies: ["HookWire"],
        path: "app/BoopHook"
    ),

    // Internal from here on: none of it ships.

    // What boopdev and the tests share: the harness evals (Eval) and hook
    // replay.
    .target(
        name: "BoopDevKit",
        dependencies: ["BoopKit", "HookWire"],
        path: "internal/app/BoopDevKit",
        swiftSettings: testable
    ),
    // Developer CLI: the evals, reading debug logs, replay, voice lines
    // and the hook installer (hooks).
    .executableTarget(
        name: "BoopDev",
        dependencies: ["BoopKit", "HookWire", "BoopDevKit"],
        path: "internal/app/BoopDev"
    ),
]

if useXCTestShim {
    // No real XCTest here: SwiftPM's `swift test` would build these tests and
    // run NONE of them (a false green). Instead build the Tests directory as an
    // executable driven by the generated GeneratedTestRunner.swift, run via
    // `make -C internal test`. See internal/app/tools/gen-test-runner.py.
    packageTargets.append(
        .executableTarget(
            name: "BoopTests",
            dependencies: ["BoopKit", "HookWire", "BoopDevKit", "XCTest"],
            path: "internal/app/Tests",
            exclude: ["Fixtures"],
            swiftSettings: [.define("BOOP_SHIM_RUNNER")]
        )
    )
    packageTargets.append(
        .target(
            name: "XCTest",
            path: "internal/app/TestSupport/XCTestShim"
        )
    )
} else {
    packageTargets.append(
        .testTarget(
            name: "BoopTests",
            dependencies: ["BoopKit", "HookWire", "BoopDevKit"],
            path: "internal/app/Tests",
            exclude: ["Fixtures"]
        )
    )
}

let package = Package(
    name: "Boop",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Boop", targets: ["Boop"]),
        .executable(name: "boop-hook", targets: ["BoopHook"]),
        .executable(name: "boopdev", targets: ["BoopDev"]),
    ],
    targets: packageTargets
)
