#if canImport(SwiftUI)
import SwiftUI

/// Semantic text styles built on Dynamic Type text styles (never fixed
/// point sizes), so every screen respects the user's chosen text size and
/// accessibility text sizes automatically.
public enum SSFont {
    public static let title = Font.title.weight(.semibold)
    public static let headline = Font.headline
    public static let body = Font.body
    public static let caption = Font.caption
    public static let monospacedValue = Font.system(.body, design: .monospaced)
}

public struct ConfidenceBadge: View {
    public enum Level { case low, medium, high }
    let level: Level

    public init(level: Level) {
        self.level = level
    }

    public var body: some View {
        Text(label)
            .font(SSFont.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch level {
        case .low: return "Low confidence"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }

    private var color: Color {
        switch level {
        case .low: return SSColor.lowConfidence
        case .medium: return SSColor.mediumConfidence
        case .high: return SSColor.highConfidence
        }
    }
}
#endif
