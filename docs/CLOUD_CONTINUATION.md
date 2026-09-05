# Cloud Continuation — Milestone 1 Handoff

This document is the authoritative state of the repo at the end of
milestone 1. Written for a fresh agent with no other context to pick up
immediately.

## Environment facts (read this first)

This session ran in a **Linux container with no Xcode, no `xcodebuild`,
and no Swift toolchain** (`which swift`/`swiftc`/`xcodebuild`/`xcodegen`
all returned nothing). The outbound network proxy also blocks
`download.swift.org` (403), so a Swift toolchain could not be installed
either. This means:

- **No `.xcodeproj` was generated or opened**, and **no `swift build`/
  `swift test` command was actually run in this container** — this is an
  environment limitation, not a decision. All Swift code below is
  believed correct by careful manual review and mutual consistency (types,
  imports, protocol conformances) but is **UNVERIFIED by compilation**.
  Treat every `.swift` file as needing a real `swift build`/`swift test`
  (or Xcode build) pass as the very first step of the next milestone.
- **Postgres 16 WAS available** (`psql`, plus a stopped local cluster this
  session started with `service postgresql start`) and was used for real:
  the schema and RLS migrations were applied to a live local database and
  the RLS isolation test suite was run and passed — see below for the
  actual command transcript.
- The Supabase CLI itself is not installed in this container, so
  `supabase start`/`supabase test db` were not run; the local-Postgres
  path (with `supabase/tests/00_local_test_shim.sql` standing in for
  Supabase Auth's `auth.users`/`auth.uid()`) was used instead, and is
  documented as the reproducible fallback in `docs/CLOUD_ARCHITECTURE.md`.

## What exists

```
App/                 SwiftUI app shell (SerialSnapApp, RootView, Onboarding,
                      WorkspaceSelect, Scanner/AssetList/Settings screens),
                      Info.plist, unimplemented Auth/Workspace backends
Packages/
  Core/              Domain models: User, Workspace, WorkspaceMembership,
                      Asset, SyncStatus, FieldConfidence. Pure Swift.
                      Tests: ModelsTests.swift (5 tests)
  Parsing/           LabelParser (deterministic field extraction),
                      AmbiguityNormalizer (OCR confusable-char handling),
                      ExtractedFields/ParsedField/ParsedConfidence. Pure
                      Swift, zero UIKit/SwiftUI/Vision imports.
                      Tests: LabelParserTests.swift + AmbiguityNormalizerTests
                      (20 tests total) covering HP/Dell/Lenovo/printer/
                      monitor/router/unknown-manufacturer/serial-only/
                      serial+model/serial+assetID/serial+barcode-agreement/
                      confusable-agreement/barcode-only/ambiguous-OCR/
                      empty-input/noise-line fixtures
  Export/            AssetExporter: RFC4180 CSV (quote/comma/newline
                      escaping, stable column order) + versioned JSON.
                      Pure Swift. Tests: AssetExporterTests.swift (8 tests)
  Sync/              WriteOperation/WriteQueueStore/InMemoryWriteQueueStore,
                      IdempotencyKeyGenerator, SyncEngine (retry + flush),
                      ConflictResolver (last-write-wins by updatedAt). Pure
                      Swift, protocol-based remote seam (RemoteAssetService).
                      Tests: SyncEngineTests.swift (9 tests) incl. a fake
                      remote proving retried submissions never duplicate
                      server-side records
  Assets/            AssetStore: ExtractedFields -> candidate Asset ->
                      duplicate detection -> local save + Sync enqueue;
                      search. Pure Swift (Core/Sync/Parsing only).
                      Tests: AssetStoreTests.swift (7 tests)
  OCR/                iOS-only (Vision/AVFoundation): TextRecognizer,
                      BarcodeRecognizer, ScanPipeline. No test target
                      (Apple-only frameworks, cannot run on Linux).
  Scanner/            iOS-only (AVFoundation/UIKit): CameraPermission,
                      CaptureSessionController.
  Auth/               Sign in with Apple session state machine
                      (AuthSessionStore, AuthBackend protocol). Supabase-
                      backed AuthBackend implementation NOT yet written —
                      App/UnimplementedBackends.swift is the placeholder.
  Workspace/          WorkspaceStore + WorkspaceBackend protocol. Same
                      "not yet Supabase-backed" status as Auth.
  Settings/           SettingsViewModel (sign out / delete account flow).
  DesignSystem/       SSColor, GlassSurfaceModifier (.glassEffect() on
                      iOS 18+, .regularMaterial fallback), SSFont,
                      ConfidenceBadge.
  Localization/       Localizable.xcstrings (46 keys, en base locale) +
                      type-safe L10n enum.
supabase/
  migrations/
    20260901000001_initial_schema.sql   users/workspaces/memberships/assets
    20260901000002_row_level_security.sql   RLS enabled + policies on all 4 tables
  tests/
    00_local_test_shim.sql   auth.users/auth.uid() shim for plain Postgres
    10_rls_isolation_test.sql   6 real cross-tenant isolation assertions
docs/
  ARCHITECTURE_DECISIONS.md   ADR-001..005 (Supabase, on-device OCR,
                              SwiftData sync, package-per-module, String
                              Catalog localization)
  CLOUD_ARCHITECTURE.md      schema/RLS explanation + how to run migrations
  SECURITY.md, PRIVACY.md, TESTING.md, APP_STORE_READINESS.md,
  REAL_DEVICE_QA.md, RELEASE_CHECKLIST.md   (scaffolded alongside this
                              session's work; consistent with the above)
PrivacyManifest/PrivacyInfo.xcprivacy   scaffolded privacy manifest
project.yml           XcodeGen spec wiring all 12 packages to the App target
.env.example          SUPABASE_URL / SUPABASE_ANON_KEY / APPLE_SIGN_IN_SERVICE_ID
.gitignore            Xcode/SPM/Supabase/secrets patterns
README.md             overview + setup instructions
```

## What is verified, with real command output

### 1. Postgres schema migration — applied cleanly

```
$ sudo -u postgres psql -d serialsnap_verify -v ON_ERROR_STOP=1 \
    -f supabase/migrations/20260901000001_initial_schema.sql
CREATE EXTENSION
CREATE TABLE
CREATE FUNCTION
CREATE TRIGGER
CREATE TABLE
CREATE TYPE
CREATE TABLE
CREATE INDEX (x4)
CREATE FUNCTION
CREATE TRIGGER
CREATE TABLE
CREATE INDEX (x4)
CREATE FUNCTION
CREATE TRIGGER (x2)
```
No errors. (Run against a database that already had the
`00_local_test_shim.sql` auth shim applied, to provide `auth.users` the
same way a real Supabase project already does.)

### 2. RLS migration — applied cleanly

```
$ sudo -u postgres psql -d serialsnap_verify -v ON_ERROR_STOP=1 \
    -f supabase/migrations/20260901000002_row_level_security.sql
ALTER TABLE (x4)
CREATE FUNCTION (x2)
CREATE POLICY (x12)
```
No errors.

### 3. RLS isolation test suite — all 6 assertions PASS (rerun to confirm reproducibility)

```
$ sudo -u postgres psql -d serialsnap_verify -v ON_ERROR_STOP=1 \
    -f supabase/tests/10_rls_isolation_test.sql
NOTICE:  PASS: alice_sees_only_own_workspace_assets
NOTICE:  PASS: cross_tenant_update_denied
NOTICE:  PASS: cross_tenant_delete_denied
NOTICE:  PASS: cross_tenant_insert_denied
NOTICE:  PASS: cross_tenant_workspace_select_denied
NOTICE:  PASS: same_tenant_update_allowed
NOTICE:  ALL RLS ISOLATION TESTS PASSED
```
This proves, against a live database (not just by code review): a second
user cannot read, update, delete, or insert into another user's/
workspace's assets or read their workspace row, while a legitimate member
of a workspace can still update their own asset. Exact reproduction steps
are in `docs/CLOUD_ARCHITECTURE.md` ("Running migrations" section).

### What is NOT verified (needs a macOS/Xcode environment)

- `swift build` / `swift test` for **any** package, including the pure-
  Swift ones (`Core`, `Parsing`, `Export`, `Sync`, `Assets`) that were
  specifically designed to be Linux-testable — no Swift toolchain was
  reachable in this container (no `swift` binary, and
  `download.swift.org` is blocked by the outbound proxy: `curl` returned
  `403`/`CONNECT tunnel failed`). **This is the single highest-priority
  verification gap** — see "Next executable milestone" below.
- `xcodegen generate` / opening `SerialSnap.xcodeproj` in Xcode / building
  the `SerialSnap` app target.
- Anything requiring Vision/AVFoundation/SwiftData/AuthenticationServices
  at runtime (all Apple-only frameworks).

## Commits made this session (chronological, all pushed)

Branch: `claude/serialsnap-ios-production-6yb4rs`, pushed to
`origin` after each commit.

1. `25ff14a` — Add Core, Parsing, Export, Sync packages and Supabase schema+RLS
2. `aab2416` — Add ADRs, cloud architecture docs, and .env.example
3. `8d98313` — Add App target skeleton, remaining feature packages, XcodeGen spec
4. `579fdb2` — Make RLS test suite idempotent (drop role if exists before create)
5. (this commit) — Add docs/CLOUD_CONTINUATION.md

**Note on commit trailers:** commit 1 (`25ff14a`) was made before this
session's attribution convention was fully internalized and does **not**
carry the `Co-Authored-By`/`Claude-Session` trailers that all later
commits do. Per repo convention, it was not amended (amending after other
commits exist would rewrite already-pushed history) — flagging it here for
visibility rather than silently leaving it undocumented.

Push status: all 5 commits are on `origin/claude/serialsnap-ios-production-6yb4rs` (confirmed via `git push` output after each commit — no rejections, no force needed).

## Milestones remaining (from the master spec)

Roughly in the order they unblock each other:

1. **Verify compilation** (see "Next executable milestone" — this is the
   very next thing to do, before writing more code).
2. Wire `Auth` and `Workspace` packages to a real `supabase-swift` client:
   replace `App/UnimplementedBackends.swift` with real
   `SupabaseAuthBackend`/`SupabaseWorkspaceBackend` implementations.
3. Full Sign in with Apple UI flow (`ASAuthorizationAppleIDButton`,
   nonce generation/hashing, Keychain token storage per `docs/SECURITY.md`).
4. Workspace create/select screens wired to live data (currently a
   skeleton list with a text field that doesn't call `createWorkspace`
   yet).
5. Live camera scanner: wire `Scanner.CaptureSessionController` into
   `ScannerScreen` with an `AVCaptureVideoPreviewLayer`-backed SwiftUI view
   (`UIViewRepresentable`), replacing `CameraReadyPlaceholder`.
6. OCR/barcode pipeline end-to-end: confirm `OCR.ScanPipeline` output
   flows into `Assets.AssetStore.makeCandidate` correctly on a real device
   (this is the first point real Vision output — not synthetic fixtures —
   exercises `Parsing.LabelParser`).
7. Review/edit UI: a screen surfacing `ExtractedFields` for user
   confirmation, highlighting ambiguous characters
   (`ExtractedFields.serialNumberAlternates`) and low-confidence fields
   (`ConfidenceBadge`), plus the duplicate-warning banner driven by
   `AssetStore.findDuplicates`.
8. Asset list/detail screens wired to real `AssetStore` data (list
   currently always renders the empty state).
9. `SwiftData`-backed concrete `AssetLocalStore` and `WriteQueueStore`
   (currently only `InMemoryAssetLocalStore`/`InMemoryWriteQueueStore`
   exist, used for tests — production needs durable on-device storage).
10. `Sync` engine wired to a real `RemoteAssetService` implementation
    calling Supabase's PostgREST endpoints (`/rest/v1/assets`), including
    sending `idempotency_key` and handling the unique-constraint conflict
    response for a duplicate retry.
11. CSV/JSON export UI (`ShareLink`) using `Export.AssetExporter`.
12. Settings screens beyond the current stub list: language picker wired
    to actual locale switching, privacy/about content screens.
13. Accessibility pass (VoiceOver labels, Dynamic Type at accessibility
    sizes, contrast checks beyond the semantic-color defaults already in
    `DesignSystem`).
14. Localization completeness: translate `Localizable.xcstrings` beyond
    the `en` base locale once target languages are decided.
15. CI: this container could not verify `.github/workflows/ci.yml` runs
    green (needs `macos-14` runners with a real `swift`/Xcode, which
    GitHub Actions has but this container doesn't) — first real PR/push
    against this branch is the first real CI signal.
16. Privacy manifest (`PrivacyManifest/PrivacyInfo.xcprivacy`) validation
    against actual API usage once more frameworks are wired in.
17. App Store readiness pass (`docs/APP_STORE_READINESS.md`) and
    real-device QA pass (`docs/REAL_DEVICE_QA.md`) — both need a physical
    device/TestFlight, which this container cannot provide.

## Next executable milestone (start here)

**Goal: get a real `swift build && swift test` (not just careful review)
for the five Linux-testable packages, on a machine with the Swift
toolchain, then fix whatever it finds.**

Exact steps for a fresh agent:

1. Confirm a Swift toolchain is available: `swift --version`. If this is
   still a container without one, install Swift for Linux from
   `https://www.swift.org/install/linux/` (this session's proxy blocked
   `download.swift.org` — try again from an unrestricted network, or do
   this step on macOS/Xcode instead, where step 2 also gets you the full
   app build for free).
2. Run, from the repo root:
   ```sh
   for pkg in Core Parsing Export Sync Assets; do
     echo "==> Packages/$pkg"
     (cd "Packages/$pkg" && swift build && swift test) || { echo "FAILED: $pkg"; break; }
   done
   ```
3. Fix any compile errors or test failures found — they were written
   carefully but genuinely unverified by a compiler in this session, so
   treat any failure as a real bug to fix, not a false positive.
4. Once those five pass, on macOS: `xcodegen generate`, open
   `SerialSnap.xcodeproj`, and get the `SerialSnap` scheme building (this
   will surface any issues in the iOS-only packages — `OCR`, `Scanner`,
   `Auth`, `Workspace`, `Settings`, `DesignSystem` — for the first time).
5. Only after 2–4 are green, proceed to milestone-remaining item #2
   (real Supabase client wiring) above — building further UI on top of
   unverified logic compounds risk.

## True external blockers

- **No macOS/Xcode in this container** → the final `.ipa`
  archive/App Store submission step can never happen here, only on a
  macOS machine or CI runner with Xcode (this is an environment fact
  stated in `.github/workflows/ci.yml` already, which correctly targets
  `macos-14` runners for the Swift build/test jobs).
- **No Swift toolchain reachable in this container** (see above) — this
  blocked *any* `swift build`/`swift test` run in this session, including
  for the packages designed to be Linux-testable. Not a design flaw in
  the packages; a tooling gap in this specific container that the next
  environment should not assume persists.
- **No Supabase CLI/project** — migrations were validated against plain
  Postgres with an auth shim (see verified section above), which is a
  faithful proxy for schema/RLS correctness but has not been run through
  `supabase db push` against a real project, nor exercised via the actual
  Supabase Auth/PostgREST HTTP layer the app will call in production.
- **No physical iOS device or Apple Developer account context** in this
  container — Sign in with Apple, camera capture, and TestFlight/App
  Store steps all require one and are out of scope for any container-only
  session.

None of the above blocked the work done in this milestone; they are
recorded so the next milestone starts by closing the compilation-
verification gap rather than assuming this session's code already builds.
