import AuthenticationServices
import SwiftUI
import Auth
import Workspace
import Localization
import DesignSystem

/// Top-level navigation: onboarding/auth -> workspace select/create ->
/// main tab flow (Scanner / Assets / Settings). See docs/CLOUD_CONTINUATION.md
/// for which of these are fully wired vs. structural placeholders in
/// milestone 1.
struct RootView: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        switch authSession.state {
        case .signedOut, .error:
            OnboardingView()
        case .signingIn:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SSColor.background)
        case .signedIn:
            if workspaceStore.selectedWorkspace == nil {
                WorkspaceSelectView()
            } else {
                MainTabView()
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    @State private var coordinator = SignInWithAppleCoordinator()
    @State private var signInError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(SSColor.accent)
            Text(L10n.Onboarding.welcomeTitle)
                .font(SSFont.title)
                .multilineTextAlignment(.center)
            Text(L10n.Onboarding.welcomeSubtitle)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let signInError {
                Text(signInError)
                    .font(SSFont.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityLabel(signInError)
            }
            Spacer()
            Button {
                signInError = nil
                coordinator.signIn { result in
                    switch result {
                    case .success(let credential):
                        Task {
                            await authSession.signInWithApple(identityToken: credential.identityToken, nonce: credential.nonce)
                        }
                    case .failure(let error):
                        // ASAuthorizationError.canceled is the user dismissing
                        // the system sheet — not an error worth surfacing.
                        if (error as? ASAuthorizationError)?.code == .canceled { return }
                        signInError = String(describing: error)
                    }
                }
            } label: {
                Label(L10n.Auth.signInWithApple, systemImage: "apple.logo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(SSColor.background)
    }
}

struct WorkspaceSelectView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var newWorkspaceName = ""

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.Workspace.selectTitle) {
                    ForEach(workspaceStore.workspaces) { workspace in
                        Button(workspace.name) {
                            workspaceStore.select(workspaceID: workspace.id)
                        }
                    }
                }
                Section(L10n.Workspace.createTitle) {
                    TextField(L10n.Workspace.namePlaceholder, text: $newWorkspaceName)
                }
            }
            .navigationTitle(L10n.Workspace.selectTitle)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ScannerScreen()
                .tabItem { Label(L10n.Scanner.title, systemImage: "camera.viewfinder") }
            AssetListScreen()
                .tabItem { Label(L10n.AssetsList.title, systemImage: "list.bullet.rectangle") }
            SettingsScreen()
                .tabItem { Label(L10n.Settings.title, systemImage: "gearshape") }
        }
    }
}
