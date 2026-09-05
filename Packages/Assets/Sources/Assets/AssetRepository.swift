import Foundation
import Core
import Sync
import Parsing

/// Abstraction over local persistence (SwiftData in the real app) for
/// assets, kept protocol-based so `AssetStore`'s duplicate-detection and
/// save-flow logic is unit-testable without SwiftData.
public protocol AssetLocalStore {
    func all(workspaceID: WorkspaceID) -> [Asset]
    func save(_ asset: Asset)
    func delete(id: AssetID)
}

public final class InMemoryAssetLocalStore: AssetLocalStore {
    private var assetsByID: [AssetID: Asset] = [:]

    public init() {}

    public func all(workspaceID: WorkspaceID) -> [Asset] {
        assetsByID.values.filter { $0.workspaceID == workspaceID && !$0.isDeleted }
    }

    public func save(_ asset: Asset) {
        assetsByID[asset.id] = asset
    }

    public func delete(id: AssetID) {
        if var asset = assetsByID[id] {
            asset.isDeleted = true
            asset.updatedAt = Date()
            assetsByID[id] = asset
        }
    }
}

/// Coordinates: extracted-fields -> candidate Asset -> duplicate check
/// within the workspace -> local save + enqueue for sync. This is the
/// object the Scanner/Review UI drives after a scan is confirmed.
public final class AssetStore {
    private let localStore: AssetLocalStore
    private let writeQueue: WriteQueueStore

    public init(localStore: AssetLocalStore, writeQueue: WriteQueueStore) {
        self.localStore = localStore
        self.writeQueue = writeQueue
    }

    /// Builds a candidate `Asset` from parser output, ready for the review
    /// screen. Does not save it yet — the human confirms/edits first.
    public func makeCandidate(from fields: ExtractedFields, workspaceID: WorkspaceID, userID: UserID) -> Asset {
        Asset(
            id: UUID().uuidString,
            workspaceID: workspaceID,
            manufacturer: fields.manufacturer?.value,
            model: fields.model?.value,
            serialNumber: fields.serialNumber?.value,
            assetTag: fields.assetTag?.value,
            barcodeValue: fields.barcodeValue,
            barcodeSymbology: fields.barcodeSymbology,
            confidence: mapConfidence(fields.overallConfidence),
            syncStatus: .pendingCreate,
            createdByUserID: userID
        )
    }

    /// Finds existing assets in the workspace that are probable duplicates
    /// of `candidate`, for the review screen's duplicate-warning banner.
    public func findDuplicates(of candidate: Asset) -> [Asset] {
        localStore.all(workspaceID: candidate.workspaceID).filter { $0.isProbableDuplicate(of: candidate) }
    }

    /// Persists the (possibly user-edited) asset locally and enqueues it
    /// for sync — this never blocks on network, so a scan is never lost
    /// offline. `revision` should be incremented by the caller for every
    /// logical edit to the same assetID so idempotency keys stay correct
    /// across retries but distinct across real edits.
    public func save(_ asset: Asset, revision: Int) {
        localStore.save(asset)
        let kind: WriteOperationKind = revision == 0 ? .create : .update
        let key = IdempotencyKeyGenerator.makeKey(assetID: asset.id, kind: kind, revision: revision)
        let payload = try? JSONEncoder().encode(asset)
        let op = WriteOperation(idempotencyKey: key, kind: kind, assetID: asset.id, workspaceID: asset.workspaceID, payload: payload)
        writeQueue.enqueue(op)
    }

    public func delete(_ asset: Asset, revision: Int) {
        localStore.delete(id: asset.id)
        let key = IdempotencyKeyGenerator.makeKey(assetID: asset.id, kind: .delete, revision: revision)
        let op = WriteOperation(idempotencyKey: key, kind: .delete, assetID: asset.id, workspaceID: asset.workspaceID, payload: nil)
        writeQueue.enqueue(op)
    }

    public func search(_ query: String, in workspaceID: WorkspaceID) -> [Asset] {
        let all = localStore.all(workspaceID: workspaceID)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        let needle = query.lowercased()
        return all.filter {
            ($0.manufacturer?.lowercased().contains(needle) ?? false) ||
            ($0.model?.lowercased().contains(needle) ?? false) ||
            ($0.serialNumber?.lowercased().contains(needle) ?? false) ||
            ($0.assetTag?.lowercased().contains(needle) ?? false)
        }
    }

    private func mapConfidence(_ c: ParsedConfidence) -> FieldConfidence {
        switch c {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}
