# Release Checklist

Concrete pre-submission checklist to run through before shipping a new
SerialSnap build to TestFlight or the App Store. Complements
`docs/APP_STORE_READINESS.md` (App Review/store-listing readiness) and
`docs/REAL_DEVICE_QA.md` (manual functional QA) — this document is about
build hygiene and process.

## Build configuration

- [ ] Building with the **Release** configuration/scheme, not Debug — verify
      in Xcode's scheme editor ("Archive" action uses Release) and in any
      CI archive step.
- [ ] `swift_flags`/compiler flags confirm optimizations are enabled for
      the Release configuration (default Xcode template settings do this;
      verify nothing overrides it back to `-Onone`).
- [ ] No `#if DEBUG`-only backend/mock endpoints are reachable from a
      Release build (verify by grepping for `DEBUG` guards in networking
      code and confirming the guarded branch is genuinely excluded from
      Release).

## No debug logging in Release

- [ ] No verbose request/response logging (headers, tokens, response
      bodies) is enabled in a Release build. Prefer a logging shim that
      compiles to a no-op (or minimal, non-sensitive) log level outside
      Debug, rather than relying on remembering to remove `print()`
      statements.
- [ ] Grep the diff for stray `print(`, `debugPrint(`, or `dump(` calls
      added during development before tagging a release build.
- [ ] Confirm no access/refresh tokens, emails, or full asset records are
      ever written to the system log (`os_log`/`Logger`) even at a
      non-debug level — logs can be collected via device diagnostics.

## No dev backend URL hardcoded

- [ ] The Supabase project URL and anon key are **not** literal strings in
      Swift source. They are read from build configuration (`.xcconfig`
      files per configuration — e.g. `Debug.xcconfig` pointing at a dev/
      staging Supabase project, `Release.xcconfig` pointing at production)
      injected via `Info.plist` placeholders or a generated config, per
      `docs/CLOUD_ARCHITECTURE.md`.
- [ ] Verify the Release build actually resolves to the **production**
      Supabase project — not staging/dev — by inspecting the compiled
      `Info.plist`/config values in the archived build, not just the
      source `.xcconfig` file (a misconfigured build phase can silently
      keep using dev values).
- [ ] Confirm the production Supabase project has RLS enabled on every
      relevant table (see `docs/SECURITY.md`) — a staging project having
      it enabled does not guarantee production does if migrations were
      applied out of order or manually.

## Signing and provisioning

- [ ] A valid Distribution certificate and App Store provisioning profile
      are selected (or "Automatically manage signing" is enabled and
      resolves without errors) for the Release/Archive build.
- [ ] Entitlements match what's actually used (e.g. Sign in with Apple
      capability is enabled if that feature ships) — mismatched
      entitlements are a common App Review rejection reason.
- [ ] Push notification / background modes entitlements (if used for sync)
      are present only if actually needed, and match what's declared to
      App Review.

## Version / build number bump

- [ ] Marketing version (`CFBundleShortVersionString`) bumped following
      the scheme in `docs/APP_STORE_READINESS.md` if this is a
      user-visible release.
- [ ] Build number (`CFBundleVersion`) bumped to a value higher than any
      previously uploaded for this marketing version.
- [ ] Both are changed via the build-configuration mechanism (not a
      manual edit buried in the `.pbxproj`), so the bump shows as a clear,
      reviewable diff.

## Regression test pass

- [ ] `swift test` passes for every package under `Packages/*` (CI green
      on the release branch/tag — see `.github/workflows/ci.yml`).
- [ ] Supabase migration validation job is green (migrations apply
      cleanly against a clean database).
- [ ] Full manual pass of `docs/REAL_DEVICE_QA.md` completed on at least
      one real device on the current shipping iOS version, with results
      recorded per that document's sign-off section.
- [ ] Any known failing/waived QA step is explicitly listed here with a
      one-line rationale for shipping anyway, rather than silently
      skipped:
  - _(none at this time)_

## Changelog

- [ ] User-facing changelog/release notes drafted for the App Store
      Connect "What's New in This Version" field — written for end users,
      not a raw commit log.
- [ ] Internal changelog entry (if this repo maintains one) added
      summarizing notable changes for future reference, including any
      security- or privacy-relevant change that should also be reflected
      in `docs/SECURITY.md`/`docs/PRIVACY.md`.

## Final sign-off

- [ ] All checkboxes above are checked (or explicitly waived with
      rationale) before archiving the build that will be submitted.
- [ ] The person submitting has read the current
      `docs/APP_STORE_READINESS.md` and confirmed nothing there has
      regressed since the last release.
