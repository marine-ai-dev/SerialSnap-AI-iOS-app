#if canImport(AVFoundation)
import AVFoundation

/// The states the Scanner screen must render distinctly, per the product
/// spec's "scanner (with permission states)" requirement.
public enum CameraPermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public enum CameraPermission {
    public static func currentState() -> CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// Requests camera access if not yet determined. Returns the resulting
    /// state (never blocks on an already-decided permission).
    @discardableResult
    public static func requestAccessIfNeeded() async -> CameraPermissionState {
        let current = currentState()
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}
#endif
