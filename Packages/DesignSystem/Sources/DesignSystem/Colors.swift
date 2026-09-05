#if canImport(SwiftUI)
import SwiftUI

/// Semantic color tokens for SerialSnap. Defined via SwiftUI `Color` +
/// asset-catalog-free dynamic system colors so the app automatically
/// adapts to light/dark mode and increased-contrast accessibility settings
/// without a custom asset catalog to maintain in milestone 1.
public enum SSColor {
    public static let background = Color(uiColor: .systemBackground)
    public static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)
    public static let accent = Color.accentColor
    public static let success = Color.green
    public static let warning = Color.orange
    public static let danger = Color.red
    public static let lowConfidence = Color.orange
    public static let mediumConfidence = Color.yellow
    public static let highConfidence = Color.green
}
#endif
