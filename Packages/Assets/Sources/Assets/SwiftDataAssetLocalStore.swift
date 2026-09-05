import Foundation
import Core

#if canImport(SwiftData)
import SwiftData

/// `@Model` mirror of `Core.Asset`, persisted on-device. See ADR-003 in
/// docs/ARCHITECTURE_DECISIONS.md for why SwiftData was chosen for local
/// persistence (the canonical `Asset` type itself stays pure Foundation so
/// it remains Linux-testable; this is the Apple-only storage adapter).
@Model
public final class PersistedAsset {
    @Attribute(.unique) public var id: String
    public var workspaceID: String
    public var manufacturer: String?
    public var model: String?
    public var serialNumber: String?
    public var assetTag: String?
    public var barcodeValue: String?
    public var barcodeSymbology: String?
    public var notes: String?
    public var confidenceRaw: String
    public var syncStatusRaw: String
    public var createdByUserID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(
        id: String,
        workspaceID: String,
        manufacturer: String?,
        model: String?,
        serialNumber: String?,
        assetTag: String?,
        barcodeValue: String?,
        barcodeSymbology: String?,
        notes: String?,
        confidenceRaw: String,
        syncStatusRaw: String,
        createdByUserID: String,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.assetTag = assetTag
        self.barcodeValue = barcodeValue
        self.barcodeSymbology = barcodeSymbology
        self.notes = notes
        self.confidenceRaw = confidenceRaw
        self.syncStatusRaw = syncStatusRaw
        self.createdByUserID = createdByUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    public convenience init(asset: Asset) {
        self.init(
            id: asset.id,
            workspaceID: asset.workspaceID,
            manufacturer: asset.manufacturer,
            model: asset.model,
            serialNumber: asset.serialNumber,
            assetTag: asset.assetTag,
            barcodeValue: asset.barcodeValue,
            barcodeSymbology: asset.barcodeSymbology,
            notes: asset.notes,
            confidenceRaw: asset.confidence.rawValue,
            syncStatusRaw: asset.syncStatus.rawValue,
            createdByUserID: asset.createdByUserID,
            createdAt: asset.createdAt,
            updatedAt: asset.updatedAt,
            isDeleted: asset.isDeleted
        )
    }

    public func apply(_ asset: Asset) {
        workspaceID = asset.workspaceID
        manufacturer = asset.manufacturer
        model = asset.model
        serialNumber = asset.serialNumber
        assetTag = asset.assetTag
        barcodeValue = asset.barcodeValue
        barcodeSymbology = asset.barcodeSymbology
        notes = asset.notes
        confidenceRaw = asset.confidence.rawValue
        syncStatusRaw = asset.syncStatus.rawValue
        createdByUserID = asset.createdByUserID
        createdAt = asset.createdAt
        updatedAt = asset.updatedAt
        isDeleted = asset.isDeleted
    }

    public var asAsset: Asset {
        Asset(
            id: id,
            workspaceID: workspaceID,
            manufacturer: manufacturer,
            model: model,
            serialNumber: serialNumber,
            assetTag: assetTag,
            barcodeValue: barcodeValue,
            barcodeSymbology: barcodeSymbology,
            notes: notes,
            confidence: FieldConfidence(rawValue: confidenceRaw) ?? .medium,
            syncStatus: SyncStatus(rawValue: syncStatusRaw) ?? .pendingCreate,
            createdByUserID: createdByUserID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}

/// On-device durable `AssetLocalStore`, backed by SwiftData. This is the
/// production implementation used by the app; `InMemoryAssetLocalStore`
/// remains for unit tests and any SwiftData-unavailable platform.
///
/// `ModelContext` is not thread-safe: confine an instance of this store to
/// one actor/thread (in the app, the caller of `AssetStore`, expected to be
/// `@MainActor`).
@available(iOS 17, macOS 14, *)
public final class SwiftDataAssetLocalStore: AssetLocalStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience initializer that creates its own on-disk
    /// `ModelContainer` for `PersistedAsset`. Prefer the `context:`-taking
    /// initializer when the app already has a shared container so both
    /// this store and `SwiftDataWriteQueueStore` share one SQLite file.
    public convenience init() throws {
        let container = try ModelContainer(for: PersistedAsset.self)
        self.init(context: ModelContext(container))
    }

    public func all(workspaceID: WorkspaceID) -> [Asset] {
        let predicate = #Predicate<PersistedAsset> { $0.workspaceID == workspaceID && !$0.isDeleted }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(\.asAsset)
    }

    public func save(_ asset: Asset) {
        let targetID = asset.id
        let predicate = #Predicate<PersistedAsset> { $0.id == targetID }
        if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.apply(asset)
        } else {
            context.insert(PersistedAsset(asset: asset))
        }
        try? context.save()
    }

    public func delete(id: AssetID) {
        let predicate = #Predicate<PersistedAsset> { $0.id == id }
        guard let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first else { return }
        existing.isDeleted = true
        existing.updatedAt = Date()
        try? context.save()
    }
}
#endif
