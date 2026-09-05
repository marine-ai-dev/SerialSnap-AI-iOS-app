# Local QA Handoff — Cloud Phase → macOS/Xcode Phase

This is the single source of truth for picking up SerialSnap on a real Mac
with Xcode. It supersedes nothing in `docs/CLOUD_CONTINUATION.md` (still
worth reading for the full milestone-by-milestone history) — this file is
the condensed, current-as-of-handoff snapshot plus the exact next steps.

**Written from inside a Linux cloud container with no Xcode, no `swift`/
`xcodebuild`/`xcodegen` binary, and no Swift toolchain reachable at all**
(confirmed repeatedly this session: `uname -a` → Linux; `which swift
xcodebuild` → nothing). Every fix described below as "fixed" was fixed by
reading real compiler/test-runner errors from GitHub Actions' macOS
runners (which do have Xcode) and editing source accordingly — never by
guessing or by "should work" reasoning alone. Every fix is honestly
flagged if it has not yet been confirmed by a fully green CI run.

## Current branch / commit / push state

- Branch: `claude/serialsnap-ios-production-6yb4rs`
- Latest commit: `3898138` — "fix: qualify Core.User to resolve real ambiguous-type-lookup CI error"
- Working tree: clean (`git status --short` empty at handoff time)
- Push state: `origin/claude/serialsnap-ios-production-6yb4rs` == local `HEAD` (confirmed via `git rev-parse HEAD origin/...` — both `3898138...`)
- No secrets found in a repo-wide grep for API-key/JWT/private-key patterns; no `.env`/non-example `.xcconfig` files are committed.

## What is genuinely done and cloud-verified

### Backend (Supabase/Postgres) — verified against a real, live local Postgres 16 instance, multiple times, in this session

- `supabase/migrations/20260901000001_initial_schema.sql` — users/workspaces/workspace_memberships/assets tables, triggers (auto-profile-on-signup, auto-owner-membership-on-workspace-create, `updated_at` maintenance).
- `supabase/migrations/20260901000002_row_level_security.sql` — RLS enabled + policies on all 4 tables enforcing workspace-scoped access.
- `supabase/migrations/20260901000003_delete_own_account.sql` — `security definer` RPC, callable only by `authenticated`, always operates on `auth.uid()` (never a parameter) so a caller can only ever delete their own account.
- `supabase/migrations/20260901000004_assets_created_by_set_null_on_delete.sql` — fixes a real bug this session found by actually exercising account deletion: `assets.created_by_user_id` had no `ON DELETE` action, so deleting a user who'd ever created an asset in a shared (not solely-owned) workspace failed with a FK violation. Now `ON DELETE SET NULL` — asset and workspace survive, only creator attribution clears.
- `supabase/tests/00_local_test_shim.sql` — local-only stand-in for Supabase's `auth.users`/`auth.uid()`/`authenticated`/`anon` roles. **Never run this against a real Supabase project** — it already has all of this.
- `supabase/tests/10_rls_isolation_test.sql` — 6 cross-tenant isolation assertions.

**Exact verified results (rerun in this session, fresh database each time):**
```
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/tests/00_local_test_shim.sql
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/migrations/20260901000001_initial_schema.sql
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/migrations/20260901000002_row_level_security.sql
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/migrations/20260901000003_delete_own_account.sql
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/migrations/20260901000004_assets_created_by_set_null_on_delete.sql
-- all five applied with zero errors --
$ sudo -u postgres psql -d serialsnap_final_verify -f supabase/tests/10_rls_isolation_test.sql
NOTICE:  PASS: alice_sees_only_own_workspace_assets
NOTICE:  PASS: cross_tenant_update_denied
NOTICE:  PASS: cross_tenant_delete_denied
NOTICE:  PASS: cross_tenant_insert_denied
NOTICE:  PASS: cross_tenant_workspace_select_denied
NOTICE:  PASS: same_tenant_update_allowed
NOTICE:  ALL RLS ISOLATION TESTS PASSED
```
Plus a manual scenario (not an automated test file yet — worth turning into one): deleting a user removed their own account + solely-owned workspace + that workspace's assets, while a *shared* workspace they'd only contributed an asset to survived with the asset intact and `created_by_user_id` nulled.

