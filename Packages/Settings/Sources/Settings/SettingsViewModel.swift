import Foundation
import Core
import Auth
import Workspace

/// Non-UI state/actions backing the Settings screen (account, workspace,
/// language, privacy, about, sign out, delete account). Kept UIKit/
/// SwiftUI-free so the action wiring is unit-testable; the SwiftUI view
/// itself lives in the App target and observes `AuthSessionStore` /
/// `WorkspaceStore` directly plus this for the few settings-specific bits.
@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var isDeleteAccountConfirmationPresented = false
    @Published public var isDeleteAssetConfirmationPresented = false

    private let authSession: AuthSessionStore

    public init(authSession: AuthSessionStore) {
        self.authSession = authSession
    }

    public func requestDeleteAccount() {
        isDeleteAccountConfirmationPresented = true
    }

    public func confirmDeleteAccount() async {
        isDeleteAccountConfirmationPresented = false
        await authSession.deleteAccount()
    }

    public func cancelDeleteAccount() {
        isDeleteAccountConfirmationPresented = false
    }

    public func signOut() async {
        await authSession.signOut()
    }

    public static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }()
}
