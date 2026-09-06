import SwiftUI
import AppAuth
import Workspace
import Settings
import Localization
import DesignSystem

struct SettingsScreen: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @StateObject private var viewModel: SettingsViewModelBox

    init() {
        _viewModel = StateObject(wrappedValue: SettingsViewModelBox())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label(L10n.Settings.account, systemImage: "person.circle")
                    }
                    NavigationLink {
                        WorkspaceSelectView()
                    } label: {
                        Label(L10n.Settings.workspace, systemImage: "person.3")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(L10n.Settings.language, systemImage: "globe")
                    }
                    .foregroundStyle(SSColor.primaryText)
                    NavigationLink {
                        PrivacyInfoView()
                    } label: {
                        Label(L10n.Settings.privacy, systemImage: "hand.raised")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label(L10n.Settings.about, systemImage: "info.circle")
                    }
                }

                Section {
                    Button(L10n.Settings.signOut) {
                        Task { await authSession.signOut() }
                    }
                    .accessibilityLabel(L10n.Settings.signOut)
                    Button(L10n.Settings.deleteAccount, role: .destructive) {
                        viewModel.model?.requestDeleteAccount()
                    }
                    .accessibilityLabel(L10n.Settings.deleteAccount)
                    .accessibilityHint("Permanently deletes your account after confirmation")
                }
            }
            .navigationTitle(L10n.Settings.title)
            .onAppear { viewModel.bind(to: authSession) }
            .alert(
                L10n.Settings.deleteAccount,
                isPresented: Binding(
                    get: { viewModel.model?.isDeleteAccountConfirmationPresented ?? false },
                    set: { _ in }
                )
            ) {
                Button(L10n.Common.cancel, role: .cancel) { viewModel.model?.cancelDeleteAccount() }
                Button(L10n.Settings.deleteAccount, role: .destructive) {
                    Task { await viewModel.model?.confirmDeleteAccount() }
                }
            } message: {
                Text(L10n.Settings.deleteAccountConfirm)
            }
        }
    }
}

// MARK: - Account sub-screen

private struct AccountView: View {
    @EnvironmentObject private var authSession: AuthSessionStore

    var body: some View {
        Form {
            Section {
                if case .signedIn(let user) = authSession.state {
                    if let name = user.displayName {
                        LabeledContent("Name", value: name)
                            .accessibilityLabel("Name: \(name)")
                    }
                    if let email = user.email {
                        LabeledContent("Email", value: email)
                            .accessibilityLabel("Email: \(email)")
                    }
                    LabeledContent("User ID", value: String(user.id.prefix(8)) + "…")
                        .font(SSFont.monospacedValue)
                        .accessibilityLabel("User ID")
                }
            }
        }
        .navigationTitle(L10n.Settings.account)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy info sub-screen

private struct PrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy")
                    .font(SSFont.title)
                    .padding(.bottom, 4)
                Group {
                    Text("**On-device processing**")
                    Text("SerialSnap performs all OCR and barcode scanning on your device. No images or video are uploaded to any server.")
                    Text("**Data sync**")
                    Text("Asset records you create (serial numbers, model numbers, notes) are synced to your account so you can access them across your devices.")
                    Text("**No tracking**")
                    Text("SerialSnap does not use any advertising SDKs or cross-app tracking technologies.")
                    Text("**Account deletion**")
                    Text("Deleting your account permanently removes all your data from our servers. See Settings → Delete account.")
                }
                .font(SSFont.body)
                .foregroundStyle(SSColor.primaryText)
            }
            .padding()
        }
        .navigationTitle(L10n.Settings.privacy)
        .navigationBarTitleDisplayMode(.inline)
        .background(SSColor.background)
    }
}

// MARK: - About sub-screen

private struct AboutView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
                    .accessibilityLabel("App version \(appVersion)")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            Section {
                Text("SerialSnap — equipment inventory for IT teams.")
                    .font(SSFont.body)
                    .foregroundStyle(SSColor.secondaryText)
            }
        }
        .navigationTitle(L10n.Settings.about)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ViewModel box (carries lazy init requirement)

@MainActor
final class SettingsViewModelBox: ObservableObject {
    @Published private(set) var model: SettingsViewModel?

    func bind(to authSession: AuthSessionStore) {
        guard model == nil else { return }
        model = SettingsViewModel(authSession: authSession)
    }
}
