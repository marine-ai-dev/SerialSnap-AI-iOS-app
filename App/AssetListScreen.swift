import SwiftUI
import Core
import Assets
import Export
import AppAuth
import Workspace
import Localization
import DesignSystem

// MARK: - Asset list screen

struct AssetListScreen: View {
    @EnvironmentObject private var assetViewModel: AssetViewModel
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if assetViewModel.assets.isEmpty {
                    EmptyAssetsView(isSearching: !searchText.isEmpty)
                } else {
                    assetList
                }
            }
            .navigationTitle(L10n.AssetsList.title)
            .searchable(text: $searchText, prompt: L10n.AssetsList.searchPlaceholder)
            .onChange(of: searchText) { _, query in
                assetViewModel.search(query)
            }
            .toolbar {
                if assetViewModel.isFlushingSync {
                    ToolbarItem(placement: .topBarLeading) {
                        ProgressView()
                            .accessibilityLabel("Syncing changes")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ExportMenuButton(assets: assetViewModel.assets)
                }
            }
        }
        .onAppear {
            if let wid = workspaceStore.selectedWorkspace?.id {
                assetViewModel.activate(workspaceID: wid)
            }
        }
        .onChange(of: workspaceStore.selectedWorkspace?.id) { _, wid in
            if let wid { assetViewModel.activate(workspaceID: wid) }
        }
    }

    private var assetList: some View {
        List {
            ForEach(assetViewModel.assets) { asset in
                NavigationLink {
                    AssetDetailView(asset: asset)
                } label: {
                    AssetRowView(asset: asset)
                }
                .accessibilityLabel(assetAccessibilityLabel(asset))
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Asset inventory")
    }

    private func assetAccessibilityLabel(_ asset: Asset) -> String {
        var parts: [String] = []
        if let v = asset.model { parts.append(v) }
        if let v = asset.manufacturer { parts.append(v) }
        if let v = asset.serialNumber { parts.append("Serial number \(v)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Empty state

private struct EmptyAssetsView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.secondaryText)
                .accessibilityHidden(true)
            Text(isSearching ? "No results" : L10n.AssetsList.empty)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}

// MARK: - Asset row

private struct AssetRowView: View {
    let asset: Asset

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryLabel)
                    .font(SSFont.headline)
                    .foregroundStyle(SSColor.primaryText)
                    .lineLimit(1)
                if let serial = asset.serialNumber {
                    Text("S/N \(serial)")
                        .font(SSFont.monospacedValue)
                        .foregroundStyle(SSColor.secondaryText)
                        .lineLimit(1)
                } else if let tag = asset.assetTag {
                    Text("Tag \(tag)")
                        .font(SSFont.monospacedValue)
                        .foregroundStyle(SSColor.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            SyncStatusIcon(status: asset.syncStatus)
        }
        .padding(.vertical, 2)
    }

    private var primaryLabel: String {
        [asset.model, asset.manufacturer].compactMap({ $0 }).first ?? "Asset"
    }
}

// MARK: - Sync status icon

struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch status {
        case .synced: return "checkmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
        case .pendingCreate, .pendingUpdate, .pendingDelete: return "arrow.triangle.2.circlepath.icloud"
        case .failed: return "exclamationmark.icloud.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .synced: return .green
        case .syncing: return .blue
        case .pendingCreate, .pendingUpdate, .pendingDelete: return .orange
        case .failed: return .red
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .synced: return "Synced"
        case .syncing: return "Syncing"
        case .pendingCreate, .pendingUpdate, .pendingDelete: return L10n.AssetsList.syncPending
        case .failed: return L10n.AssetsList.syncFailed
        }
    }
}

// MARK: - Asset detail / edit / delete

struct AssetDetailView: View {
    @EnvironmentObject private var assetViewModel: AssetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var asset: Asset
    @State private var isEditing = false
    @State private var showDeleteConfirm = false

    // Edit-mode state mirrors
    @State private var editManufacturer = ""
    @State private var editModel = ""
    @State private var editSerial = ""
    @State private var editTag = ""
    @State private var editNotes = ""

    init(asset: Asset) {
        _asset = State(initialValue: asset)
    }

