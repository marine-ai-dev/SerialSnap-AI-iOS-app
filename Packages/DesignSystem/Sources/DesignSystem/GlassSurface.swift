#if canImport(SwiftUI)
import SwiftUI

/// A card-like surface following the native Liquid Glass direction.
///
/// The real `.glassEffect()` SwiftUI API (introduced alongside visionOS/
/// iOS's Liquid Glass materials) is not declared at all in the iOS 18.2 SDK
/// shipped by Xcode 16.2 — the newest "latest-stable" Xcode this project's
/// CI (`.github/workflows/ci.yml`, macos-14 runners) currently resolves to.
/// That's not a runtime availability question `#available` can gate: the
/// symbol itself doesn't exist in this SDK, so *referencing* it anywhere in
/// source fails to compile regardless of an `#available` check, which only
/// controls when already-compiled code executes. Rather than either (a)
/// raising this package's deployment target to chase an OS version whose
/// SDK isn't present in CI, or (b) leaving CI red, this modifier always
/// uses the `.regularMaterial` native-fallback treatment for now. Every
/// call site already goes through `ssGlassSurface(cornerRadius:)` alone,
/// so swapping in the real `.glassEffect()` call here — behind
/// `#available(iOS 18.0, macOS 15.0, *)` as originally intended — is a
/// one-file change once a CI/Xcode toolchain that ships the API is
/// available; nothing calling this modifier needs to change.
public struct GlassSurfaceModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    /// Applies the SerialSnap glass-surface treatment (see `GlassSurfaceModifier`).
    func ssGlassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}
#endif
