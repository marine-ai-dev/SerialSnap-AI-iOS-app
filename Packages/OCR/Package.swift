// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OCR",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OCR", targets: ["OCR"])
    ],
    dependencies: [
        .package(path: "../Parsing")
    ],
    targets: [
        // iOS-only: uses Vision/AVFoundation. Cannot build on Linux —
        // see docs/CLOUD_CONTINUATION.md for verification status.
        .target(name: "OCR", dependencies: ["Parsing"])
    ]
)