    var body: some View {
        Form {
            identitySection
            if asset.barcodeValue != nil {
                barcodeSection
            }
            notesSection
            metadataSection
            deleteSection
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button(L10n.Common.done) { commitEdit() }
                        .fontWeight(.semibold)
                } else {
                    Button("Edit") { beginEdit() }
                }
            }
        }
        .alert(L10n.AssetDetail.delete, isPresented: $showDeleteConfirm) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.AssetDetail.delete, role: .destructive) {
                assetViewModel.delete(asset)
                dismiss()
            }
        } message: {
            Text(L10n.AssetDetail.deleteConfirm)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var identitySection: some View {
        Section {
            if isEditing {
                editRow(label: L10n.Review.manufacturer, text: $editManufacturer)
                editRow(label: L10n.Review.model, text: $editModel)
                editRow(label: L10n.Review.serialNumber, text: $editSerial, monospaced: true)
                editRow(label: L10n.Review.assetTag, text: $editTag, monospaced: true)
            } else {
                detailRow(label: L10n.Review.manufacturer, value: asset.manufacturer)
                detailRow(label: L10n.Review.model, value: asset.model)
                detailRow(label: L10n.Review.serialNumber, value: asset.serialNumber, monospaced: true)
                detailRow(label: L10n.Review.assetTag, value: asset.assetTag, monospaced: true)
            }
        }
    }

    private var barcodeSection: some View {
        Section("Barcode") {
            if let v = asset.barcodeValue {
                LabeledContent("Value", value: v)
                    .font(SSFont.monospacedValue)
                    .accessibilityLabel("Barcode value \(v)")
            }
            if let v = asset.barcodeSymbology {
                LabeledContent("Symbology", value: v)
                    .accessibilityLabel("Barcode symbology \(v)")
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            if isEditing {
                TextField("Optional notes", text: $editNotes, axis: .vertical)
                    .lineLimit(3...)
                    .accessibilityLabel("Notes")
            } else {
                Text(asset.notes ?? "—")
                    .foregroundStyle(asset.notes == nil ? SSColor.secondaryText : SSColor.primaryText)
                    .accessibilityLabel(asset.notes ?? "No notes")
            }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            LabeledContent("Confidence") {
                ConfidenceBadge(level: badgeLevel(asset.confidence))
            }
            .accessibilityLabel("Confidence \(asset.confidence.rawValue)")
            LabeledContent("Sync") {
                SyncStatusIcon(status: asset.syncStatus)
            }
            .accessibilityLabel("Sync status \(asset.syncStatus.rawValue)")
            LabeledContent("Created") {
                Text(asset.createdAt, style: .relative)
            }
            .accessibilityLabel("Created \(asset.createdAt.formatted())")
            LabeledContent("Updated") {
                Text(asset.updatedAt, style: .relative)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(L10n.AssetDetail.delete, systemImage: "trash")
            }
            .accessibilityLabel(L10n.AssetDetail.delete)
            .accessibilityHint("Permanently deletes this asset after confirmation")
        }
    }

    // MARK: Row helpers

    @ViewBuilder
    private func editRow(label: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .font(monospaced ? SSFont.monospacedValue : SSFont.body)
                .accessibilityLabel(label)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String?, monospaced: Bool = false) -> some View {
        if let value {
            LabeledContent(label, value: value)
                .font(monospaced ? SSFont.monospacedValue : SSFont.body)
                .accessibilityLabel("\(label) \(value)")
        }
    }

    // MARK: Actions

    private func beginEdit() {
        editManufacturer = asset.manufacturer ?? ""
        editModel = asset.model ?? ""
        editSerial = asset.serialNumber ?? ""
        editTag = asset.assetTag ?? ""
        editNotes = asset.notes ?? ""
        isEditing = true
    }

    private func commitEdit() {
        asset.manufacturer = editManufacturer.trimmingCharacters(in: .whitespaces).nonEmpty
        asset.model = editModel.trimmingCharacters(in: .whitespaces).nonEmpty
        asset.serialNumber = editSerial.trimmingCharacters(in: .whitespaces).nonEmpty
        asset.assetTag = editTag.trimmingCharacters(in: .whitespaces).nonEmpty
        asset.notes = editNotes.trimmingCharacters(in: .whitespaces).nonEmpty
        assetViewModel.update(asset)
        isEditing = false
    }

    private var navTitle: String {
        [asset.model, asset.manufacturer].compactMap({ $0 }).first ?? "Asset"
    }

    private func badgeLevel(_ c: FieldConfidence) -> ConfidenceBadge.Level {
        switch c {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

// MARK: - Export menu

private struct ExportMenuButton: View {
    let assets: [Asset]

    var body: some View {
        Menu {
            let csvURL = tempFile(name: "assets.csv", data: AssetExporter.csvData(for: assets))
            if let url = csvURL {
                ShareLink(item: url, preview: SharePreview("assets.csv")) {
                    Label(L10n.Export.csv, systemImage: "tablecells")
                }
            }

            if let jsonData = try? AssetExporter.jsonData(for: assets),
               let url = tempFile(name: "assets.json", data: jsonData) {
                ShareLink(item: url, preview: SharePreview("assets.json")) {
                    Label(L10n.Export.json, systemImage: "doc.text")
                }
            }
        } label: {
            Label(L10n.Export.title, systemImage: "square.and.arrow.up")
        }
        .disabled(assets.isEmpty)
        .accessibilityLabel(L10n.Export.title)
        .accessibilityHint(assets.isEmpty ? "No assets to export" : "Export assets as CSV or JSON")
    }

    private func tempFile(name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
