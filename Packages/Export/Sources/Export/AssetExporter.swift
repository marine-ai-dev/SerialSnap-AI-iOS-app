import Foundation
import Core

/// Exports assets to CSV or JSON. Pure Swift, no framework dependency
/// beyond Foundation — callers hand the resulting Data/String to a
/// ShareLink or write it to a temp file.
public enum AssetExporter {

    /// Stable column order — do not reorder without a schema/version bump,
    /// since exported files may be re-imported or diffed by users.
    public static let csvColumns = [
        "id", "manufacturer", "model", "serialNumber", "assetTag",
        "barcodeValue", "barcodeSymbology", "notes", "confidence",
        "createdAt", "updatedAt",
    ]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - CSV

    /// Produces RFC 4180-style CSV, UTF-8 encoded, with a header row.
    /// Fields containing a comma, double quote, or newline are quoted, and
    /// embedded double quotes are doubled per RFC 4180.
    public static func csv(for assets: [Asset]) -> String {
        var lines: [String] = [csvColumns.map(csvEscape).joined(separator: ",")]
        for asset in assets.filter({ !$0.isDeleted }) {
            let row: [String] = [
                asset.id,
                asset.manufacturer ?? "",
                asset.model ?? "",
                asset.serialNumber ?? "",
                asset.assetTag ?? "",
                asset.barcodeValue ?? "",
                asset.barcodeSymbology ?? "",
                asset.notes ?? "",
                asset.confidence.rawValue,
                isoFormatter.string(from: asset.createdAt),
                isoFormatter.string(from: asset.updatedAt),
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    public static func csvData(for assets: [Asset]) -> Data {
        Data(csv(for: assets).utf8)
    }

    private static func csvEscape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - JSON

    private struct ExportEnvelope: Codable {
        let schemaVersion: Int
        let exportedAt: String
        let assets: [Asset]
    }

    /// Stable-schema JSON export: a versioned envelope wrapping the asset
    /// array, so future schema changes can be detected by consumers.
    public static func jsonData(for assets: [Asset]) throws -> Data {
        let envelope = ExportEnvelope(
            schemaVersion: 1,
            exportedAt: isoFormatter.string(from: Date()),
            assets: assets.filter { !$0.isDeleted }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}
