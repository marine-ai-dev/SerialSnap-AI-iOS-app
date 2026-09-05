// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Scanner",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Scanner", targets: ["Scanner"])
    ],
    dependencies: [
        .package(path: "../OCR"),
        .package(path: "../Parsing"),
    ],
    targets: [
        // iOS-only: uses AVFoundation for camera capture.
        .target(name: "Scanner", dependencies: ["OCR", "Parsing"])
    ]
)
