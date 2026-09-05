import Foundation

/// Deterministic, rule-based extraction of device-label fields from raw OCR
/// text lines plus an optional scanned barcode value. No ML, no LLM — just
/// keyword-anchored parsing with conservative heuristics, per product spec.
public enum LabelParser {

    // MARK: Keyword tables (checked case-insensitively, longest-first)

    static let serialKeywords = ["SERIAL NUMBER", "SERIAL NO", "SERIAL #", "SERIAL", "S/N", "SN#", "SN"]
    static let modelKeywords = ["MODEL NUMBER", "MODEL NO", "MODEL #", "MODEL", "P/N", "PN", "PART NUMBER", "PART NO"]
    static let assetKeywords = ["ASSET TAG", "ASSET ID", "ASSET NO", "ASSET #", "ASSET", "TAG #", "TAG"]

    static let knownManufacturers = [
        "HP", "HEWLETT-PACKARD", "HEWLETT PACKARD", "DELL", "LENOVO", "APPLE", "CISCO",
        "NETGEAR", "CANON", "EPSON", "BROTHER", "XEROX", "SAMSUNG", "LG", "ASUS", "ACER",
        "MICROSOFT", "LOGITECH", "TP-LINK", "TPLINK", "UBIQUITI", "SONY", "TOSHIBA", "IBM",
        "ZEBRA", "HONEYWELL", "PANASONIC",
    ]

    /// Parse OCR text (as recognized lines, top-to-bottom) plus an optional
    /// barcode payload into structured fields with per-field confidence.
    ///
    /// - Parameters:
    ///   - lines: OCR-recognized text lines, in the order Vision returned them.
    ///   - barcodeValue: A decoded barcode/QR payload from the same capture, if any.
    ///   - barcodeSymbology: e.g. "code128", "qr" — passed through untouched.
    public static func parse(lines: [String], barcodeValue: String? = nil, barcodeSymbology: String? = nil) -> ExtractedFields {
        var result = ExtractedFields(barcodeValue: barcodeValue, barcodeSymbology: barcodeSymbology)
        let cleanedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        result.serialNumber = extractField(keywords: serialKeywords, lines: cleanedLines, valueValidator: isPlausibleCode)
        result.model = extractField(keywords: modelKeywords, lines: cleanedLines, valueValidator: isPlausibleCode)
        result.assetTag = extractField(keywords: assetKeywords, lines: cleanedLines, valueValidator: isPlausibleCode)
        result.manufacturer = extractManufacturer(lines: cleanedLines)

        // Fallback: if no serial found via keyword, but exactly one line looks
        // like a bare alphanumeric code and nothing else claimed it, guess it
        // as a low-confidence serial (common on minimalist labels).
        if result.serialNumber == nil {
            let usedLines = Set([result.model?.value, result.assetTag?.value].compactMap { $0 })
            let candidates = cleanedLines.filter { isPlausibleCode($0) && !usedLines.contains($0) && !isKeywordLine($0) }
            if candidates.count == 1 {
                result.serialNumber = ParsedField(value: candidates[0], confidence: .low, hadExplicitLabel: false)
            }
        }

        // Barcode / OCR agreement logic: if a barcode was scanned and its
        // value matches (exactly, or allowing confusable-character drift)
        // the OCR-derived serial, boost confidence to .high and mark
        // corroboration. If they disagree entirely, keep OCR value but do
        // not raise confidence — the review UI should flag the mismatch.
        if let barcode = barcodeValue, var serial = result.serialNumber {
            if serial.value.caseInsensitiveCompare(barcode) == .orderedSame {
                serial.confidence = .high
                serial.barcodeCorroborated = true
                result.serialNumber = serial
            } else if AmbiguityNormalizer.matchesAllowingConfusables(serial.value, barcode) {
                serial.confidence = .high
                serial.barcodeCorroborated = true
                result.serialNumber = serial
            }
        } else if let barcode = barcodeValue, result.serialNumber == nil {
            // No OCR serial at all but we do have a barcode: use it as the
            // serial candidate at medium confidence (barcode-only source).
            result.serialNumber = ParsedField(value: barcode, confidence: .medium, hadExplicitLabel: false, barcodeCorroborated: true)
        }

        // Ambiguity alternates surfaced for user review, computed from the
        // *raw* OCR value (never auto-applied).
        if let serial = result.serialNumber, !serial.barcodeCorroborated {
            result.serialNumberAlternates = AmbiguityNormalizer.alternates(for: serial.value)
        }

        result.overallConfidence = computeOverallConfidence(result)
        return result
    }

