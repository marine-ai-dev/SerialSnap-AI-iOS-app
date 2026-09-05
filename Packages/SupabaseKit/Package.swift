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
    // supabase-swift supports macOS as well as iOS; declared here too so
    // Auth/Workspace/Sync (which depend on this package and declare macOS
    // support themselves, to let their unit tests run portably in CI
    // without an iOS Simulator) don't hit a platform-mismatch build error.
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SupabaseKit", targets: ["SupabaseKit"])
    ],
    dependencies: [
        .package(path: "../Core"),
        // Pinned below 2.50.0: from that version onward, supabase-swift's
        // own Package.swift declares swift-tools-version 6.1, which the
        // Swift 6.0.3 toolchain shipped in Xcode 16.2 (the current
        // "latest-stable" on GitHub Actions' macos-14 runners as of this
        // commit) cannot resolve at all ("contains incompatible tools
        // version") — this is a real CI failure this session hit and
        // verified by inspecting supabase-swift's tagged Package.swift
        // files directly, not a guess. v2.49.0 (tools-version 5.10) has
        // the same Auth/PostgREST APIs this app uses (signInWithIdToken,
        // .from(...), .rpc(...)) and the same module-name collision this
        // package's aliasing works around. Revisit this pin once CI's
        // Xcode version ships Swift 6.1+.
        .package(url: "https://github.com/supabase/supabase-swift", "2.30.0"..<"2.50.0")
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
