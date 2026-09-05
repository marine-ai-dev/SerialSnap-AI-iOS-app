# Cloud Architecture

See `docs/ARCHITECTURE_DECISIONS.md` (ADR-001) for why Supabase was chosen.
This document describes the concrete schema, RLS policies, and how to run
migrations.

## Schema overview

Defined in `supabase/migrations/20260901000001_initial_schema.sql`:

| Table | Purpose |
|---|---|
| `public.users` | Thin profile mirror of `auth.users` (id, email, display_name), auto-populated by a trigger on signup. |
| `public.workspaces` | A team/organization's asset inventory container. `owner_id` references `public.users`. |
| `public.workspace_memberships` | Join table: which users belong to which workspace, and their `role` (`owner` \| `member`). This table is the single source of truth every RLS policy consults. |
| `public.assets` | The canonical asset record: manufacturer, model, serial_number, asset_tag, barcode_value/symbology, notes, confidence, sync/idempotency metadata, soft-delete flag. **No image columns** — only minimal structured fields are stored in the cloud by design (see `docs/PRIVACY.md`). |

Key design points:

- `assets.idempotency_key` + a unique index on `(workspace_id,
  idempotency_key)` (partial: `where idempotency_key is not null`) is what
  makes retried offline writes safe — see
  `Packages/Sync/Sources/Sync/WriteQueue.swift` for the client side that
  generates these keys.
- `assets.is_deleted` is a soft-delete tombstone rather than a hard
  `DELETE`, so deletions propagate correctly to other devices during sync
  (a device that was offline when the delete happened needs to *see* the
  tombstone, not just fail to find the row).
- New workspaces auto-add their creator as an `owner` member via the
  `handle_new_workspace` trigger — the API surface for "create workspace"
  is just an insert into `workspaces`.
- New auth users auto-get a `public.users` row via `handle_new_auth_user`.

## Row Level Security

Defined in `supabase/migrations/20260901000002_row_level_security.sql`.
Full rationale in `docs/SECURITY.md` — summary:

- RLS is **enabled on every table** (`users`, `workspaces`,
  `workspace_memberships`, `assets`).
- Two `security definer` helper functions, `is_workspace_member(uuid)` and
  `is_workspace_owner(uuid)`, centralize the membership check every policy
  uses (avoids repeating — and risking drift in — the same subquery in a
  dozen policies, and avoids RLS-on-`workspace_memberships` causing
  infinite recursion when checking membership from another table's
  policy).
- `assets` policies require `is_workspace_member(workspace_id)` for
  `SELECT`/`UPDATE`/`DELETE`, and additionally `created_by_user_id =
  auth.uid()` on `INSERT` (a member can only create assets attributed to
  themselves).
- This is enforced **regardless of what the client sends** — a compromised
  or buggy client cannot read or write another workspace's assets no
  matter what `workspace_id` it puts in a query, because Postgres itself
  rejects rows that don't satisfy the policy.

### Verified for real

`supabase/tests/10_rls_isolation_test.sql`, run against a live local
Postgres 16 instance (not just reviewed), proves:

1. A user sees only assets in workspaces they belong to.
2. Cross-tenant `UPDATE` is denied (0 rows affected, not an error swallowed
   silently — the test asserts the row count).
