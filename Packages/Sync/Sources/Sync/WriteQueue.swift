import Foundation
import Core

/// The kind of change a queued write represents.
public enum WriteOperationKind: String, Codable, Equatable, Sendable {
    case create
    case update
    case delete
}

/// One durable, offline-safe write awaiting delivery to the cloud backend.
///
/// `idempotencyKey` is generated once, at enqueue time, and never changes
/// across retries. The server (see `supabase/migrations`) enforces a unique
/// constraint on `(workspace_id, idempotency_key)` for asset writes so that
/// re-sending the same queued operation after a dropped response can never
/// create a duplicate asset — the retry is a safe no-op on the server side.
public struct WriteOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var idempotencyKey: String
    public var kind: WriteOperationKind
    public var assetID: AssetID
    public var workspaceID: WorkspaceID
    /// Serialized asset payload at the time of enqueue (JSON). Nil for delete.
    public var payload: Data?
    public var enqueuedAt: Date
    public var attemptCount: Int
    public var lastError: String?

    public init(
        id: String = UUID().uuidString,
        idempotencyKey: String,
        kind: WriteOperationKind,
        assetID: AssetID,
        workspaceID: WorkspaceID,
        payload: Data?,
        enqueuedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.assetID = assetID
        self.workspaceID = workspaceID
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}

/// Generates stable idempotency keys for queued writes.
///
/// The key is deterministic from (assetID, kind, and a monotonically
/// increasing local revision counter for that asset) rather than random per
/// enqueue call, so that if the *same logical edit* is enqueued twice due to
/// an app relaunch replaying an unflushed local journal, it collapses to the
/// same key instead of double-submitting. A fresh edit bumps the revision
/// and therefore gets a fresh key, which is what we want — it's a distinct
/// change, not a retry of the old one.
public enum IdempotencyKeyGenerator {
    public static func makeKey(assetID: AssetID, kind: WriteOperationKind, revision: Int) -> String {
        "\(assetID)_\(kind.rawValue)_\(revision)"
    }
}

/// A simple FIFO durable queue abstraction. The production implementation
/// backs this with SwiftData; this in-memory implementation is used both as
/// the default for platforms without SwiftData available and as the seam
/// for unit tests.
public protocol WriteQueueStore: AnyObject {
    func enqueue(_ operation: WriteOperation)
    func dequeueAll() -> [WriteOperation]
    func remove(id: String)
    func update(_ operation: WriteOperation)
    func all() -> [WriteOperation]
}

public final class InMemoryWriteQueueStore: WriteQueueStore {
    private var operations: [WriteOperation] = []

    public init() {}

    public func enqueue(_ operation: WriteOperation) {
        operations.append(operation)
    }

    public func dequeueAll() -> [WriteOperation] {
        operations
    }

    public func remove(id: String) {
        operations.removeAll { $0.id == id }
    }

    public func update(_ operation: WriteOperation) {
        if let idx = operations.firstIndex(where: { $0.id == operation.id }) {
            operations[idx] = operation
        }
    }

    public func all() -> [WriteOperation] {
        operations
    }
}
