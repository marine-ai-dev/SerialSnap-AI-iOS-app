import Foundation
import Core
import Supabase

/// A row equality filter for the generic PostgREST helpers below
/// (`column = value`, PostgREST's `eq` operator). Kept intentionally small
/// — every query this app makes filters on a handful of equality
/// conditions (`workspace_id`, `id`, `user_id`); there has been no need yet
/// for the fuller filter grammar PostgREST supports.
public struct PGFilter: Sendable {
    public let column: String
    public let value: String

    public init(_ column: String, eq value: String) {
        self.column = column
        self.value = value
    }
}

/// What a successful Sign in with Apple exchange (or session restore)
/// resolves to. Deliberately a plain struct, not `Auth.User` from
/// supabase-swift, so nothing outside this package ever needs to know that
/// module exists (see `Package.swift` for why it's aliased away).
public struct RemoteAuthUser: Sendable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let createdAt: Date

    public init(id: String, email: String?, displayName: String?, createdAt: Date) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }

    public var asCoreUser: Core.User {
        // Explicitly qualified: `import Supabase` transitively re-exports
        // Auth.User (the moduleAliases declared on the SupabaseKit ->
        // Supabase dependency in Package.swift does not, in practice,
        // prevent this — confirmed by a real CI compiler error, "'User' is
        // ambiguous for type lookup in this context", the first time this
        // file was actually compiled), which collides with this package's
        // own Core.User at the bare, unqualified name `User`.
        Core.User(id: id, email: email, displayName: displayName, createdAt: createdAt)
    }
}

public enum SupabaseKitError: Error, CustomStringConvertible {
    case invalidIdentityTokenEncoding
    case notSignedIn

    public var description: String {
        switch self {
        case .invalidIdentityTokenEncoding:
            return "Apple identity token was not valid UTF-8 data."
        case .notSignedIn:
            return "No active Supabase session."
        }
    }
}

/// The single point of contact with `supabase-swift` for the whole app.
/// Every other package (`Auth`, `Workspace`, `Sync`) talks to Supabase only
/// through this type's plain-Swift API — never by importing `Supabase` or
/// any of its submodules directly. This keeps the module-name collision
/// documented in `Package.swift` fully contained, and means a future
/// backend swap only touches this one file.
///
/// Never logs a token, key, or session value anywhere in this type — see
/// docs/SECURITY.md "Secret handling".
public final class SupabaseGateway: @unchecked Sendable {
    private let client: SupabaseClient

    public init(config: SupabaseConfig) {
        self.client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }

    // MARK: - Auth

    /// Exchanges an Apple-issued identity token for a Supabase session via
    /// `auth.signInWithIdToken(credentials:)` with provider `.apple`. The
    /// nonce must be the same raw nonce whose SHA-256 hash was passed to
    /// `ASAuthorizationAppleIDRequest.nonce` — Supabase/Apple verify it
    /// against the token's `nonce` claim.
    public func signInWithApple(identityToken: Data, nonce: String) async throws -> RemoteAuthUser {
        guard let idTokenString = String(data: identityToken, encoding: .utf8) else {
            throw SupabaseKitError.invalidIdentityTokenEncoding
        }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idTokenString, nonce: nonce)
        )
        return remoteUser(from: session.user)
    }

    /// Signs out of the current Supabase session, if any. A no-op (not an
    /// error) if there is no active session — matches `AuthBackend`'s
    /// contract that sign-out never needs to be conditioned on state.
    public func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Restores a session from Supabase's persisted/refreshed session
    /// storage at app launch. Returns `nil` (not a thrown error) when there
    /// is nothing to restore — a clean signed-out state.
    public func restoreSession() async throws -> RemoteAuthUser? {
        do {
            let session = try await client.auth.session
            return remoteUser(from: session.user)
        } catch {
            return nil
        }
    }

    /// Permanently deletes the signed-in user's account and all owned data.
    /// Implemented as a call to a `security definer` Postgres RPC
    /// (`delete_own_account`) rather than the client deleting rows itself,
    /// so the deletion is atomic and cannot be partially bypassed by a
    /// compromised or buggy client skipping a step. See
    /// docs/CLOUD_ARCHITECTURE.md for the RPC's contract; it must be added
    /// as a migration before this ships to production (tracked in
    /// docs/CLOUD_CONTINUATION.md).
    public func deleteAccount() async throws {
        _ = try await client.rpc("delete_own_account").execute()
        try await client.auth.signOut()
    }

    private func remoteUser(from authUser: Auth.User) -> RemoteAuthUser {
        let displayName = authUser.userMetadata["full_name"]?.stringValue
        return RemoteAuthUser(
            id: authUser.id.uuidString,
            email: authUser.email,
            displayName: displayName,
            createdAt: authUser.createdAt
        )
    }

    // MARK: - Generic PostgREST access

    /// `SELECT` rows from `table` matching every filter in `filters`
    /// (`AND`ed), decoded as `[T]`.
    public func select<T: Decodable>(table: String, filters: [PGFilter] = [], as type: T.Type) async throws -> [T] {
        var query = client.from(table).select()
        for filter in filters {
            query = query.eq(filter.column, value: filter.value)
        }
        return try await query.execute().value
    }

    /// `INSERT`s a single row, returning the server's representation
    /// (including server-assigned defaults like `id`/`created_at`).
    public func insert<Row: Encodable, Returned: Decodable>(
        table: String,
        values: Row,
        returning: Returned.Type
    ) async throws -> Returned {
        try await client.from(table)
            .insert(values, returning: .representation)
            .select()
            .single()
            .execute()
            .value
    }

    /// Upserts a single row: `INSERT ... ON CONFLICT (onConflict) DO UPDATE`
    /// via PostgREST's `Prefer: resolution=merge-duplicates` header. This is
    /// how `SupabaseAssetRemoteService` makes a retried offline write safe —
    /// resubmitting the same `(workspace_id, idempotency_key)` merges into
    /// the existing row instead of creating a duplicate. See
    /// docs/CLOUD_ARCHITECTURE.md "Idempotent asset writes".
    public func upsert<Row: Encodable, Returned: Decodable>(
        table: String,
        values: Row,
        onConflict: String,
        returning: Returned.Type
    ) async throws -> Returned {
        try await client.from(table)
            .upsert(values, onConflict: onConflict, returning: .representation)
            .select()
            .single()
            .execute()
            .value
    }

    /// `UPDATE`s rows matching every filter in `filters`, returning the
    /// updated rows. Callers must always pass at least one filter — an
    /// unfiltered update would touch every row in the table.
    public func update<Row: Encodable, Returned: Decodable>(
        table: String,
        values: Row,
        filters: [PGFilter],
        returning: Returned.Type
    ) async throws -> [Returned] {
        var query = try client.from(table).update(values, returning: .representation)
        for filter in filters {
            query = query.eq(filter.column, value: filter.value)
        }
        return try await query.select().execute().value
    }

    /// Soft/hard `DELETE`s rows matching every filter in `filters`. Callers
    /// must always pass at least one filter.
    public func delete(table: String, filters: [PGFilter]) async throws {
        var query = client.from(table).delete(returning: .minimal)
        for filter in filters {
            query = query.eq(filter.column, value: filter.value)
        }
        _ = try await query.execute()
    }
}
