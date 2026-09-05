// swift-tools-version:5.9
import PackageDescription

/// Thin facade around `supabase-swift`. See docs/ARCHITECTURE_DECISIONS.md
/// ADR-006 for why this exists as its own package rather than each feature
/// package depending on `supabase-swift` directly: `supabase-swift` ships a
/// library literally named `Auth`, which collides with this repo's own
/// `Packages/Auth` module name in the SwiftPM build graph. Isolating the
/// `supabase-swift` dependency to this one package — and using SwiftPM
/// module aliasing (SE-0339) on the single edge that pulls it in — means no
/// other package in the repo ever needs to `import Auth` from
/// `supabase-swift` or otherwise be aware of the collision. `SupabaseKit`'s
/// public API is expressed entirely in plain Foundation/Core types so
/// `Auth`, `Workspace`, and `Sync` can consume it without any module-name
/// exposure at all.
let package = Package(
    name: "SupabaseKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SupabaseKit", targets: ["SupabaseKit"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.0")
    ],
    targets: [
        .target(
            name: "SupabaseKit",
            dependencies: [
                "Core",
                .product(
                    name: "Supabase",
                    package: "supabase-swift",
                    // Renames supabase-swift's `Auth` module to `SupabaseAuthKit`
                    // as compiled into this target, so it never collides with
                    // this repo's own `Packages/Auth` module. Only this single
                    // dependency edge needs the alias; every other package in
                    // this repo depends on `SupabaseKit` alone and never sees
                    // either `Auth` module name from supabase-swift.
                    moduleAliases: ["Auth": "SupabaseAuthKit"]
                )
            ]
        )
    ]
)
