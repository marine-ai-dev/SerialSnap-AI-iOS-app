// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Auth", targets: ["Auth"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../SupabaseKit")
    ],
    targets: [
        // iOS-only: uses AuthenticationServices (Sign in with Apple).
        // Depends on SupabaseKit (not supabase-swift directly) — see
        // Packages/SupabaseKit/Package.swift for why.
        .target(name: "Auth", dependencies: ["Core", "SupabaseKit"])
    ]
)
