import XCTest
@testable import Parsing

final class LabelParserTests: XCTestCase {

    func testHPStyleLabel() {
        let lines = ["HP LaserJet Pro", "Model: M404dn", "Serial Number: VNC3K12345"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Hp")
        XCTAssertEqual(result.model?.value, "M404dn")
        XCTAssertEqual(result.serialNumber?.value, "VNC3K12345")
        XCTAssertEqual(result.serialNumber?.confidence, .high)
    }

    func testDellStyleLabel() {
        let lines = ["DELL", "P/N: 0X7K2H", "S/N: 7XK2H3J"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Dell")
        XCTAssertEqual(result.model?.value, "0X7K2H")
        XCTAssertEqual(result.serialNumber?.value, "7XK2H3J")
    }

    func testLenovoStyleLabel() {
        let lines = ["Lenovo ThinkPad", "MODEL NO: 20UE001", "SN PF-1A2B3C"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Lenovo")
        XCTAssertEqual(result.model?.value, "20UE001")
        XCTAssertEqual(result.serialNumber?.value, "PF-1A2B3C")
    }

    func testPrinterLabelTwoLineLayout() {
        // Value on the line below the keyword (two-line label layout).
        let lines = ["Canon PIXMA", "SERIAL", "ABC1234567"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Canon")
        XCTAssertEqual(result.serialNumber?.value, "ABC1234567")
        XCTAssertEqual(result.serialNumber?.confidence, .medium)
    }

    func testMonitorLabel() {
        let lines = ["Samsung Electronics", "MODEL: S24R350", "SERIAL NO: H2AK300123"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Samsung")
        XCTAssertEqual(result.model?.value, "S24R350")
        XCTAssertEqual(result.serialNumber?.value, "H2AK300123")
    }

    func testRouterLabelWithAssetTag() {
        let lines = ["NETGEAR Nighthawk", "MODEL R7000", "SN: 4G1234567890", "ASSET TAG: IT-00231"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.manufacturer?.value, "Netgear")
        XCTAssertEqual(result.model?.value, "R7000")
        XCTAssertEqual(result.serialNumber?.value, "4G1234567890")
        XCTAssertEqual(result.assetTag?.value, "IT-00231")
    }

    func testUnknownManufacturerFallsBackGracefully() {
        let lines = ["AcmeCorp Widgets Inc", "S/N: ZX99887766"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertNil(result.manufacturer)
        XCTAssertEqual(result.serialNumber?.value, "ZX99887766")
    }

    func testSerialOnlyLabel() {
        let lines = ["SN12938471"]
        let result = LabelParser.parse(lines: lines)
        // No keyword marker present; single plausible bare code -> low-confidence guess.
        XCTAssertEqual(result.serialNumber?.value, "SN12938471")
        XCTAssertEqual(result.serialNumber?.confidence, .low)
        XCTAssertFalse(result.serialNumber?.hadExplicitLabel ?? true)
    }

    func testSerialPlusModelLabel() {
        let lines = ["MODEL X100", "SERIAL 998877"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.model?.value, "X100")
        XCTAssertEqual(result.serialNumber?.value, "998877")
    }

    func testSerialPlusAssetIDLabel() {
        let lines = ["S/N: AB123456", "ASSET ID: CORP-4477"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.serialNumber?.value, "AB123456")
        XCTAssertEqual(result.assetTag?.value, "CORP-4477")
    }

    func testSerialPlusBarcodeAgreementBoostsConfidence() {
        let lines = ["SN: AB12CD34"]
        let result = LabelParser.parse(lines: lines, barcodeValue: "AB12CD34", barcodeSymbology: "code128")
        XCTAssertEqual(result.serialNumber?.confidence, .high)
        XCTAssertTrue(result.serialNumber?.barcodeCorroborated ?? false)
    }

    func testSerialPlusBarcodeConfusableAgreementStillBoosts() {
        // OCR misread O as 0; barcode has the correct digit — should still
        // be treated as agreement via confusable-matching.
        let lines = ["SN: AB0CD34"]
        let result = LabelParser.parse(lines: lines, barcodeValue: "ABOCD34", barcodeSymbology: "qr")
        XCTAssertEqual(result.serialNumber?.confidence, .high)
        XCTAssertTrue(result.serialNumber?.barcodeCorroborated ?? false)
    }

    func testBarcodeOnlyNoOCRSerial() {
        let lines = ["Some Unrelated Label Text"]
        let result = LabelParser.parse(lines: lines, barcodeValue: "9988776655", barcodeSymbology: "code39")
        XCTAssertEqual(result.serialNumber?.value, "9988776655")
        XCTAssertEqual(result.serialNumber?.confidence, .medium)
    }

    func testAmbiguousOCRProducesAlternatesButDoesNotMutateOriginal() {
        let lines = ["S/N: S0B8G2"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.serialNumber?.value, "S0B8G2") // untouched
        XCTAssertFalse(result.serialNumberAlternates.isEmpty)
        XCTAssertFalse(result.serialNumberAlternates.contains("S0B8G2")) // no self-duplicate
    }

    func testEmptyInputProducesEmptyResult() {
        let result = LabelParser.parse(lines: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.overallConfidence, .low)
    }

    func testNoiseLinesAreIgnored() {
        let lines = ["", "   ", "Made in China", "SERIAL: QW345678"]
        let result = LabelParser.parse(lines: lines)
        XCTAssertEqual(result.serialNumber?.value, "QW345678")
    }
}

final class AmbiguityNormalizerTests: XCTestCase {
    func testAlternatesForSingleAmbiguousChar() {
        let alts = AmbiguityNormalizer.alternates(for: "ABC0DE")
        XCTAssertTrue(alts.contains("ABCODE"))
    }

    func testNoAlternatesWhenNoAmbiguousChars() {
        // "XYM" avoids every confusable glyph (O/0, I/1/l, S/5, B/8, Z/2, G/6) —
        // "XYZ" would not qualify since Z is itself confusable with 2.
        let alts = AmbiguityNormalizer.alternates(for: "XYM")
        XCTAssertTrue(alts.isEmpty)
    }

    func testMatchesAllowingConfusablesExactMatch() {
        XCTAssertTrue(AmbiguityNormalizer.matchesAllowingConfusables("ABC123", "ABC123"))
    }

    func testMatchesAllowingConfusablesWithSubstitution() {
        XCTAssertTrue(AmbiguityNormalizer.matchesAllowingConfusables("AB0", "ABO"))
        XCTAssertTrue(AmbiguityNormalizer.matchesAllowingConfusables("S5", "SS")) // S/5 confusable both directions? S<->5 only
    }

    func testMatchesAllowingConfusablesRejectsUnrelatedDifference() {
        XCTAssertFalse(AmbiguityNormalizer.matchesAllowingConfusables("ABC", "XYZ"))
        XCTAssertFalse(AmbiguityNormalizer.matchesAllowingConfusables("ABC", "ABCD"))
    }

    func testAmbiguousIndices() {
        let idx = AmbiguityNormalizer.ambiguousIndices(in: "A0I1")
        XCTAssertEqual(idx, [1, 2, 3])
    }
}
