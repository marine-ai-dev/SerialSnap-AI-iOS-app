#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit
import Parsing

/// Wraps Apple's on-device `VNRecognizeTextRequest`. No text or image data
/// ever leaves the device through this type — recognition runs entirely
/// on-device via Vision, per the product's cloud-first-but-on-device-OCR
/// architecture decision (see docs/ARCHITECTURE_DECISIONS.md).
public final class TextRecognizer {
    public init() {}

    /// Recognizes text lines in `image`, ordered top-to-bottom as Vision
    /// returns them, ready to hand to `Parsing.LabelParser`.
    public func recognizeLines(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false // we do deterministic parsing ourselves
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
