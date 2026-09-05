import Foundation
import Core

/// Abstraction over the remote backend so `SyncEngine` is fully unit
/// testable without a network connection or a real Supabase project.
public protocol RemoteAssetService {
    /// Submits a write. The server is expected to treat `idempotencyKey` as
    /// a dedupe key: a repeat submission with the same key returns the same
    /// server-side result without creating a second record.
    func submit(_ operation: WriteOperation) async throws -> RemoteAssetRecord
    func fetchAll(workspaceID: WorkspaceID) async throws -> [RemoteAssetRecord]
}

/// What the server hands back for a given asset — used to detect conflicts.
public struct RemoteAssetRecord: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var updatedAt: Date
    public var payload: Data?
    public var isDeleted: Bool

    public init(assetID: AssetID, updatedAt: Date, payload: Data?, isDeleted: Bool = false) {
        self.assetID = assetID
        self.updatedAt = updatedAt
        self.payload = payload
        self.isDeleted = isDeleted
    }
}

public enum SyncError: Error, Equatable {
    case network(String)
    case server(String)
}

/// Outcome of resolving a local pending write against the server's current
/// state for that asset.
public enum ConflictResolution: Equatable {
    /// Local write wins — either there was no server conflict, or the local
    /// edit is newer.
    case applyLocal
    /// Server's version is newer; discard the local pending write and adopt
    /// the server state instead.
    case adoptRemote(RemoteAssetRecord)
}

/// Conflict resolution strategy: **last-write-wins by `updatedAt`**.
///
/// Rationale (documented per spec, see docs/CLOUD_ARCHITECTURE.md too):
/// SerialSnap assets are edited by at most a small number of collaborators
/// in a workspace, edits are infrequent relative to reads, and field-level
/// merge would add significant complexity for a low-value payoff at this
/// stage. LWW by `updatedAt` timestamp is simple, deterministic, and
/// sufficient: whichever edit has the later timestamp is kept in full. Ties
/// (identical timestamp) favor the server to keep behavior deterministic
/// across devices.
public enum ConflictResolver {
    public static func resolve(localUpdatedAt: Date, remote: RemoteAssetRecord) -> ConflictResolution {
        if localUpdatedAt > remote.updatedAt {
            return .applyLocal
        }
        return .adoptRemote(remote)
    }
}

/// Drains the local write queue against the remote service, applying
/// retry-with-backoff semantics and idempotent resubmission.
public final class SyncEngine {
    private let store: WriteQueueStore
    private let remote: RemoteAssetService
    public var maxAttempts: Int

    public init(store: WriteQueueStore, remote: RemoteAssetService, maxAttempts: Int = 5) {
        self.store = store
        self.remote = remote
        self.maxAttempts = maxAttempts
    }

    /// Attempts to flush every queued operation once. Operations that fail
    /// are left in the queue (with an incremented attempt count) for a later
    /// retry; operations that exceed `maxAttempts` are marked failed and
    /// left in place for user-visible surfacing rather than being dropped —
    /// a scan must never be silently lost.
    @discardableResult
    public func flush() async -> SyncFlushSummary {
        var succeeded = 0
        var failed = 0
        var permanentlyFailed = 0

        for operation in store.dequeueAll() {
            do {
                _ = try await remote.submit(operation)
                store.remove(id: operation.id)
                succeeded += 1
            } catch {
                var updated = operation
                updated.attemptCount += 1
                updated.lastError = String(describing: error)
                if updated.attemptCount >= maxAttempts {
                    permanentlyFailed += 1
                } else {
                    failed += 1
                }
                store.update(updated)
            }
        }
        return SyncFlushSummary(succeeded: succeeded, retriableFailures: failed, permanentFailures: permanentlyFailed)
    }
}

public struct SyncFlushSummary: Equatable {
    public var succeeded: Int
    public var retriableFailures: Int
    public var permanentFailures: Int
}
