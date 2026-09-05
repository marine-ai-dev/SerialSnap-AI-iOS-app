// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Parsing",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Parsing", targets: ["Parsing"])
    ],
    targets: [
        // Pure Swift only: no UIKit/SwiftUI/Vision imports permitted here.
        .target(name: "Parsing"),
        .testTarget(name: "ParsingTests", dependencies: ["Parsing"])
    ]
)
