import Foundation
import Core

#if canImport(SwiftData)
import SwiftData

/// `@Model` mirror of `WriteOperation`, persisted on-device so the offline
/// write queue survives app relaunch and force-quit — the whole point of an
/// offline-safe queue is that a scan taken with no connectivity is still
/// there to flush once connectivity returns. See ADR-003 in
/// docs/ARCHITECTURE_DECISIONS.md for why SwiftData was chosen for local
/// persistence.
@Model
public final class PersistedWriteOperation {
    @Attribute(.unique) public var id: String
    public var idempotencyKey: String
    public var kindRaw: String
    public var assetID: String
    public var workspaceID: String
    public var payload: Data?
    public var enqueuedAt: Date
    public var attemptCount: Int
    public var lastError: String?

    public init(
        id: String,
        idempotencyKey: String,
        kindRaw: String,
        assetID: String,
        workspaceID: String,
        payload: Data?,
        enqueuedAt: Date,
        attemptCount: Int,
        lastError: String?
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.kindRaw = kindRaw
        self.assetID = assetID
        self.workspaceID = workspaceID
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }

    public var asWriteOperation: WriteOperation? {
        guard let kind = WriteOperationKind(rawValue: kindRaw) else { return nil }
        return WriteOperation(
            id: id,
            idempotencyKey: idempotencyKey,
            kind: kind,
            assetID: assetID,
            workspaceID: workspaceID,
            payload: payload,
            enqueuedAt: enqueuedAt,
            attemptCount: attemptCount,
            lastError: lastError
        )
    }
}

/// On-device durable `WriteQueueStore`, backed by SwiftData. This is the
/// production implementation used by the app; `InMemoryWriteQueueStore`
/// (see `WriteQueue.swift`) remains for unit tests and for any
/// SwiftData-unavailable platform.
///
/// Every method is synchronous over a single `ModelContext`, matching
/// `WriteQueueStore`'s synchronous protocol — SwiftData's `ModelContext`
/// is not thread-safe, so callers must confine an instance of this store to
/// one actor/thread (in the app, the `@MainActor` `SyncEngine` call site).
@available(iOS 17, macOS 14, *)
public final class SwiftDataWriteQueueStore: WriteQueueStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience initializer that creates its own on-disk
    /// `ModelContainer` for `PersistedWriteOperation`. Use the
    /// `context:`-taking initializer instead when the app already has a
    /// shared container (e.g. one also holding `PersistedAsset`) so both
    /// stores share a single SQLite file.
    public convenience init() throws {
        let container = try ModelContainer(for: PersistedWriteOperation.self)
        self.init(context: ModelContext(container))
    }

    public func enqueue(_ operation: WriteOperation) {
        let model = PersistedWriteOperation(
            id: operation.id,
            idempotencyKey: operation.idempotencyKey,
            kindRaw: operation.kind.rawValue,
            assetID: operation.assetID,
            workspaceID: operation.workspaceID,
            payload: operation.payload,
            enqueuedAt: operation.enqueuedAt,
            attemptCount: operation.attemptCount,
            lastError: operation.lastError
        )
        context.insert(model)
        try? context.save()
    }

    public func dequeueAll() -> [WriteOperation] {
        all()
    }

    public func remove(id: String) {
        let predicate = #Predicate<PersistedWriteOperation> { $0.id == id }
        if let match = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            context.delete(match)
            try? context.save()
        }
    }

    public func update(_ operation: WriteOperation) {
        let targetID = operation.id
        let predicate = #Predicate<PersistedWriteOperation> { $0.id == targetID }
        guard let match = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
            enqueue(operation)
            return
        }
        match.idempotencyKey = operation.idempotencyKey
        match.kindRaw = operation.kind.rawValue
        match.assetID = operation.assetID
        match.workspaceID = operation.workspaceID
        match.payload = operation.payload
        match.attemptCount = operation.attemptCount
        match.lastError = operation.lastError
        try? context.save()
    }

    public func all() -> [WriteOperation] {
        let descriptor = FetchDescriptor<PersistedWriteOperation>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.compactMap(\.asWriteOperation)
    }
}
#endif
