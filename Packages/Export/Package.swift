// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Export",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Export", targets: ["Export"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Export", dependencies: ["Core"]),
        .testTarget(name: "ExportTests", dependencies: ["Export"])
    ]
)
