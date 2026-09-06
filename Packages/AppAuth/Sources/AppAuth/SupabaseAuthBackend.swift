import Foundation
import Core
import SupabaseKit

/// Real, production `AuthBackend` backed by Supabase Auth. Sign in with
/// Apple works by exchanging the identity token minted by
/// `ASAuthorizationAppleIDCredential` for a Supabase session via
/// `signInWithIdToken(credentials:)` (provider `.apple`) — see
/// `SupabaseKit.SupabaseGateway.signInWithApple` and
/// docs/ARCHITECTURE_DECISIONS.md ADR-006.
///
/// Never logs a token, nonce, or session value — see docs/SECURITY.md
/// "Secret handling". Every method here only ever forwards to
/// `SupabaseGateway`, which itself never logs those values either.
public final class SupabaseAuthBackend: AuthBackend {
    private let gateway: SupabaseGateway

    public init(gateway: SupabaseGateway) {
        self.gateway = gateway
    }

    public func signInWithApple(identityToken: Data, nonce: String) async throws -> User {
        try await gateway.signInWithApple(identityToken: identityToken, nonce: nonce).asCoreUser
    }

    public func signOut() async throws {
        try await gateway.signOut()
    }

    public func deleteAccount() async throws {
        try await gateway.deleteAccount()
    }

    public func restoreSession() async throws -> User? {
        try await gateway.restoreSession()?.asCoreUser
    }
}
