// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Sync", targets: ["Sync"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Sync", dependencies: ["Core"]),
        .testTarget(name: "SyncTests", dependencies: ["Sync"])
    ]
)
