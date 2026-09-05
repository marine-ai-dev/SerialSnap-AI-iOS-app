import XCTest
@testable import Core

final class ModelsTests: XCTestCase {
    func testAssetDuplicateBySerial() {
        let a = Asset(id: "1", workspaceID: "w1", serialNumber: "ABC-123", createdByUserID: "u1")
        let b = Asset(id: "2", workspaceID: "w1", serialNumber: "abc 123", createdByUserID: "u1")
        XCTAssertTrue(a.isProbableDuplicate(of: b))
    }

    func testAssetNotDuplicateAcrossWorkspaces() {
        let a = Asset(id: "1", workspaceID: "w1", serialNumber: "ABC-123", createdByUserID: "u1")
        let b = Asset(id: "2", workspaceID: "w2", serialNumber: "ABC-123", createdByUserID: "u1")
        XCTAssertFalse(a.isProbableDuplicate(of: b))
    }

    func testAssetDuplicateByTagFallback() {
        let a = Asset(id: "1", workspaceID: "w1", assetTag: "TAG-001", createdByUserID: "u1")
        let b = Asset(id: "2", workspaceID: "w1", assetTag: "tag001", createdByUserID: "u1")
        XCTAssertTrue(a.isProbableDuplicate(of: b))
    }

    func testConfidenceOrdering() {
        XCTAssertTrue(FieldConfidence.low < .medium)
        XCTAssertTrue(FieldConfidence.medium < .high)
    }

    func testCodableRoundTrip() throws {
        let asset = Asset(id: "1", workspaceID: "w1", manufacturer: "HP", model: "X1", serialNumber: "S1", createdByUserID: "u1")
        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(Asset.self, from: data)
        XCTAssertEqual(asset, decoded)
    }
}
