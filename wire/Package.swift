// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BoopWire", platforms: [.macOS(.v14)], products: [
    .library(name: "LeaderboardWire", targets: ["LeaderboardWire"]),
    .library(name: "BoopSQLite", targets: ["BoopSQLite"])
], targets: [
    .systemLibrary(name: "CSQLite", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite"])]),
    .systemLibrary(name: "CSignature", pkgConfig: "openssl", providers: [.apt(["libssl-dev"]), .brew(["openssl"])]),
    .target(name: "LeaderboardWire", dependencies: [.target(name: "CSignature", condition: .when(platforms: [.linux]))]),
    .target(name: "BoopSQLite", dependencies: ["CSQLite"])
])
