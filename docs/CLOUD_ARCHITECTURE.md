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

## Environment configuration

See `.env.example` for the variable names the app/tooling expect
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, etc.) — no real values are ever
committed. Populate a real `.env` (gitignored) locally, and configure the
same values as CI/CD secrets and in Xcode build configuration for actual
builds.
