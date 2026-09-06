import SwiftUI
import AppAuth
import Settings
import Localization

struct SettingsScreen: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    @StateObject private var viewModel: SettingsViewModelBox

    init() {
        // ViewModel needs authSession from the environment, which isn't
        // available at init time, so it's created lazily on first body
        // evaluation via SettingsViewModelBox. See its definition below.
        _viewModel = StateObject(wrappedValue: SettingsViewModelBox())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(L10n.Settings.account, systemImage: "person.circle")
                    Label(L10n.Settings.workspace, systemImage: "person.3")
                    Label(L10n.Settings.language, systemImage: "globe")
                    Label(L10n.Settings.privacy, systemImage: "hand.raised")
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                Section {
                    Button(L10n.Settings.signOut) {
                        Task { await authSession.signOut() }
                    }
                    Button(L10n.Settings.deleteAccount, role: .destructive) {
                        viewModel.model?.requestDeleteAccount()
                    }
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

/// Small helper so `SettingsViewModel` (which needs an `AuthSessionStore`
/// at construction time) can be created once the environment object is
/// actually available, rather than at `SettingsScreen.init()`.
@MainActor
final class SettingsViewModelBox: ObservableObject {
    @Published private(set) var model: SettingsViewModel?

    func bind(to authSession: AuthSessionStore) {
        guard model == nil else { return }
        model = SettingsViewModel(authSession: authSession)
    }
}
