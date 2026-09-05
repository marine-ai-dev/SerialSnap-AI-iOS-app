// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Settings", targets: ["Settings"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Auth"),
        .package(path: "../Workspace"),
    ],
    targets: [
        .target(name: "Settings", dependencies: ["Core", "Auth", "Workspace"])
    ]
)