### Portable Swift packages — real macOS CI compiler/test-runner results (not this container)

As of commit `079a079` (before the final `Core.User` ambiguity fix in `3898138`, not yet re-verified by CI — see "Pending CI verification" below):

| Package | swift build | swift test | Notes |
|---|---|---|---|
| Core | ✅ pass | ✅ pass | |
| Parsing | ✅ pass | ✅ pass | 20 tests, HP/Dell/Lenovo/printer/monitor/router/ambiguous-OCR fixtures |
| Export | ✅ pass | ✅ pass | RFC4180 CSV + JSON |
| Sync | ✅ pass (at 079a079) | ✅ pass | offline queue, idempotency, conflict resolution |
| Assets | ❌ fail (ambiguous `User` — fixed in 3898138, unverified) | skipped | |
| Localization | ✅ pass | ✅ pass (no tests, skips cleanly) | |
| Auth | ❌ fail (ambiguous `User` — fixed in 3898138, unverified) | skipped | |
| Workspace | ❌ fail (ambiguous `User` — fixed in 3898138, unverified) | skipped | |
| Settings | not yet re-checked at 079a079 | | |
| SupabaseKit | ❌ fail at c10fb21 (tools-version 6.1) — fixed in 079a079 (version pin); ambiguous-`User` root cause fixed in 3898138 | | |

**iOS-only packages** (built via `xcodebuild ... -destination 'generic/platform=iOS Simulator'`, real Xcode 16.2 / iOS 18.2 SDK on macos-14 runners):
- OCR: ✅ pass
- Scanner: ✅ pass
- DesignSystem: ❌ fail at c10fb21/079a079 for two different reasons, both fixed — see below.

### Real bugs found and fixed this session (each confirmed by an actual compiler/test-runner error, not code review alone)

