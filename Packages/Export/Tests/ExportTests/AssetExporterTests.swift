import XCTest
@testable import Export
import Core

final class AssetExporterTests: XCTestCase {
    func makeAsset(id: String = "1", serial: String? = "SN1", notes: String? = nil) -> Asset {
        Asset(id: id, workspaceID: "w1", manufacturer: "HP", model: "M1", serialNumber: serial, notes: notes, createdByUserID: "u1")
    }

    func testCSVHeaderAndStableColumnOrder() {
        let csv = AssetExporter.csv(for: [])
        XCTAssertEqual(csv, AssetExporter.csvColumns.joined(separator: ","))
    }

    func testCSVEscapesCommas() {
        let asset = makeAsset(notes: "has, a comma")
        let csv = AssetExporter.csv(for: [asset])
        XCTAssertTrue(csv.contains("\"has, a comma\""))
    }

    func testCSVEscapesQuotes() {
        let asset = makeAsset(notes: "has \"quotes\" inside")
        let csv = AssetExporter.csv(for: [asset])
        XCTAssertTrue(csv.contains("\"has \"\"quotes\"\" inside\""))
    }

    func testCSVEscapesNewlines() {
        let asset = makeAsset(notes: "line1\nline2")
        let csv = AssetExporter.csv(for: [asset])
        XCTAssertTrue(csv.contains("\"line1\nline2\""))
    }

    func testCSVExcludesDeletedAssets() {
        var asset = makeAsset()
        asset.isDeleted = true
        let csv = AssetExporter.csv(for: [asset])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 1) // header only
    }

    func testCSVIsUTF8Encodable() {
        let asset = makeAsset(notes: "café ünïcödé")
        let data = AssetExporter.csvData(for: [asset])
        XCTAssertNotNil(String(data: data, encoding: .utf8))
    }

    func testJSONRoundTripsAssetFields() throws {
        let asset = makeAsset()
        let data = try AssetExporter.jsonData(for: [asset])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["schemaVersion"] as? Int, 1)
        let assets = json?["assets"] as? [[String: Any]]
        XCTAssertEqual(assets?.count, 1)
        XCTAssertEqual(assets?.first?["serialNumber"] as? String, "SN1")
    }

    func testJSONExcludesDeletedAssets() throws {
        var asset = makeAsset()
        asset.isDeleted = true
        let data = try AssetExporter.jsonData(for: [asset])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let assets = json?["assets"] as? [[String: Any]]
        XCTAssertEqual(assets?.count, 0)
    }
}
