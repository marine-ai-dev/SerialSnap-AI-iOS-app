import AuthenticationServices
import SwiftUI
import AppAuth
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
            ProgressView("Signing in…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SSColor.background)
                .accessibilityLabel("Signing in, please wait")
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

    /// The error to surface: local sign-in error takes priority over an
    /// auth-state error so we don't show a stale error after a new attempt.
    private var effectiveError: String? {
        if let e = signInError { return e }
        if case .error(let msg) = authSession.state, !msg.isEmpty { return msg }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(SSColor.accent)
                .accessibilityHidden(true)
            Text(L10n.Onboarding.welcomeTitle)
                .font(SSFont.title)
                .multilineTextAlignment(.center)
            Text(L10n.Onboarding.welcomeSubtitle)
                .font(SSFont.body)
                .foregroundStyle(SSColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let err = effectiveError {
                Text(err)
                    .font(SSFont.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Sign-in error: \(err)")
            }
#if DEBUG
            Button("Debug: Skip Auth") {
                authSession.debugSignIn()
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Debug: bypass authentication")
#endif
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
                        // ASAuthorizationError.canceled = user dismissed the sheet — not an error.
                        if (error as? ASAuthorizationError)?.code == .canceled { return }
                        // .notHandled / .invalidResponse / .failed / .notInteractive:
                        // all other ASAuthorizationError codes are real failures worth surfacing.
                        signInError = (error as? ASAuthorizationError)?.localizedDescription
                            ?? error.localizedDescription
                    }
                }
            } label: {
                Label(L10n.Auth.signInWithApple, systemImage: "apple.logo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .accessibilityLabel(L10n.Auth.signInWithApple)
        }
        .background(SSColor.background)
    }
}

struct WorkspaceSelectView: View {
    @EnvironmentObject private var authSession: AuthSessionStore
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
                    Button(L10n.Workspace.createTitle) {
                        guard case .signedIn(let user) = authSession.state else { return }
                        Task { await workspaceStore.createWorkspace(name: newWorkspaceName, ownerID: user.id) }
                    }
                    .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
#if DEBUG
                Section("Debug") {
                    Button("Skip: Use Stub Workspace") {
                        workspaceStore.debugSelectStubWorkspace()
                    }
                    .foregroundStyle(.orange)
                }
#endif
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
