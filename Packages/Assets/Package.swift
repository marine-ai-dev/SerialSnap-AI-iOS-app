// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Assets",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Assets", targets: ["Assets"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Sync"),
        .package(path: "../Parsing"),
    ],
    targets: [
        .target(name: "Assets", dependencies: ["Core", "Sync", "Parsing"]),
        .testTarget(name: "AssetsTests", dependencies: ["Assets"])
    ]
)