3. Cross-tenant `DELETE` is denied.
4. Cross-tenant `INSERT` directly into another user's workspace is denied.
5. Cross-tenant `SELECT` of the workspace row itself is denied.
6. A legitimate same-tenant `UPDATE` **is** allowed (proves the policies
   aren't just failing closed on everything).

See `docs/CLOUD_CONTINUATION.md` for the exact command output from this
run and exactly how to reproduce it.

## Running migrations

**Against a real Supabase project** (recommended path once one exists):

```sh
supabase link --project-ref <your-project-ref>
supabase db push          # applies supabase/migrations/*.sql in order
```

**Local development with the Supabase CLI:**

```sh
supabase start             # local Postgres + Auth + Storage + API, via Docker
supabase db reset          # (re)applies all migrations from a clean DB
```

**Without the Supabase CLI** (e.g. this container, which has `psql` but
not Docker/the Supabase CLI or a full Supabase stack) — apply against any
Postgres 16 instance, with the local auth shim standing in for Supabase
Auth's `auth.users`/`auth.uid()`:

```sh
psql <connection> -v ON_ERROR_STOP=1 -f supabase/tests/00_local_test_shim.sql
psql <connection> -v ON_ERROR_STOP=1 -f supabase/migrations/20260901000001_initial_schema.sql
psql <connection> -v ON_ERROR_STOP=1 -f supabase/migrations/20260901000002_row_level_security.sql
psql <connection> -v ON_ERROR_STOP=1 -f supabase/tests/10_rls_isolation_test.sql
```

Do **not** run `00_local_test_shim.sql` against a real Supabase project —
`auth.users` and `auth.uid()` already exist there, managed by Supabase
Auth itself; the shim exists purely so migrations/RLS can be validated
against a plain Postgres instance in environments (like this one) without
the full Supabase stack available.

## Client wiring (milestone 2)

See ADR-006 in `docs/ARCHITECTURE_DECISIONS.md` for why `supabase-swift` is
isolated behind one facade package, `Packages/SupabaseKit`
(`SupabaseGateway` + `SupabaseConfig`). Every Supabase-backed
implementation lives in the feature package whose protocol it satisfies,
and depends only on `SupabaseKit` — never on `supabase-swift` directly:

- `Packages/Auth/Sources/Auth/SupabaseAuthBackend.swift` — `AuthBackend`.
  Sign in with Apple exchanges the identity token via
  `auth.signInWithIdToken(credentials:)` (provider `.apple`); session
  restore/refresh goes through `auth.session` (Supabase's SDK handles
  token refresh internally); sign-out and account deletion (via a
  `delete_own_account` RPC — not yet defined as a migration, tracked in
  docs/CLOUD_CONTINUATION.md) round out the protocol.
- `Packages/Workspace/Sources/Workspace/SupabaseWorkspaceBackend.swift` —
  `WorkspaceBackend`, over PostgREST (`workspaces` / `workspace_memberships`
  tables). `fetchWorkspaces` issues a deliberately unfiltered `SELECT` —
  Row Level Security, not a client-side `WHERE`, is what actually scopes
  the result to the caller's workspaces (see docs/SECURITY.md).
- `Packages/Sync/Sources/Sync/SupabaseAssetRemoteService.swift` —
  `RemoteAssetService`, over PostgREST (`assets` table). See "Idempotent
  asset writes" below.
- `Packages/Sync/Sources/Sync/SwiftDataWriteQueueStore.swift` and
  `Packages/Assets/Sources/Assets/SwiftDataAssetLocalStore.swift` — on-device
  durable storage (`WriteQueueStore` / `AssetLocalStore`), backed by
  SwiftData `@Model` types that mirror `Sync.WriteOperation` /
  `Core.Asset`. Both are gated behind `#if canImport(SwiftData)` /
  `@available(iOS 17, macOS 14, *)`; `InMemoryWriteQueueStore` /
  `InMemoryAssetLocalStore` remain as-is for unit tests.
- `App/AppDependencies.swift` is the composition root: it reads
  `Config/Supabase.xcconfig` (via Info.plist, see below), builds one
  `SupabaseGateway`, and wires every backend + the `SwiftData` stores +
  `SyncEngine` + `AssetStore` from it. `SerialSnapApp` now constructs this
  once and hands its objects to `RootView` as environment objects, instead
  of the milestone-1 `UnimplementedAuthBackend`/`UnimplementedWorkspaceBackend`
  (kept in `App/UnimplementedBackends.swift` for SwiftUI Previews only).

### Idempotent asset writes

`SupabaseAssetRemoteService.submit` upserts on the row's **primary key**
(`id` — the client-generated `AssetID` from `Assets.AssetStore.makeCandidate`)
via PostgREST's `Prefer: resolution=merge-duplicates` header
(`SupabaseGateway.upsert(table:values:onConflict:returning:)`). Because a
retry of a queued `WriteOperation` always resubmits the *same* operation
(same `assetID`), this makes a retried create a safe no-op and a retried
update reapply cleanly, with no duplicate row ever created — the property
`Sync`'s test suite (`SyncEngineTests`) already exercises against a fake
remote.

`assets.idempotency_key` (already present in the initial schema migration,
with its own unique index `uq_assets_workspace_idempotency` on
`(workspace_id, idempotency_key)` — see "Schema overview" above) is still
sent on every write and still enforced by that index. It is not the
upsert's conflict target, but a second, independent database-level
invariant: it makes it a hard error, rather than silent data corruption,
if two different asset rows in the same workspace were ever assigned the
same idempotency key by a bug elsewhere (`IdempotencyKeyGenerator` should
never produce that, but the database — not client trust — is what actually
guarantees it can't happen unnoticed).

An alternative considered was a bespoke `upsert_asset_idempotent(...)`
Postgres RPC performing an explicit `INSERT ... ON CONFLICT
(workspace_id, idempotency_key) DO UPDATE`. Upserting on the primary key
via PostgREST directly was chosen instead: it needs no new migration or
RPC function, reuses the existing unique index as a pure integrity check
rather than a query path, and keeps "how a write reaches the database" in
one place (`SupabaseGateway`) instead of splitting it between a generic
REST call and a bespoke SQL function.

No new migration was required for this milestone: the `idempotency_key`
column and its unique index already existed in
`20260901000001_initial_schema.sql` from milestone 1. It does not change
which RLS policy applies to any row (the existing `assets` INSERT/UPDATE/
DELETE/SELECT policies already cover every column on the table), so
`supabase/tests/10_rls_isolation_test.sql` did not need updating either —
confirmed by re-running the full migration set end-to-end against a fresh
local Postgres 16 database; see docs/CLOUD_CONTINUATION.md "Milestone 2
update" for the exact command transcript.

## Environment configuration

See `.env.example` for the variable names the app/tooling expect
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, etc.) — no real values are ever
committed. Populate a real `.env` (gitignored) locally, and configure the
same values as CI/CD secrets for non-app tooling.

For the iOS app itself specifically: copy `Config/Supabase.xcconfig.example`
to `Config/Supabase.xcconfig` (gitignored — see `.gitignore`'s
`Config/*.xcconfig` rule) and fill in the same two values. `project.yml`
wires that file in as the project's `Debug`/`Release` `configFiles` entry
and surfaces its two keys into the generated app's Info.plist via `$(...)`
substitution; `SupabaseKit.SupabaseConfig.fromInfoDictionary(_:)` reads
them at runtime and throws a clear, actionable error — turned into a
`fatalError` at launch by `App/AppDependencies.swift` — if the file was
never created. This is intentional: a missing xcconfig must fail loudly,
never silently fall back to a hardcoded development URL, especially in a
Release build (see docs/SECURITY.md "Secret handling"). Note the xcconfig
escaping gotcha documented in `Config/Supabase.xcconfig.example` itself:
`//` starts a comment in `.xcconfig` syntax, which would silently truncate
a `https://...` URL value unless escaped as `https:/$()/...`.