    // MARK: - Field extraction

    private static func extractField(keywords: [String], lines: [String], valueValidator: (String) -> Bool) -> ParsedField? {
        for line in lines {
            let upper = line.uppercased()
            for keyword in keywords {
                guard let range = upper.range(of: keyword) else { continue }
                // Require a word boundary on both sides of the match so a
                // keyword's letters embedded in a longer alphanumeric token
                // (e.g. "SN12938471") are not mistaken for an explicit label —
                // only a genuine "SN:", "SN ", or line-final "SN" counts.
                if range.upperBound < upper.endIndex, upper[range.upperBound].isLetter || upper[range.upperBound].isNumber {
                    continue
                }
                if range.lowerBound > upper.startIndex {
                    let before = upper.index(before: range.lowerBound)
                    if upper[before].isLetter || upper[before].isNumber {
                        continue
                    }
                }
                // Value is whatever follows the keyword on the same line,
                // stripped of separators (":", "-", "#"), or if nothing
                // follows, the next non-empty line (two-line label layout).
                let afterKeyword = String(line[line.index(line.startIndex, offsetBy: upper.distance(from: upper.startIndex, to: range.upperBound))...])
                let cleaned = stripSeparators(afterKeyword)
                if !cleaned.isEmpty, valueValidator(cleaned) {
                    return ParsedField(value: cleaned, confidence: .high, hadExplicitLabel: true)
                }
                // Try same-line value even if validator initially rejects
                // (e.g. contains trailing punctuation) after tighter cleanup.
                let tighter = cleaned.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if !tighter.isEmpty, valueValidator(tighter) {
                    return ParsedField(value: tighter, confidence: .high, hadExplicitLabel: true)
                }
                if let idx = lines.firstIndex(of: line), idx + 1 < lines.count {
                    let next = lines[idx + 1]
                    if valueValidator(next), !isKeywordLine(next) {
                        return ParsedField(value: next, confidence: .medium, hadExplicitLabel: true)
                    }
                }
            }
        }
        return nil
    }

    private static func extractManufacturer(lines: [String]) -> ParsedField? {
        for line in lines {
            let upper = line.uppercased()
            for brand in knownManufacturers {
                if upper.contains(brand) {
                    return ParsedField(value: brand.capitalized, confidence: .high, hadExplicitLabel: true)
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func stripSeparators(_ s: String) -> String {
        var result = s
        while let first = result.first, [":", "-", "#", "="].contains(first) || first.isWhitespace {
            result.removeFirst()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isKeywordLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        return (serialKeywords + modelKeywords + assetKeywords).contains { upper == $0 }
    }

    /// A plausible device code: 3-40 chars, a single token (no embedded
    /// whitespace — device identifiers don't contain spaces; a multi-word
    /// line is descriptive text, not a code) built from alphanumerics plus
    /// internal hyphens/slashes/dots, containing at least one digit or at
    /// least 4 letters (rules out stray English words like "Model:" leftovers).
    static func isPlausibleCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 40 else { return false }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-/."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let hasDigit = trimmed.contains { $0.isNumber }
        let letterCount = trimmed.filter { $0.isLetter }.count
        return hasDigit || letterCount >= 4
    }

    // MARK: - Confidence scoring

    private static func computeOverallConfidence(_ fields: ExtractedFields) -> ParsedConfidence {
        let confidences = [fields.manufacturer?.confidence, fields.model?.confidence, fields.serialNumber?.confidence, fields.assetTag?.confidence].compactMap { $0 }
        guard !confidences.isEmpty else { return .low }
        // Overall confidence is driven primarily by the serial number since
        // it is the most safety-critical field for duplicate detection.
        if let serialConfidence = fields.serialNumber?.confidence {
            return serialConfidence
        }
        return confidences.min() ?? .low
    }
}
