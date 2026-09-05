#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit

public struct BarcodeReading: Equatable {
    public let value: String
    public let symbology: String

    public init(value: String, symbology: String) {
        self.value = value
        self.symbology = symbology
    }
}

/// On-device barcode/QR detection via `VNDetectBarcodesRequest`.
public final class BarcodeRecognizer {
    public init() {}

    public func recognize(in image: CGImage) async throws -> [BarcodeReading] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let readings = observations.compactMap { obs -> BarcodeReading? in
                    guard let payload = obs.payloadStringValue else { return nil }
                    return BarcodeReading(value: payload, symbology: obs.symbology.rawValue)
                }
                continuation.resume(returning: readings)
            }
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
