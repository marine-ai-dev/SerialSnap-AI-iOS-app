import XCTest
@testable import Assets
import Core
import Sync
import Parsing

final class AssetStoreTests: XCTestCase {
    func makeStore() -> (AssetStore, InMemoryAssetLocalStore, InMemoryWriteQueueStore) {
        let local = InMemoryAssetLocalStore()
        let queue = InMemoryWriteQueueStore()
        return (AssetStore(localStore: local, writeQueue: queue), local, queue)
    }

    func testCandidateBuiltFromExtractedFields() {
        let (store, _, _) = makeStore()
        let fields = ExtractedFields(
            manufacturer: ParsedField(value: "HP", confidence: .high, hadExplicitLabel: true),
            serialNumber: ParsedField(value: "SN123", confidence: .high, hadExplicitLabel: true),
            overallConfidence: .high
        )
        let candidate = store.makeCandidate(from: fields, workspaceID: "w1", userID: "u1")
        XCTAssertEqual(candidate.manufacturer, "HP")
        XCTAssertEqual(candidate.serialNumber, "SN123")
        XCTAssertEqual(candidate.confidence, .high)
        XCTAssertEqual(candidate.syncStatus, .pendingCreate)
    }

    func testFindDuplicatesDetectsSameSerialInWorkspace() {
        let (store, local, _) = makeStore()
        let existing = Asset(id: "1", workspaceID: "w1", serialNumber: "DUPLICATE-1", createdByUserID: "u1")
        local.save(existing)
        let candidate = Asset(id: "2", workspaceID: "w1", serialNumber: "duplicate-1", createdByUserID: "u1")

        let duplicates = store.findDuplicates(of: candidate)
        XCTAssertEqual(duplicates.map(\.id), ["1"])
    }

    func testFindDuplicatesIgnoresOtherWorkspaces() {
        let (store, local, _) = makeStore()
        local.save(Asset(id: "1", workspaceID: "w2", serialNumber: "SN1", createdByUserID: "u1"))
        let candidate = Asset(id: "2", workspaceID: "w1", serialNumber: "SN1", createdByUserID: "u1")

        XCTAssertTrue(store.findDuplicates(of: candidate).isEmpty)
    }

    func testSaveEnqueuesCreateOperationOnFirstRevision() {
        let (store, local, queue) = makeStore()
        let asset = Asset(id: "1", workspaceID: "w1", serialNumber: "SN1", createdByUserID: "u1")

        store.save(asset, revision: 0)

        XCTAssertEqual(local.all(workspaceID: "w1").count, 1)
        XCTAssertEqual(queue.all().count, 1)
        XCTAssertEqual(queue.all().first?.kind, .create)
    }

    func testSaveEnqueuesUpdateOperationOnLaterRevision() {
        let (store, _, queue) = makeStore()
        let asset = Asset(id: "1", workspaceID: "w1", serialNumber: "SN1", createdByUserID: "u1")

        store.save(asset, revision: 1)

        XCTAssertEqual(queue.all().first?.kind, .update)
    }

    func testDeleteSoftDeletesLocallyAndEnqueuesDeleteOp() {
        let (store, local, queue) = makeStore()
        let asset = Asset(id: "1", workspaceID: "w1", serialNumber: "SN1", createdByUserID: "u1")
        local.save(asset)

        store.delete(asset, revision: 2)

        XCTAssertTrue(local.all(workspaceID: "w1").isEmpty) // soft-deleted, filtered out
        XCTAssertEqual(queue.all().first?.kind, .delete)
    }

    func testSearchMatchesAcrossFields() {
        let (store, local, _) = makeStore()
        local.save(Asset(id: "1", workspaceID: "w1", manufacturer: "HP", model: "M404", serialNumber: "AAA111", createdByUserID: "u1"))
        local.save(Asset(id: "2", workspaceID: "w1", manufacturer: "Dell", model: "X1", serialNumber: "BBB222", createdByUserID: "u1"))

        XCTAssertEqual(store.search("hp", in: "w1").map(\.id), ["1"])
        XCTAssertEqual(store.search("bbb222", in: "w1").map(\.id), ["2"])
        XCTAssertEqual(Set(store.search("", in: "w1").map(\.id)), ["1", "2"])
    }
}
