import Foundation
import Core

/// Current authentication state of the app.
public enum AuthState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(User)
    case error(String)
}

/// Abstraction over the backend auth calls (Supabase Auth in production),
/// so `AuthSessionStore` and views built against it are testable without a
/// live network/Supabase project.
public protocol AuthBackend {
    /// Completes Sign in with Apple: exchanges Apple's identity token for a
    /// backend session and returns the resulting user.
    func signInWithApple(identityToken: Data, nonce: String) async throws -> User
    func signOut() async throws
    /// Permanently deletes the account and all owned data server-side.
    func deleteAccount() async throws
    /// Restores a session from securely-stored tokens at app launch, if any.
    func restoreSession() async throws -> User?
}

/// Owns the app's current auth state. iOS-only pieces (the actual
/// `ASAuthorizationController` flow, Keychain-backed token storage) are
/// implemented by the concrete `AuthBackend` supplied at app-target
/// composition time — this type contains no UIKit/AuthenticationServices
/// dependency itself so its state machine is unit-testable.
@MainActor
public final class AuthSessionStore: ObservableObject {
    @Published public private(set) var state: AuthState = .signedOut

    private let backend: AuthBackend

    public init(backend: AuthBackend) {
        self.backend = backend
    }

    public func restoreSessionIfAvailable() async {
        do {
            if let user = try await backend.restoreSession() {
                state = .signedIn(user)
            }
        } catch {
            // A failed silent restore just leaves the user signed out —
            // never surfaces as a hard error on launch.
            state = .signedOut
        }
    }

    public func signInWithApple(identityToken: Data, nonce: String) async {
        state = .signingIn
        do {
            let user = try await backend.signInWithApple(identityToken: identityToken, nonce: nonce)
            state = .signedIn(user)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func signOut() async {
        do {
            try await backend.signOut()
            state = .signedOut
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func deleteAccount() async {
        do {
            try await backend.deleteAccount()
            state = .signedOut
        } catch {
            state = .error(String(describing: error))
        }
    }
}
