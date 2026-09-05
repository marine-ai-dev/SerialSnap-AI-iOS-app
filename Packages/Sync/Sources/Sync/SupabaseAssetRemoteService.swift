import Foundation
import Core
import SupabaseKit

/// Real, production `RemoteAssetService` backed by Supabase PostgREST
/// (`/rest/v1/assets`), matching
/// `supabase/migrations/20260901000001_initial_schema.sql`.
///
/// Idempotent writes: every `submit` is an **upsert on the row's primary
/// key** (`id`, the client-generated `AssetID` — see
/// `Assets.AssetStore.makeCandidate`) via PostgREST's
/// `Prefer: resolution=merge-duplicates` header (see
/// `SupabaseGateway.upsert`). Because a *retry* of a queued write always
/// resubmits the exact same `WriteOperation` (same `assetID`), upserting on
/// `id` makes a retried create a safe no-op and a retried update reapply
/// cleanly — both without a duplicate row. `idempotency_key` is still sent
/// and still carries the unique index the initial schema migration defines
/// on `(workspace_id, idempotency_key)`
/// (`uq_assets_workspace_idempotency`): it's a second, independent
/// integrity guard that makes it a hard database error (rather than silent
/// data corruption) if two different asset rows in the same workspace ever
/// end up with the same idempotency key — which should never happen given
/// `IdempotencyKeyGenerator`, but is exactly the kind of invariant worth
/// having the database enforce rather than trusting the client to uphold.
/// See docs/CLOUD_ARCHITECTURE.md "Idempotent asset writes" for the full
/// rationale, including why this was chosen over a bespoke
/// `upsert_asset_idempotent` RPC.
public final class SupabaseAssetRemoteService: RemoteAssetService {
    private let gateway: SupabaseGateway
    private static let table = "assets"

    public init(gateway: SupabaseGateway) {
        self.gateway = gateway
    }

    public func submit(_ operation: WriteOperation) async throws -> RemoteAssetRecord {
        switch operation.kind {
        case .create, .update:
            guard let payload = operation.payload,
                  let asset = try? JSONDecoder().decode(Asset.self, from: payload) else {
                throw SyncError.server("WriteOperation \(operation.id) has no decodable asset payload")
            }
            let row = AssetUpsertRow(asset: asset, idempotencyKey: operation.idempotencyKey)
            let result: AssetRow
            do {
                result = try await gateway.upsert(
                    table: Self.table,
                    values: row,
                    onConflict: "id",
                    returning: AssetRow.self
                )
            } catch {
                throw SyncError.network(String(describing: error))
            }
            return result.asRemoteRecord

        case .delete:
            // Soft-delete: set is_deleted rather than issuing a DELETE, so
            // the tombstone propagates to other devices during sync (see
            // docs/CLOUD_ARCHITECTURE.md "assets.is_deleted"). Scoped by
            // both id and workspace_id, matching the RLS policy's
            // expectations and guarding against a stale/mismatched
            // workspaceID ever touching another workspace's row (RLS would
            // reject it anyway, but the filter keeps intent explicit here).
            do {
                let updated: [AssetRow] = try await gateway.update(
                    table: Self.table,
                    values: AssetSoftDeleteRow(),
                    filters: [
                        PGFilter("id", eq: operation.assetID),
                        PGFilter("workspace_id", eq: operation.workspaceID)
                    ],
                    returning: AssetRow.self
                )
                guard let row = updated.first else {
                    throw SyncError.server("Delete of asset \(operation.assetID) matched no row")
                }
                return row.asRemoteRecord
            } catch let error as SyncError {
                throw error
            } catch {
                throw SyncError.network(String(describing: error))
            }
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [RemoteAssetRecord] {
        do {
            let rows: [AssetRow] = try await gateway.select(
                table: Self.table,
                filters: [PGFilter("workspace_id", eq: workspaceID)],
                as: AssetRow.self
            )
            return rows.map(\.asRemoteRecord)
        } catch {
            throw SyncError.network(String(describing: error))
        }
    }
}

// MARK: - Row DTOs

/// Matches `public.assets` (see initial schema migration).
private struct AssetRow: Decodable {
    let id: String
    let workspaceID: String
    let updatedAt: Date
    let isDeleted: Bool
    let manufacturer: String?
    let model: String?
    let serialNumber: String?
    let assetTag: String?
    let barcodeValue: String?
    let barcodeSymbology: String?
    let notes: String?
    let confidence: String
    let createdByUserID: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case manufacturer, model
        case serialNumber = "serial_number"
        case assetTag = "asset_tag"
        case barcodeValue = "barcode_value"
        case barcodeSymbology = "barcode_symbology"
        case notes, confidence
        case createdByUserID = "created_by_user_id"
        case createdAt = "created_at"
    }

    /// `RemoteAssetRecord.payload` carries the full row re-encoded as an
    /// `Asset` so `SyncEngine`/`ConflictResolver` can adopt the server's
    /// state wholesale on a conflict — see `ConflictResolver.resolve`.
    var asRemoteRecord: RemoteAssetRecord {
        let asset = Asset(
            id: id,
            workspaceID: workspaceID,
            manufacturer: manufacturer,
            model: model,
            serialNumber: serialNumber,
            assetTag: assetTag,
            barcodeValue: barcodeValue,
            barcodeSymbology: barcodeSymbology,
            notes: notes,
            confidence: FieldConfidence(rawValue: confidence) ?? .medium,
            syncStatus: .synced,
            createdByUserID: createdByUserID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
        let payload = try? JSONEncoder().encode(asset)
        return RemoteAssetRecord(assetID: id, updatedAt: updatedAt, payload: payload, isDeleted: isDeleted)
    }
}

/// Upsert payload for `POST /rest/v1/assets` with
/// `Prefer: resolution=merge-duplicates`, conflict target `id`. The
/// client-generated `AssetID` (see `Assets.AssetStore.makeCandidate`) is
/// sent as the row's primary key so the same logical asset always maps to
/// the same server row across create, subsequent updates, and retries —
/// see the `SupabaseAssetRemoteService` doc comment above.
private struct AssetUpsertRow: Encodable {
    let id: String
    let workspaceID: String
    let manufacturer: String?
    let model: String?
    let serialNumber: String?
    let assetTag: String?
    let barcodeValue: String?
    let barcodeSymbology: String?
    let notes: String?
    let confidence: String
    let createdByUserID: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case manufacturer, model
        case serialNumber = "serial_number"
        case assetTag = "asset_tag"
        case barcodeValue = "barcode_value"
        case barcodeSymbology = "barcode_symbology"
        case notes, confidence
        case createdByUserID = "created_by_user_id"
        case idempotencyKey = "idempotency_key"
    }

    init(asset: Asset, idempotencyKey: String) {
        id = asset.id
        workspaceID = asset.workspaceID
        manufacturer = asset.manufacturer
        model = asset.model
        serialNumber = asset.serialNumber
        assetTag = asset.assetTag
        barcodeValue = asset.barcodeValue
        barcodeSymbology = asset.barcodeSymbology
        notes = asset.notes
        confidence = asset.confidence.rawValue
        createdByUserID = asset.createdByUserID
        self.idempotencyKey = idempotencyKey
    }
}

private struct AssetSoftDeleteRow: Encodable {
    let isDeleted = true

    enum CodingKeys: String, CodingKey {
        case isDeleted = "is_deleted"
    }
}
