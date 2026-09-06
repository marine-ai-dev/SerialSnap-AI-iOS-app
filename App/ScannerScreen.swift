import AVFoundation
import SwiftUI
import UIKit
import Scanner
import OCR
import Assets
import Parsing
import Core
import AppAuth
import Workspace
import Localization
import DesignSystem

// MARK: - Root scanner screen

struct ScannerScreen: View {
    @EnvironmentObject private var assetViewModel: AssetViewModel
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var authSession: AuthSessionStore

    @StateObject private var captureController = CaptureSessionController()
    @State private var permissionState: CameraPermissionState = .notDetermined
    @State private var reviewCandidate: ReviewCandidate?

    var body: some View {
        NavigationStack {
            Group {
                switch permissionState {
                case .notDetermined:
                    ProgressView()
                        .accessibilityLabel("Requesting camera permission")
                        .task { permissionState = await CameraPermission.requestAccessIfNeeded() }
                case .authorized:
                    CameraLiveView(captureController: captureController) { fields in
                        guard let wid = workspaceStore.selectedWorkspace?.id,
                              case .signedIn(let user) = authSession.state else { return }
                        let candidate = assetViewModel.makeCandidate(from: fields, workspaceID: wid, userID: user.id)
                        let dupes = assetViewModel.findDuplicates(of: candidate)
                        reviewCandidate = ReviewCandidate(
                            asset: candidate,
                            duplicates: dupes,
                            alternates: fields.serialNumberAlternates
                        )
                    }
                case .denied, .restricted:
                    PermissionDeniedView()
                }
            }
            .navigationTitle(L10n.Scanner.title)
            .sheet(item: $reviewCandidate) { candidate in
                ReviewSheet(
                    candidate: candidate,
                    onSave: { saved in
                        assetViewModel.saveNew(saved)
                        reviewCandidate = nil
                    },
                    onDiscard: { reviewCandidate = nil }
                )
            }
        }
    }
}

// MARK: - Review state

private struct ReviewCandidate: Identifiable {
    let id = UUID()
    let asset: Asset
    let duplicates: [Asset]
    let alternates: [String]
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PreviewView { _PreviewView() }

    func updateUIView(_ uiView: _PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = .resizeAspectFill
    }

    final class _PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Live camera view

private struct CameraLiveView: View {
    @ObservedObject var captureController: CaptureSessionController
    let onCapture: (ExtractedFields) -> Void

    @State private var setupError: String?
    @State private var captureError: String?
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            if let error = setupError {
                CameraUnavailableView(message: error, onSimulate: onCapture)
            } else {
                CameraPreviewView(session: captureController.session)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let error = captureError {
                        Text(error)
                            .font(SSFont.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 8)
                            .accessibilityLabel(error)
                    }

                    captureButton
                        .padding(.bottom, 40)
                }
            }
        }
        .task {
            do {
                try captureController.configureSession()
                captureController.start()
            } catch CaptureError.deviceUnavailable {
                setupError = "Camera unavailable on this device."
            } catch {
                setupError = "Camera error: \(error.localizedDescription)"
            }
        }
        .onDisappear {
            captureController.stop()
        }
    }

    private var captureButton: some View {
        Button {
            guard !isCapturing else { return }
            isCapturing = true
            captureError = nil
            Task {
                defer { isCapturing = false }
                do {
                    let fields = try await captureController.captureAndExtract()
                    onCapture(fields)
                } catch {
                    captureError = L10n.Common.genericError
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(.white.opacity(0.45), lineWidth: 5)
                    .frame(width: 82, height: 82)
                if isCapturing {
                    ProgressView()
                        .tint(.gray)
                }
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel("Capture label")
        .accessibilityHint("Double tap to photograph the equipment label")
    }
}

// MARK: - Camera unavailable (Simulator / no back camera)

private struct CameraUnavailableView: View {
    let message: String
    let onSimulate: (ExtractedFields) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.secondaryText)
                .accessibilityHidden(true)
            Text(message)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
#if DEBUG
            Button("Simulate scan (debug only)") {
                let fixture = LabelParser.parse(
                    lines: [
                        "LENOVO",
                        "ThinkPad X1 Carbon Gen 11",
                        "S/N: PF3Z1AB2",
                        "MODEL: 21HQ004DUS",
                        "ASSET TAG: IT-00421",
                    ],
                    barcodeValue: "PF3Z1AB2",
                    barcodeSymbology: "code128"
                )
                onSimulate(fixture)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Simulate a test scan with fixture data")
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}

// MARK: - Permission denied

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(SSColor.warning)
                .accessibilityHidden(true)
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
            .accessibilityLabel(L10n.Scanner.openSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SSColor.background)
    }
}