1. **LabelParser word-boundary bug** — `"SN12938471"` was mis-parsed as an explicit-label match (truncating to `"12938471"`) instead of falling back to the bare-code guess, because keyword matching had no boundary check. Fixed with an explicit boundary check on both sides of a keyword match.
2. **`isKeywordLine` used `hasPrefix`** instead of exact match, wrongly excluding compound tokens starting with a keyword's letters from the bare-code fallback.
3. **`isPlausibleCode` allowed embedded whitespace**, so multi-word descriptive OCR lines (e.g. `"Some Unrelated Label Text"`) were wrongly guessed as bare serial candidates ahead of an actual barcode reading.
4. **`Asset.normalizedForComparison` only stripped whitespace**, so `"ABC-123"`/`"ABC123"` and `"TAG-001"`/`"tag001"` weren't recognized as duplicates. Now strips all non-alphanumeric characters.
5. **A genuinely wrong test assertion**: `"XYZ"` was asserted to contain no OCR-ambiguous characters, but `Z` is itself confusable with `2` per the documented table. Fixed the fixture to `"XYM"`.
6. **CI ran `swift build`/`swift test` for iOS-only (UIKit/Vision/AVFoundation) packages as plain macOS builds**, which fails outright. Split into `build-and-test-portable` (packages declaring `.macOS(...)`) and `build-ios-only` (xcodebuild against the iOS Simulator destination).
7. **`swift test` fails hard with no `Tests/` directory** — Auth/Workspace/Settings/Localization had none yet. CI now skips the test step gracefully instead of treating it as red.
8. **DesignSystem incorrectly declared `.macOS(.v13)`** — it genuinely depends on `Color(uiColor:)` (UIKit-only), which doesn't compile for macOS at all. Reverted to iOS-only.
9. **SwiftData `@Model` classes need macOS 14, not macOS 13** — `Sync`/`Assets` bumped from `.macOS(.v13)` to `.macOS(.v14)`.
10. **supabase-swift ≥ 2.50.0 requires Swift tools-version 6.1**, which Xcode 16.2's Swift 6.0.3 toolchain (the current "latest-stable" on GitHub's macos-14 runners) cannot parse at all. Verified directly by fetching supabase-swift's tagged `Package.swift` files. Pinned to `"2.30.0"..<"2.50.0"` (spot-checked 2.30/2.40/2.45/2.49 all declare tools-version 5.9/5.10 and have the same APIs used here).
11. **`.glassEffect()` isn't declared in the iOS 18.2 SDK** Xcode 16.2 ships — not an `#available` runtime question, the symbol doesn't exist in this SDK at all. `GlassSurfaceModifier` now always uses `.regularMaterial`. **See "Liquid Glass — must re-evaluate locally" below — this is the most product-visible thing to revisit first on a real Mac.**
12. **The onboarding Sign in with Apple button was a literal no-op** (`// TODO` + empty closure). Implemented `App/SignInWithAppleCoordinator.swift`: real `ASAuthorizationController` flow (random hex nonce, SHA-256-hashed per Apple's requirement, delegate/presentation-context-provider conformance), wired into `RootView.OnboardingView`.
13. **`assets.created_by_user_id` FK bug** — see migration 4 above.
14. **`'User' is ambiguous for type lookup in this context`** (the most recent fix, `3898138`, unverified by CI yet) — `import Supabase` in `SupabaseKit/SupabaseGateway.swift` transitively exposes `Auth.User` at the bare name `User`, colliding with `Core.User`. The `moduleAliases` declared on the SupabaseKit→Supabase package dependency does **not**, in practice, prevent this (confirmed by it being the actual failure). Fixed by explicitly qualifying as `Core.User`. **This is the fix most worth double-checking first** — if it doesn't fully resolve the ambiguity, grep the whole repo for bare `User` (not `Core.User`) in any file that also `import`s something Supabase-derived (`SupabaseKit`, or transitively `Supabase`) and qualify those too.

### Known, deliberately deferred follow-up (not a bug introduced silently — flagged honestly)

- `Core.Asset.createdByUserID` is a non-optional `UserID` (`String`), but the column can now legitimately be `NULL` (fix #13/migration 4 above). A real decode of an asset whose creator's account was deleted would need `createdByUserID: UserID?` — a real but mechanical change across ~33 call sites in `Core`/`Sync`/`Assets`/`Export` and their tests. Not done this session to avoid a wide, hard-to-review change stacked on everything else touched. Until fixed, this only matters for the rare shared-workspace-account-deletion path.
- The Sign in with Apple failure message in `OnboardingView` uses `String(describing: error)`, not an `L10n`-backed localized string like every other user-facing string in the app. Small, isolated fix.

## Pending CI verification (do this first, in this order)

1. **Check the actual current CI run** for commit `3898138` (or whatever is HEAD by the time you read this) at https://github.com/marine-ai-dev/SerialSnap-AI-iOS-app/actions — at last check it was still queued (GitHub's macos-14 runners were congested this session; several runs sat queued for 5–10+ minutes). If still red on Auth/Workspace/Assets/SupabaseKit with the same `'User' is ambiguous` error, the `Core.User` qualification in fix #14 wasn't sufficient — grep for other bare `User` references as described above.
2. Once CI is green (or you're on a Mac and can just run it directly — much faster feedback loop than waiting on shared CI runners):
   ```sh
   for pkg in Core Parsing Export Sync Assets Auth Workspace Settings Localization SupabaseKit; do
     echo "==> Packages/$pkg"
     (cd "Packages/$pkg" && swift build && swift test) || echo "FAILED: $pkg"
   done
   ```
   (SupabaseKit will fetch `supabase-swift` from GitHub the first time — expect a short delay.)
3. Then, still on the Mac:
   ```sh
   xcodegen generate   # reads project.yml at repo root
   open SerialSnap.xcodeproj
   ```
   Get the `SerialSnap` scheme building for an iOS Simulator destination. This is the **first time ever** the `App/` target, `OCR`, `Scanner`, and `DesignSystem` get compiled together as the real app — expect to find and fix integration issues here that no CI job (which only builds packages individually) could have caught.

## Liquid Glass — must re-evaluate locally

`Packages/DesignSystem/Sources/DesignSystem/GlassSurface.swift`'s
`GlassSurfaceModifier` **currently always uses `.regularMaterial`**, not
the real `.glassEffect()` API, because Xcode 16.2 (the newest "latest-
stable" this session's CI resolved to) ships an iOS 18.2 SDK that doesn't
declare `.glassEffect()` at all — referencing it fails to compile
regardless of any `#available` runtime check, since the symbol doesn't
exist in that SDK.

**On your Mac, check what Xcode version you actually have.** If it's
newer than 16.2 and its SDK does declare `.glassEffect()` (Apple's real
Liquid Glass materials API), swap the fallback-only implementation back
to the availability-gated real one — the git history has it (see commit
`079a079`'s diff, reverted from an earlier `if #available(iOS 18.0, macOS
15.0, *) { ... .glassEffect(...) ... } else { ...regularMaterial... }`
structure). Every call site already goes through
`ssGlassSurface(cornerRadius:)` alone, so this is a one-file change.
Don't just copy the old code back verbatim without checking the exact
`.glassEffect(...)` API signature current documentation shows, in case it
changed between when that code was written and whatever SDK you have.

## Supabase configuration / environment requirements for a real run

- `.env.example` (repo root) and `Config/Supabase.xcconfig.example` (`Config/`) list the required variable names only — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APPLE_SIGN_IN_SERVICE_ID`. **No real values are or should ever be committed.**
- Copy `Config/Supabase.xcconfig.example` → `Config/Supabase.xcconfig` (gitignored) and fill in a real (or local `supabase start`) project's URL/anon key before building the app target — `App/AppDependencies.swift` reads this via Info.plist and `fatalError`s with a clear message if it's missing, rather than silently falling back to a hardcoded dev URL.
- To actually run the migrations against a real Supabase project (not the local Postgres shim this container used): `supabase link` then `supabase db push`, per the exact commands in `docs/CLOUD_ARCHITECTURE.md`. **Do not run `supabase/tests/00_local_test_shim.sql` against a real Supabase project** — it already has `auth.users`/`auth.uid()`/the built-in roles; running the shim would be redundant at best and could conflict with Supabase-managed objects at worst.
- Sign in with Apple needs a real Apple Developer Program membership + configured Service ID/key for the `signInWithIdToken` exchange to work end-to-end against a real Supabase Auth project — this is a genuine external-credential requirement, not something fixable in any environment without your Apple Developer account.

## Ordered local implementation/QA checklist

1. Resolve CI (see "Pending CI verification" above).
2. `xcodegen generate`, open the project, get a clean Debug build for iOS Simulator.
3. Fix whatever integration issues surface between `App/`, `OCR`, `Scanner`, `DesignSystem` that per-package CI couldn't catch.
4. Re-evaluate Liquid Glass (see above) once you know your Xcode/SDK version.
5. Launch in Simulator: onboarding → Sign in with Apple (needs real Apple Developer config, see above, but the flow's plumbing/nonce-hashing/delegate wiring can at least be exercised for compile/launch correctness without a successful sign-in) → workspace create/select → scanner permission states → mocked/synthetic-fixture OCR review flow → asset list/search → asset detail/edit/delete → CSV/JSON export via ShareLink → Settings (language, privacy, about, sign out, delete account).
6. SwiftData persistence: confirm `SwiftDataAssetLocalStore`/`SwiftDataWriteQueueStore` actually persist across app relaunch (kill and restart the Simulator app, not just background/foreground).
7. Offline queue: airplane-mode a scan save, confirm it queues locally, confirm it survives app termination, confirm reconnect flushes it exactly once (watch for duplicate assets — the `idempotency_key` unique index should prevent server-side duplicates even on a retried request, but verify the client-side retry logic doesn't double-enqueue).
8. Accessibility pass: VoiceOver labels, Dynamic Type at accessibility sizes (especially Review screen fields, duplicate warnings, serial/model text — nothing should truncate a critical identifier), light/dark appearance on every screen, touch target sizes.
9. Debug build → Release build. Confirm no dev backend URL is hardcoded (should be impossible given `Config/Supabase.xcconfig` is gitignored and required), no debug-only QA utilities leak into Release, no verbose logging of tokens/credentials/full asset records.
10. Attempt an Xcode archive. If it succeeds without a paid Apple Developer signing identity, great — validate it. If signing blocks it, that's a genuine external blocker (see below), not a code defect — don't misdiagnose a signing failure as a build failure or vice versa.
11. Audit `PrivacyInfo.xcprivacy` (currently at `PrivacyManifest/PrivacyInfo.xcprivacy` — **move it into the real `SerialSnap` app target once `xcodegen generate` creates one**) against actual API usage once the app target exists and you can see exactly which required-reason APIs Xcode's build-time privacy report flags.
12. Update `docs/APP_STORE_READINESS.md` and `docs/RELEASE_CHECKLIST.md` with anything discovered as factually true only once actually verified — don't mark an item done from code inspection alone.

## Real iPhone QA (only if a physical device is available)

See `docs/REAL_DEVICE_QA.md` for the full step-by-step checklist. At minimum, on real hardware (none of this is meaningfully testable in Simulator):
- Camera permission grant/deny/recovery flow.
- A real equipment label under real lighting — serial/model/manufacturer/asset-ID extraction accuracy, not synthetic-fixture accuracy.
- OCR ambiguity in the wild: does the O/0, I/1/l, S/5, B/8, Z/2, G/6 confusable-alternates UI actually help correct a real misread?
- Real barcode/QR scan, both agreeing and disagreeing with OCR.
- Duplicate warning shown for a genuinely re-scanned label.
- Offline scan with the device actually in airplane mode (not just Simulator's network-link-conditioner), app force-quit while the write is still pending, relaunch, reconnect, confirm exactly one record synced.
- If you have a second device/simulator signed into the same account: confirm multi-device sync visibility (an asset created on device A appears on device B after reconnect/refresh).
- Sign in with Apple end-to-end (needs the real Apple Developer configuration noted above).
- Account deletion end-to-end against a real Supabase project (the RPC and FK behavior are verified against local Postgres in this session — a real run through the app's Settings → Delete Account UI, against a real Supabase project, has not been done anywhere yet).

## True external blockers (not implementation gaps)

- **No macOS/Xcode/Swift toolchain in this cloud container** — this is the reason this handoff exists; nothing about the app's own code required this, it's a container capability gap.
- **No Apple Developer Program membership/Service ID configured** in this environment — blocks a real end-to-end Sign in with Apple test and code-signed archive. The client-side flow is implemented and should be checkable for compile-correctness without one; a real sign-in and a signed archive need it.
- **No physical iPhone in this environment** — real-camera/real-barcode/real-hardware-offline QA (see above) needs one.
- **No real Supabase project provisioned** — everything backend-related in this session was verified against local Postgres with a shim standing in for Supabase Auth, which is a faithful proxy for schema/RLS/migration correctness but has not been exercised through Supabase's actual Auth/PostgREST HTTP layer, nor through `supabase db push` against a real hosted or `supabase start` local project.

## Exact next command

```sh
git -C /path/to/SerialSnap-AI-iOS-app fetch origin claude/serialsnap-ios-production-6yb4rs
git -C /path/to/SerialSnap-AI-iOS-app checkout claude/serialsnap-ios-production-6yb4rs
```
Then check the GitHub Actions run for commit `3898138` (or later) at
the URL above. If green: proceed straight to `xcodegen generate` (step 2
of "Pending CI verification"). If still showing the `'User' is ambiguous`
error on Auth/Workspace/Assets/SupabaseKit: grep the repo for other bare
`User` references needing `Core.User` qualification, fix, commit, push,
recheck — this is the single most likely remaining loose end.
