#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit
import OCR
import Parsing

public enum CaptureError: Error {
    case deviceUnavailable
    case cannotAddInput
    case cannotAddOutput
}

/// Drives an `AVCaptureSession` for the live scanner preview and captures
/// still frames on demand, handing each captured frame to `ScanPipeline`
/// for fully on-device OCR + barcode extraction. No frame or image is ever
/// written to disk or sent off-device by this type.
@MainActor
public final class CaptureSessionController: NSObject, ObservableObject {
    public let session = AVCaptureSession()
    @Published public private(set) var isRunning = false

    private let photoOutput = AVCapturePhotoOutput()
    private let pipeline = ScanPipeline()
    private var captureContinuation: CheckedContinuation<ExtractedFields, Error>?

    public override init() {
        super.init()
    }

    public func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.deviceUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CaptureError.cannotAddOutput }
        session.addOutput(photoOutput)
        session.sessionPreset = .photo
    }

    public func start() {
        guard !session.isRunning else { return }
        session.startRunning()
        isRunning = true
    }

    public func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    /// Captures one frame and returns the deterministically-extracted
    /// fields for it. The frame's `CGImage` is discarded immediately after
    /// recognition — never persisted — per the on-device, minimal-data
    /// architecture decision (see docs/ARCHITECTURE_DECISIONS.md).
    public func captureAndExtract() async throws -> ExtractedFields {
        try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CaptureSessionController: AVCapturePhotoCaptureDelegate {
    public nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            guard let continuation = self.captureContinuation else { return }
            self.captureContinuation = nil
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let cgImage = photo.cgImageRepresentation() else {
                continuation.resume(throwing: CaptureError.deviceUnavailable)
                return
            }
            do {
                let fields = try await self.pipeline.process(image: cgImage)
                continuation.resume(returning: fields)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
