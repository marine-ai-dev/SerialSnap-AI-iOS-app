#if canImport(SwiftUI)
import SwiftUI

/// A card-like surface using Liquid Glass on iOS 26+ and regularMaterial as fallback.
///
/// `.glassEffect()` requires @available(iOS 26.0, *) — it didn't exist in
/// earlier SDKs. Every call site goes through `ssGlassSurface(cornerRadius:)`
/// so this is the only file that needs updating when the availability changes.
public struct GlassSurfaceModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

public extension View {
    /// Applies the SerialSnap glass-surface treatment (see `GlassSurfaceModifier`).
    func ssGlassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}
#endif
