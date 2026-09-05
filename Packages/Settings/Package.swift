// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Settings", targets: ["Settings"])
    ],
    targets: [
        .target(name: "Settings")
    ]
)
