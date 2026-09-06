// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppAuth",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "AppAuth", targets: ["AppAuth"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../SupabaseKit")
    ],
    targets: [
        // iOS-only: uses AuthenticationServices (Sign in with Apple).
        // Depends on SupabaseKit (not supabase-swift directly) — see
        // Packages/SupabaseKit/Package.swift for why.
        .target(name: "AppAuth", dependencies: ["Core", "SupabaseKit"])
    ]
)
