// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Auth", targets: ["Auth"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        // iOS-only: uses AuthenticationServices (Sign in with Apple).
        .target(name: "Auth", dependencies: ["Core"])
    ]
)
