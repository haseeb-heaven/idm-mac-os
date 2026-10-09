// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MacDownloadManager", platforms: [.macOS("13.0")], products: [
    .library(name: "DownloadCore", targets: ["DownloadCore"]),
    .executable(name: "MacDownloadManager", targets: ["MacDownloadManager"]),
    .executable(name: "MacDownloadManagerHost", targets: ["MacDownloadManagerHost"])
], targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
    .target(name: "DownloadCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "MacDownloadManagerHost", dependencies: ["DownloadCore"]),
    .executableTarget(name: "MacDownloadManager", dependencies: ["DownloadCore"]),
    .executableTarget(name: "DownloadCoreChecks", dependencies: ["DownloadCore"], path: "Tests/DownloadCoreTests")
])
