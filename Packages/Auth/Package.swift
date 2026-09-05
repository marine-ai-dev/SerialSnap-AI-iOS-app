// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Auth", targets: ["Auth"])
    ],
    targets: [
        .target(name: "Auth")
    ]
)
