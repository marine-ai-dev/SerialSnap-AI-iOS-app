import Foundation
import Core
import Auth
import Workspace

/// Milestone 1 placeholder backends. As of milestone 2,
/// `App/AppDependencies.swift` wires the real `SupabaseAuthBackend` /
/// `SupabaseWorkspaceBackend` (see `Packages/Auth`, `Packages/Workspace`)
/// into the running app — these are no longer used there. Kept in the repo
/// (rather than deleted) as a lightweight, network-free `AuthBackend` /
/// `WorkspaceBackend` pair for SwiftUI Previews or ad hoc manual testing of
/// screens in isolation, where spinning up a real Supabase session isn't
/// wanted. Every method still fails clearly rather than silently
/// no-opping, so accidentally using one of these in place of the real
/// backend is obvious immediately.

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
