# Security

SerialSnap is a cloud-first iOS app: scanned asset data is synced to a Supabase
(Postgres) backend so a user's inventory is available across their devices.
This document covers the threat model and the security controls that follow
from it. For system layout see `docs/CLOUD_ARCHITECTURE.md`; for what data is
collected and why, see `docs/PRIVACY.md`.

## Threat model

In scope:

- **Cross-tenant data exposure** — one user or workspace reading or writing
  another's assets, either through a compromised client, a buggy query, or a
  missing database policy.
- **Credential/token theft** — an attacker who obtains a device or gains
  access to local storage should not be able to silently impersonate the user
  against the backend indefinitely.
- **Secret leakage** — API keys or database credentials with elevated
  privilege ending up in the shipped app binary, a public repo, or CI logs.
- **Supply chain risk** — a compromised or malicious third-party dependency
  (Swift package or backend extension) gaining access to user data.
- **Malicious/malformed input** — a crafted image, barcode payload, or OCR
  result attempting to inject unexpected data into stored records or SQL.

Out of scope for this document (but tracked elsewhere as the app matures):
physical device theft/passcode compromise (mitigated at the OS level by
Face ID/Touch ID and OS keychain protections), and platform-level iOS
vulnerabilities.

## Tenant isolation via Row Level Security (RLS)

All multi-tenant data lives in Postgres tables with **Row Level Security
enabled and enforced**, not just application-layer filtering. The rule of
thumb: if RLS is bypassed or a query forgets a `WHERE` clause, no cross-user
data should still be readable or writable.

- Every table holding user- or workspace-scoped data has an owning
  `user_id` / `workspace_id` column and matching RLS policies for
  `SELECT`, `INSERT`, `UPDATE`, and `DELETE` that key off
  `auth.uid()` (or workspace-membership checks derived from it).
- Policies are additive-deny by default: a table with RLS enabled and no
  matching policy denies access rather than allowing it.
- RLS policies are defined in the SQL migrations under `supabase/migrations`
  and are the single source of truth for authorization — the iOS client
  never re-implements access control logic that the database should own.
- Workspace/team sharing (where applicable) is expressed as explicit
  membership rows, not by loosening tenant boundaries in the client.

RLS policy correctness is verified with automated tests — see
`docs/TESTING.md` for how those tests are run and what they must cover
before a policy change ships.

## Least privilege

- The app's Supabase client uses the **anonymous/public (`anon`) API key**
  only. This key is safe to embed in a distributed binary because every
  request it makes is still subject to RLS.
- The **service-role key is never included in the iOS app, in client-side
  configuration, or in any file committed to this repository.** It is used
  only by trusted server-side/CI contexts (e.g. running migrations) that
  need to bypass RLS deliberately, and only from environments where it is
  injected as a secret at deploy/run time.
- Database roles used by any server-side job follow least privilege: a job
  that only needs to read a table is not granted write access to it.
- Third-party integrations (if any are added later) are scoped to the
  minimum data and permissions they need, and documented before being wired
  in.

## Secret handling

- No API key, database URL, or credential is hardcoded in source. Local
  development secrets are read from an untracked `.env` file (see
  `.env.example` for the documented variable names) or from Xcode build
  configuration/xcconfig files that are themselves untracked.
- CI never prints secret values to logs. The migration-validation CI job
  runs against an ephemeral, locally-provisioned Postgres container with
  throwaway credentials — it does not require or use any real Supabase
  project secret.
- Production secrets (service-role key, production database URL, signing
  keys) are held only in the CI/CD secret store and the Supabase project
  dashboard, never in the git repository.
- If a secret is ever accidentally committed, it must be treated as
  compromised and rotated immediately — history rewriting alone is not
  sufficient.

## Auth token handling

- User authentication is handled by Supabase Auth (email/password and/or
  Sign in with Apple — see `docs/CLOUD_ARCHITECTURE.md` for the exact
  providers enabled).
- Session tokens (access + refresh) are stored using iOS Keychain, not
  `UserDefaults` or plain files, so they benefit from OS-level encryption
  and are not included in unencrypted device backups by default.
- Access tokens are short-lived; the client relies on Supabase's refresh
  token flow rather than requesting long-lived tokens.
- Signing out clears all locally cached tokens and any locally cached
  asset data tied to that account (see `docs/PRIVACY.md` for the account
  deletion flow, which goes further and removes server-side data too).
- All network calls to the backend are made over TLS (HTTPS); no
  credential or token is ever sent over plaintext HTTP.

## Dependency policy

- Only Swift Package Manager dependencies with a clear license, active
  maintenance, and a scope matching their stated purpose are added.
- Dependencies are pinned (exact version or narrow range) rather than left
  floating, so CI builds are reproducible and a compromised upstream
  release does not silently get pulled in.
- New dependencies are reviewed for what data/network access they could
  reasonably touch before being added — a parsing or UI library should not
  need network access, for example.
- Dependency versions are revisited periodically (see
  `docs/RELEASE_CHECKLIST.md`) as part of release preparation, not only
  when something breaks.

## Input handling

- OCR/barcode results are treated as untrusted input: they are validated
  and normalized (see the `Parsing` package) before being persisted, and
  all database writes use parameterized queries/the Supabase client
  library — never hand-built SQL string concatenation.
- Image data captured by the camera is processed on-device (see
  `docs/PRIVACY.md`) and is not forwarded to any external service as part
  of parsing.

## Reporting a concern

Until a dedicated security contact is published, report suspected security
issues to the repository owner directly rather than opening a public issue,
so a fix can be prepared before any details are made public.
