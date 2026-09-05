// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Workspace",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Workspace", targets: ["Workspace"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Workspace", dependencies: ["Core"])
    ]
)
