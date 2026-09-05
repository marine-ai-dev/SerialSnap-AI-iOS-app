import Foundation

/// Confidence level for a single extracted field. Deliberately independent
/// from `Core.FieldConfidence` — this module has zero dependencies, pure
/// Swift only — but the two enums are designed to map 1:1 at call sites.
public enum ParsedConfidence: String, Codable, Equatable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
    public static func < (lhs: ParsedConfidence, rhs: ParsedConfidence) -> Bool { lhs.rank < rhs.rank }
}

/// One extracted field value plus how it was derived.
public struct ParsedField: Codable, Equatable, Sendable {
    public var value: String
    public var confidence: ParsedConfidence
    /// True when an explicit label keyword (e.g. "S/N:") preceded the value.
    public var hadExplicitLabel: Bool
    /// True when this value was also corroborated by a scanned barcode.
    public var barcodeCorroborated: Bool

    public init(value: String, confidence: ParsedConfidence, hadExplicitLabel: Bool, barcodeCorroborated: Bool = false) {
        self.value = value
        self.confidence = confidence
        self.hadExplicitLabel = hadExplicitLabel
        self.barcodeCorroborated = barcodeCorroborated
    }
}

/// The full result of parsing one OCR text block (+ optional barcode read)
/// into deterministic device-label fields.
public struct ExtractedFields: Codable, Equatable, Sendable {
    public var manufacturer: ParsedField?
    public var model: ParsedField?
    public var serialNumber: ParsedField?
    public var assetTag: ParsedField?
    public var barcodeValue: String?
    public var barcodeSymbology: String?
    /// Alternate readings worth surfacing to the user for ambiguous OCR
    /// characters (e.g. serial "S0MEC0DE" also plausible as "SOMECODE").
    public var serialNumberAlternates: [String]
    /// Overall confidence — the minimum of the confidences of the fields
    /// that were found, or `.low` if nothing was found at all.
    public var overallConfidence: ParsedConfidence

    public init(
        manufacturer: ParsedField? = nil,
        model: ParsedField? = nil,
        serialNumber: ParsedField? = nil,
        assetTag: ParsedField? = nil,
        barcodeValue: String? = nil,
        barcodeSymbology: String? = nil,
        serialNumberAlternates: [String] = [],
        overallConfidence: ParsedConfidence = .low
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.assetTag = assetTag
        self.barcodeValue = barcodeValue
        self.barcodeSymbology = barcodeSymbology
        self.serialNumberAlternates = serialNumberAlternates
        self.overallConfidence = overallConfidence
    }

    public var isEmpty: Bool {
        manufacturer == nil && model == nil && serialNumber == nil && assetTag == nil && barcodeValue == nil
    }
}
