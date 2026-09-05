// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Sync", targets: ["Sync"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../SupabaseKit")
    ],
    targets: [
        // SwiftData (SwiftDataWriteQueueStore.swift) is iOS/macOS-only and
        // gated behind `#if canImport(SwiftData)`, so this target still
        // builds for the plain in-memory store on any platform.
        .target(name: "Sync", dependencies: ["Core", "SupabaseKit"]),
        .testTarget(name: "SyncTests", dependencies: ["Sync"])
    ]
)
