import Foundation
import Core

/// Abstraction over the backend workspace endpoints, so `WorkspaceStore` is
/// unit-testable against a fake without a live Supabase project.
public protocol WorkspaceBackend {
    func createWorkspace(name: String, ownerID: UserID) async throws -> Workspace
    func fetchWorkspaces(for userID: UserID) async throws -> [Workspace]
    func fetchMemberships(workspaceID: WorkspaceID) async throws -> [WorkspaceMembership]
}

public enum WorkspaceError: Error, Equatable {
    case invalidName
    case backend(String)
}

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var selectedWorkspaceID: WorkspaceID?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: WorkspaceError?

    private let backend: WorkspaceBackend

    public init(backend: WorkspaceBackend) {
        self.backend = backend
    }

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    public func loadWorkspaces(for userID: UserID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            workspaces = try await backend.fetchWorkspaces(for: userID)
            if selectedWorkspaceID == nil {
                selectedWorkspaceID = workspaces.first?.id
            }
        } catch {
            lastError = .backend(String(describing: error))
        }
    }

    @discardableResult
    public func createWorkspace(name: String, ownerID: UserID) async -> Workspace? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = .invalidName
            return nil
        }
        do {
            let workspace = try await backend.createWorkspace(name: trimmed, ownerID: ownerID)
            workspaces.append(workspace)
            selectedWorkspaceID = workspace.id
            return workspace
        } catch {
            lastError = .backend(String(describing: error))
            return nil
        }
    }

    public func select(workspaceID: WorkspaceID) {
        selectedWorkspaceID = workspaceID
    }

#if DEBUG
    /// Injects a stub workspace — only for Simulator QA without a real Supabase project.
    public func debugSelectStubWorkspace() {
        let stub = Workspace(
            id: "debug-workspace-00000000",
            name: "Debug Workspace",
            ownerID: "debug-user-00000000"
        )
        workspaces = [stub]
        selectedWorkspaceID = stub.id
    }
#endif
}
