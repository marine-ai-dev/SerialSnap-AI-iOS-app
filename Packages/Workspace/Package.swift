// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Workspace",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Workspace", targets: ["Workspace"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../SupabaseKit")
    ],
    targets: [
        .target(name: "Workspace", dependencies: ["Core", "SupabaseKit"])
    ]
)
