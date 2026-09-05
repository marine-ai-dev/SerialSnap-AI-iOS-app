import SwiftUI
import Localization
import DesignSystem

/// Asset list skeleton covering search/empty states per spec. Real data
/// binding to `Assets.AssetStore` + SwiftData is wired in milestone 2 —
/// see docs/CLOUD_CONTINUATION.md.
struct AssetListScreen: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            EmptyStateView()
                .navigationTitle(L10n.AssetsList.title)
                .searchable(text: $searchText, prompt: L10n.AssetsList.searchPlaceholder)
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.secondaryText)
            Text(L10n.AssetsList.empty)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}
