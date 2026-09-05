# Testing Strategy

This document describes how SerialSnap is tested across its layers: pure
Swift package logic, backend (Supabase/Postgres) policies, integration
between the two, and manual UI/device validation. For CI wiring see
`.github/workflows/ci.yml`; for the manual device pass see
`docs/REAL_DEVICE_QA.md`.

## Layers

1. **Unit tests** — per-package `swift test` targets covering pure logic:
   parsing/normalization rules (`Parsing`), export formatting (`Export`),
   sync conflict resolution logic (`Sync`), core models (`Core`), etc.
   These have no network or camera dependency and run on every push/PR.
2. **Fixture-based tests** — tests that exercise OCR/barcode parsing logic
   against a library of representative *synthetic* label images/strings
   (see Fixture policy below), rather than live camera input.
3. **Backend tests** — SQL/RLS policy tests that run against a real
   Postgres instance (ephemeral in CI, local Supabase CLI in dev) to prove
   tenant isolation holds.
4. **Integration tests** — tests that exercise a package against the
   Supabase client against a local/test backend (e.g. `Sync` writing a
   record and reading it back under a given auth context).
5. **Manual UI/device QA** — camera, permissions, and end-to-end flows that
   cannot be meaningfully simulated in CI; see `docs/REAL_DEVICE_QA.md`.

## Running unit tests per package

Each package under `Packages/*` with a `Package.swift` is buildable and
testable independently:

```sh
cd Packages/Core && swift test
cd Packages/Parsing && swift test
cd Packages/Export && swift test
cd Packages/Sync && swift test
# ...and so on for every package under Packages/*
```

To run all of them in one pass locally:

```sh
for pkg in Packages/*/Package.swift; do
  dir="$(dirname "$pkg")"
  echo "==> $dir"
  (cd "$dir" && swift test) || exit 1
done
```

CI runs this same discovery-and-fan-out pattern automatically (see the
`discover-packages` and `build-and-test` jobs in
`.github/workflows/ci.yml`), so any new package added under `Packages/*`
with its own `Package.swift` is picked up without editing the workflow.

## Running Supabase RLS tests

RLS policies are the primary tenant-isolation control (see
`docs/SECURITY.md`), so they need tests that prove a user cannot read or
write another user's/workspace's rows.

Locally, using the Supabase CLI:

```sh
supabase start                 # spins up local Postgres + Auth + API
supabase db reset              # applies all migrations from a clean state
# Run the RLS test suite (SQL-based, e.g. under supabase/tests) with pgTAP
# or an equivalent SQL test runner:
supabase test db
```

Recommended structure for RLS tests under `supabase/tests/` (owned by the
migrations author, cross-referenced here for how to run them):

- For every table with RLS enabled, a test that a second, unrelated
  authenticated user cannot `SELECT`/`UPDATE`/`DELETE` a row it does not
  own.
- A test that an unauthenticated (`anon`, no JWT) request is denied by
  default where the policy requires authentication.
- A test that a workspace member can access shared workspace data and a
  non-member cannot.

In CI, the `migrations` job in `.github/workflows/ci.yml` applies all
`supabase/migrations/*.sql` files against a throwaway Postgres service
container to catch syntax errors and failed migrations on every push; it
does not require a real Supabase project or secrets. As the `supabase/`
test suite grows, wire `supabase test db` (or equivalent) into that same
job so RLS regressions are caught automatically, not just migration syntax
errors.

## Synthetic fixture policy

**Never commit real customer data, real serial numbers, or real device
photos to this repository — test fixtures must be synthetic.**

- Label/barcode fixtures used to test OCR and parsing accuracy are either
  generated (e.g. rendered text on a plain background, procedurally
  generated barcodes) or manually crafted with made-up serial numbers and
  product names that do not correspond to real inventory.
- Backend test data (seed rows used for RLS tests) uses obviously fake
  values (e.g. `test-user-a@example.com`, serials like `TEST-0001`).
- If a real-world example is needed to reproduce a bug (e.g. a
  mis-parsed label format), redact or reconstruct the specific pattern
  that caused the failure rather than committing the original captured
  image or data.

## Coverage expectations per module

| Module | Expectation |
|---|---|
| `Core` | High — shared models/utilities used everywhere; regressions here are widest-blast-radius. |
| `Parsing` | High, with a growing fixture library — this is the module most exposed to real-world input variance (label formats, OCR noise). |
| `Export` | High for format-correctness (e.g. CSV/PDF field mapping); golden-file comparisons where practical. |
| `Sync` | High for conflict-resolution and offline-queue logic; integration-tested against a local Supabase instance. |
| `OCR` / `Scanner` | Unit-tested for the non-camera-dependent logic (result post-processing, confidence thresholds); camera capture itself is covered by manual QA. |
| `Auth` | Unit-tested for session/token handling logic; the actual sign-in UI flow (incl. Sign in with Apple) is covered by manual QA. |
| `DesignSystem` / `Localization` | Lighter — mostly compile-time/snapshot checks; correctness here is largely visual, covered by manual QA. |
| `Workspace`, `Assets`, `Settings` | Medium — business logic unit-tested; UI flows covered by manual QA. |
| Supabase RLS policies | High — every table with RLS must have a passing/failing test pair (owner can access, non-owner cannot) before merge. |

New packages should ship with unit tests from their first commit rather
than have tests added retroactively.
