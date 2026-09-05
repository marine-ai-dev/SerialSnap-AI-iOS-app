import XCTest
@testable import Sync
import Core

final class FakeRemoteAssetService: RemoteAssetService {
    var submittedIdempotencyKeys: [String] = []
    var failNextNCalls: Int = 0
    var recordsByAssetID: [AssetID: RemoteAssetRecord] = [:]
    /// Tracks how many *distinct* asset records exist server-side per
    /// idempotency key, to prove retries never create duplicates.
    private var seenKeys: Set<String> = []

    func submit(_ operation: WriteOperation) async throws -> RemoteAssetRecord {
        submittedIdempotencyKeys.append(operation.idempotencyKey)
        if failNextNCalls > 0 {
            failNextNCalls -= 1
            throw SyncError.network("simulated failure")
        }
        // Idempotent: if we've already applied this key, return the
        // existing record rather than creating a new one.
        if seenKeys.contains(operation.idempotencyKey), let existing = recordsByAssetID[operation.assetID] {
            return existing
        }
        seenKeys.insert(operation.idempotencyKey)
        let record = RemoteAssetRecord(assetID: operation.assetID, updatedAt: Date(), payload: operation.payload, isDeleted: operation.kind == .delete)
        recordsByAssetID[operation.assetID] = record
        return record
    }

    func fetchAll(workspaceID: WorkspaceID) async throws -> [RemoteAssetRecord] {
        Array(recordsByAssetID.values)
    }
}

final class SyncEngineTests: XCTestCase {

    func testIdempotencyKeyIsStableForSameRevision() {
        let k1 = IdempotencyKeyGenerator.makeKey(assetID: "a1", kind: .create, revision: 1)
        let k2 = IdempotencyKeyGenerator.makeKey(assetID: "a1", kind: .create, revision: 1)
        XCTAssertEqual(k1, k2)
    }

    func testIdempotencyKeyChangesForNewRevision() {
        let k1 = IdempotencyKeyGenerator.makeKey(assetID: "a1", kind: .update, revision: 1)
        let k2 = IdempotencyKeyGenerator.makeKey(assetID: "a1", kind: .update, revision: 2)
        XCTAssertNotEqual(k1, k2)
    }

    func testSuccessfulFlushRemovesOperationFromQueue() async {
        let store = InMemoryWriteQueueStore()
        let remote = FakeRemoteAssetService()
        let engine = SyncEngine(store: store, remote: remote)
        let op = WriteOperation(idempotencyKey: "a1_create_1", kind: .create, assetID: "a1", workspaceID: "w1", payload: nil)
        store.enqueue(op)

        let summary = await engine.flush()
        XCTAssertEqual(summary.succeeded, 1)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testRetryAfterTransientFailureEventuallySucceedsWithoutDuplication() async {
        let store = InMemoryWriteQueueStore()
        let remote = FakeRemoteAssetService()
        remote.failNextNCalls = 2
        let engine = SyncEngine(store: store, remote: remote, maxAttempts: 5)
        let op = WriteOperation(idempotencyKey: "a1_create_1", kind: .create, assetID: "a1", workspaceID: "w1", payload: nil)
        store.enqueue(op)

        var summary = await engine.flush()
        XCTAssertEqual(summary.retriableFailures, 1)
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.attemptCount, 1)

        summary = await engine.flush()
        XCTAssertEqual(summary.retriableFailures, 1)

        summary = await engine.flush()
        XCTAssertEqual(summary.succeeded, 1)
        XCTAssertTrue(store.all().isEmpty)

        // All three attempts used the SAME idempotency key.
        XCTAssertEqual(Set(remote.submittedIdempotencyKeys).count, 1)
        // Only one server-side record exists despite 3 submit calls.
        XCTAssertEqual(remote.recordsByAssetID.count, 1)
    }

    func testOperationMarkedPermanentlyFailedAfterMaxAttemptsButNeverDropped() async {
        let store = InMemoryWriteQueueStore()
        let remote = FakeRemoteAssetService()
        remote.failNextNCalls = 100
        let engine = SyncEngine(store: store, remote: remote, maxAttempts: 3)
        let op = WriteOperation(idempotencyKey: "a1_create_1", kind: .create, assetID: "a1", workspaceID: "w1", payload: nil)
        store.enqueue(op)

        _ = await engine.flush()
        _ = await engine.flush()
        let summary = await engine.flush()

        XCTAssertEqual(summary.permanentFailures, 1)
        // The operation is still in the queue — never silently lost.
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.attemptCount, 3)
    }

    func testConflictResolutionLastWriteWinsLocalNewer() {
        let remote = RemoteAssetRecord(assetID: "a1", updatedAt: Date(timeIntervalSince1970: 100), payload: nil)
        let resolution = ConflictResolver.resolve(localUpdatedAt: Date(timeIntervalSince1970: 200), remote: remote)
        XCTAssertEqual(resolution, .applyLocal)
    }

    func testConflictResolutionLastWriteWinsRemoteNewer() {
        let remote = RemoteAssetRecord(assetID: "a1", updatedAt: Date(timeIntervalSince1970: 300), payload: nil)
        let resolution = ConflictResolver.resolve(localUpdatedAt: Date(timeIntervalSince1970: 200), remote: remote)
        XCTAssertEqual(resolution, .adoptRemote(remote))
    }

    func testConflictResolutionTieFavorsRemote() {
        let t = Date(timeIntervalSince1970: 500)
        let remote = RemoteAssetRecord(assetID: "a1", updatedAt: t, payload: nil)
        let resolution = ConflictResolver.resolve(localUpdatedAt: t, remote: remote)
        XCTAssertEqual(resolution, .adoptRemote(remote))
    }

    func testMultipleQueuedOperationsForDifferentAssetsAllFlush() async {
        let store = InMemoryWriteQueueStore()
        let remote = FakeRemoteAssetService()
        let engine = SyncEngine(store: store, remote: remote)
        store.enqueue(WriteOperation(idempotencyKey: "a1_create_1", kind: .create, assetID: "a1", workspaceID: "w1", payload: nil))
        store.enqueue(WriteOperation(idempotencyKey: "a2_create_1", kind: .create, assetID: "a2", workspaceID: "w1", payload: nil))

        let summary = await engine.flush()
        XCTAssertEqual(summary.succeeded, 2)
        XCTAssertTrue(store.all().isEmpty)
    }
}
