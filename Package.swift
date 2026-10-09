// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IDMMac", platforms: [.macOS("13.0")], products: [
    .library(name: "IDMCore", targets: ["IDMCore"]),
    .executable(name: "IDMMac", targets: ["IDMMac"]),
    .executable(name: "IDMBrowserHost", targets: ["IDMBrowserHost"])
], targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
    .target(name: "IDMCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "IDMBrowserHost", dependencies: ["IDMCore"]),
    .executableTarget(name: "IDMMac", dependencies: ["IDMCore"]),
    .executableTarget(name: "IDMCoreChecks", dependencies: ["IDMCore"], path: "Tests/IDMCoreTests")
])
