import Foundation
import Core
import Auth
import Workspace

/// Placeholder backends wired into the App target for milestone 1, where
/// the goal is a compiling, navigable app shell — not a live Supabase
/// connection yet. Every method fails clearly rather than silently
/// no-opping, so it's obvious in manual testing that milestone 2's actual
/// `supabase-swift`-backed implementations haven't been wired in yet. See
/// docs/CLOUD_CONTINUATION.md for the exact next milestone that replaces
/// these.

struct NotYetImplemented: Error, CustomStringConvertible {
    var description: String { "Not implemented in milestone 1 — see docs/CLOUD_CONTINUATION.md" }
}

struct UnimplementedAuthBackend: AuthBackend {
    func signInWithApple(identityToken: Data, nonce: String) async throws -> User {
        throw NotYetImplemented()
    }
    func signOut() async throws {}
    func deleteAccount() async throws {
        throw NotYetImplemented()
    }
    func restoreSession() async throws -> User? {
        nil
    }
}

struct UnimplementedWorkspaceBackend: WorkspaceBackend {
    func createWorkspace(name: String, ownerID: UserID) async throws -> Workspace {
        throw NotYetImplemented()
    }
    func fetchWorkspaces(for userID: UserID) async throws -> [Workspace] {
        []
    }
    func fetchMemberships(workspaceID: WorkspaceID) async throws -> [WorkspaceMembership] {
        []
    }
}
