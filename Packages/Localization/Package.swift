// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Localization",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Localization", targets: ["Localization"])
    ],
    targets: [
        .target(name: "Localization", resources: [.process("Resources")])
    ]
)
