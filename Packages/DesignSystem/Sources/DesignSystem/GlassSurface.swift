#if canImport(SwiftUI)
import SwiftUI

/// A card-like surface following the native Liquid Glass direction:
/// uses `.glassEffect()` on OS versions that support it (iOS 18+), and
/// falls back to `.regularMaterial` on earlier iOS 17 devices. Callers
/// never branch on OS version themselves — this modifier is the single
/// seam for that.
public struct GlassSurfaceModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
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
