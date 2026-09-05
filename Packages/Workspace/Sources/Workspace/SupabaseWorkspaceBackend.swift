import Foundation
import Core
import SupabaseKit

/// Real, production `WorkspaceBackend` backed by Supabase PostgREST,
/// matching the schema in
/// `supabase/migrations/20260901000001_initial_schema.sql`. Every request
/// goes through the anon key and is therefore fully subject to the Row
/// Level Security policies in
/// `supabase/migrations/20260901000002_row_level_security.sql` — this type
/// never attempts to enforce tenant isolation itself (see
/// docs/SECURITY.md). In particular `fetchWorkspaces` issues an
/// unfiltered `SELECT` on `workspaces`: RLS, not a client-side `WHERE`, is
/// what actually restricts the result to workspaces the caller belongs to.
public final class SupabaseWorkspaceBackend: WorkspaceBackend {
    private let gateway: SupabaseGateway

    private static let workspacesTable = "workspaces"
    private static let membershipsTable = "workspace_memberships"

    public init(gateway: SupabaseGateway) {
        self.gateway = gateway
    }

    public func createWorkspace(name: String, ownerID: UserID) async throws -> Core.Workspace {
        let row = try await gateway.insert(
            table: Self.workspacesTable,
            values: WorkspaceInsertRow(name: name, ownerID: ownerID),
            returning: WorkspaceRow.self
        )
        return row.asCoreWorkspace
    }

    public func fetchWorkspaces(for userID: UserID) async throws -> [Core.Workspace] {
        // Deliberately unfiltered: RLS restricts this to workspaces the
        // caller (the current `auth.uid()`, which must equal `userID` for a
        // legitimately-authenticated caller) is a member of. `userID` is
        // accepted to satisfy the `WorkspaceBackend` protocol and to keep
        // the call self-documenting, not used as a client-side filter.
        let rows: [WorkspaceRow] = try await gateway.select(table: Self.workspacesTable, as: WorkspaceRow.self)
        return rows.map(\.asCoreWorkspace)
    }

    public func fetchMemberships(workspaceID: WorkspaceID) async throws -> [WorkspaceMembership] {
        let rows: [WorkspaceMembershipRow] = try await gateway.select(
            table: Self.membershipsTable,
            filters: [PGFilter("workspace_id", eq: workspaceID)],
            as: WorkspaceMembershipRow.self
        )
        return rows.map(\.asCoreMembership)
    }
}

// MARK: - Row DTOs

/// Matches `public.workspaces` (see initial schema migration). Field names
/// use `snake_case` `CodingKeys` to match PostgREST's JSON column naming.
private struct WorkspaceRow: Decodable {
    let id: String
    let name: String
    let ownerID: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var asCoreWorkspace: Core.Workspace {
        Core.Workspace(id: id, name: name, ownerID: ownerID, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Insert payload for `POST /rest/v1/workspaces` — only client-supplied
/// columns; `id`/`created_at`/`updated_at` are server defaults, and the
/// `handle_new_workspace` trigger auto-adds the creator as an `owner`
/// member (see the initial schema migration).
private struct WorkspaceInsertRow: Encodable {
    let name: String
    let ownerID: String

    enum CodingKeys: String, CodingKey {
        case name
        case ownerID = "owner_id"
    }
}

/// Matches `public.workspace_memberships`.
private struct WorkspaceMembershipRow: Decodable {
    let id: String
    let workspaceID: String
    let userID: String
    let role: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case userID = "user_id"
        case role
        case createdAt = "created_at"
    }

    var asCoreMembership: WorkspaceMembership {
        WorkspaceMembership(
            id: id,
            workspaceID: workspaceID,
            userID: userID,
            role: WorkspaceRole(rawValue: role) ?? .member,
            createdAt: createdAt
        )
    }
}
