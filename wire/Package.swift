// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BoopWire", platforms: [.macOS(.v14)], products: [
    .library(name: "BoopSQLite", targets: ["BoopSQLite"])
], targets: [
    .systemLibrary(name: "CSQLite", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite"])]),
    .target(name: "BoopSQLite", dependencies: ["CSQLite"])
])
