import SwiftUI
import Scanner
import Localization
import DesignSystem

/// Scanner screen skeleton covering all required permission states. The
/// live `AVCaptureSession` preview + capture loop (via
/// `Scanner.CaptureSessionController`) is wired in milestone 2 — see
/// docs/CLOUD_CONTINUATION.md for the exact next step.
struct ScannerScreen: View {
    @State private var permissionState: CameraPermissionState = .notDetermined

    var body: some View {
        NavigationStack {
            Group {
                switch permissionState {
                case .notDetermined:
                    ProgressView().task { permissionState = await CameraPermission.requestAccessIfNeeded() }
                case .authorized:
                    CameraReadyPlaceholder()
                case .denied, .restricted:
                    PermissionDeniedView()
                }
            }
            .navigationTitle(L10n.Scanner.title)
        }
    }
}

private struct CameraReadyPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.accent)
            Text(L10n.Scanner.title)
                .font(SSFont.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.warning)
            Text(L10n.Scanner.permissionDeniedTitle)
                .font(SSFont.headline)
            Text(L10n.Scanner.permissionDeniedMessage)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(L10n.Scanner.openSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}
