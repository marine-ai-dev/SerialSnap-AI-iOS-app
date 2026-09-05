#if canImport(Vision) && canImport(UIKit)
import UIKit
import Parsing

/// Orchestrates on-device OCR + barcode recognition, then hands both to
/// the deterministic `Parsing.LabelParser`. This is the single entry point
/// the Scanner module should call after capturing a frame.
public final class ScanPipeline {
    private let textRecognizer = TextRecognizer()
    private let barcodeRecognizer = BarcodeRecognizer()

    public init() {}

    public func process(image: CGImage) async throws -> ExtractedFields {
        async let linesTask = textRecognizer.recognizeLines(in: image)
        async let barcodesTask = barcodeRecognizer.recognize(in: image)
        let (lines, barcodes) = try await (linesTask, barcodesTask)
        let primaryBarcode = barcodes.first
        return LabelParser.parse(
            lines: lines,
            barcodeValue: primaryBarcode?.value,
            barcodeSymbology: primaryBarcode?.symbology
        )
    }
}
#endif