// MARK: - Review sheet

private struct ReviewSheet: View {
    let candidate: ReviewCandidate
    let onSave: (Asset) -> Void
    let onDiscard: () -> Void

    @State private var manufacturer: String
    @State private var model: String
    @State private var serialNumber: String
    @State private var assetTag: String
    @State private var notes: String

    init(candidate: ReviewCandidate, onSave: @escaping (Asset) -> Void, onDiscard: @escaping () -> Void) {
        self.candidate = candidate
        self.onSave = onSave
        self.onDiscard = onDiscard
        _manufacturer = State(initialValue: candidate.asset.manufacturer ?? "")
        _model = State(initialValue: candidate.asset.model ?? "")
        _serialNumber = State(initialValue: candidate.asset.serialNumber ?? "")
        _assetTag = State(initialValue: candidate.asset.assetTag ?? "")
        _notes = State(initialValue: candidate.asset.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                warningsSection
                fieldsSection
                if !candidate.alternates.isEmpty {
                    alternatesSection
                }
                notesSection
            }
            .navigationTitle(L10n.Review.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { onDiscard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Review.save) { commitSave() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        Section {
            ConfidenceBadge(level: badgeLevel(candidate.asset.confidence))
                .accessibilityLabel("Confidence: \(candidate.asset.confidence.rawValue)")

            if !candidate.duplicates.isEmpty {
                Label {
                    Text(L10n.Review.duplicateWarning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel(L10n.Review.duplicateWarning)
            }

            if candidate.asset.confidence == .low || !candidate.alternates.isEmpty {
                Label {
                    Text(L10n.Review.ambiguousCharacterHint)
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.yellow)
                }
                .accessibilityLabel(L10n.Review.ambiguousCharacterHint)
            }
        }
    }

    private var fieldsSection: some View {
        Section {
            ReviewField(label: L10n.Review.manufacturer, text: $manufacturer)
            ReviewField(label: L10n.Review.model, text: $model)
            ReviewField(label: L10n.Review.serialNumber, text: $serialNumber)
            ReviewField(label: L10n.Review.assetTag, text: $assetTag)
        }
    }

    private var alternatesSection: some View {
        Section("Alternate readings") {
            ForEach(candidate.alternates, id: \.self) { (alt: String) in
                Button {
                    serialNumber = alt
                } label: {
                    HStack {
                        Text(verbatim: alt)
                            .font(SSFont.monospacedValue)
                            .foregroundStyle(SSColor.primaryText)
                        Spacer()
                        if serialNumber == alt {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel("Use alternate reading \(alt)")
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(3...)
                .accessibilityLabel("Notes")
        }
    }

    private func commitSave() {
        var saved = candidate.asset
        saved.manufacturer = manufacturer.trimmingCharacters(in: .whitespaces).nonEmpty
        saved.model = model.trimmingCharacters(in: .whitespaces).nonEmpty
        saved.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces).nonEmpty
        saved.assetTag = assetTag.trimmingCharacters(in: .whitespaces).nonEmpty
        saved.notes = notes.trimmingCharacters(in: .whitespaces).nonEmpty
        onSave(saved)
    }

    private func badgeLevel(_ c: FieldConfidence) -> ConfidenceBadge.Level {
        switch c {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

// MARK: - Review field row

private struct ReviewField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
                .font(SSFont.monospacedValue)
                .foregroundStyle(SSColor.primaryText)
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
