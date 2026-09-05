# App Store Readiness Checklist

Tracks what's needed for SerialSnap to pass App Review, separate from
release-build mechanics (see `docs/RELEASE_CHECKLIST.md`) and from the
underlying privacy/security facts this checklist must stay consistent with
(`docs/PRIVACY.md`, `docs/SECURITY.md`).

## Privacy Manifest (`PrivacyInfo.xcprivacy`)

- [ ] A `PrivacyInfo.xcprivacy` file is included in the app target's build.
      A starting template lives at
      `PrivacyManifest/PrivacyInfo.xcprivacy` in this repo — **it must be
      moved into the actual Xcode app target (e.g. `SerialSnap/`) once
      that target exists**, and added to that target's "Copy Bundle
      Resources" build phase (Xcode does this automatically for a file
      named `PrivacyInfo.xcprivacy` added to a target).
  - [ ] `NSPrivacyTracking` = `false` (accurate — see `docs/PRIVACY.md`).
  - [ ] `NSPrivacyCollectedDataTypes` declares Account/User ID data used
        for "App Functionality," linked to identity, not used for
        tracking. Add the "Photos" entry (see template comment) only if/
        when the opt-in photo-attachment feature ships.
  - [ ] `NSPrivacyAccessedAPITypes` declares required-reason API usage
        actually present in the shipped code — at minimum:
        - `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`:
          storing app preferences/state that isn't sent off-device) if
          `UserDefaults` is used anywhere in the app (very likely, for
          simple UI state).
        - `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1`:
          used for display or as part of a document's timestamp within
          the app) if file creation/modification timestamps are read
          (e.g. for locally cached asset attachments).
  - [ ] Before submission, re-check this list against Apple's current
        [required reason API list](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api)
        — Apple updates the list and reason codes periodically, and any
        new required-reason API adopted by a dependency (check third-party
        SwiftPM packages' own privacy manifests too) must be declared.

## App Store privacy questionnaire

- [ ] Answers entered in App Store Connect's "App Privacy" section match
      `docs/PRIVACY.md` exactly:
  - [ ] Data collected: Email/User ID (linked to identity, app
        functionality), Asset inventory data (linked to identity, app
        functionality). Photos only if the opt-in attach-photo feature is
        live.
  - [ ] "Data Used to Track You": **No.**
  - [ ] No analytics, advertising, or third-party data-sharing categories
        are declared, since none are integrated.
- [ ] If any of the above ever changes (a feature adds a new data type, or
      a third-party SDK is added), update `docs/PRIVACY.md`, the
      `PrivacyInfo.xcprivacy` manifest, and the App Store Connect answers
      **together**, in the same release — a mismatch is a rejection risk
      and, if discovered post-release, a compliance issue.

## Info.plist usage-description keys

- [ ] `NSCameraUsageDescription` is present and contains a real, plain-
      language explanation of why the camera is needed, e.g.:
      *"SerialSnap uses your camera to scan serial numbers and barcodes
      on your devices and equipment. Photos are processed on your device
      and are not uploaded unless you choose to attach one to an asset."*
  - [ ] **Localize this string** rather than hardcoding only an English
        value in `Info.plist`: add the key to `Localizable.xcstrings` (see
        the `Localization` package) and reference it via
        `InfoPlist.xcstrings`/`INFOPLIST_KEY_NSCameraUsageDescription`
        build settings so each supported locale gets a properly
        translated, equally clear explanation — a raw hardcoded English
        string in `Info.plist` is a fallback only, not the intended final
        state.
- [ ] `NSPhotoLibraryAddUsageDescription` (or
      `NSPhotoLibraryUsageDescription` if reading is also needed) is added
      if/when the opt-in "attach a photo" feature reads or writes the
      photo library — not required for the OCR/barcode scan flow itself,
      which uses the camera directly via `AVFoundation`/`VisionKit`, not
      the photo library.
- [ ] Re-check for any other usage-description key required by APIs
      actually used by the shipped app (e.g. if biometric unlock via
      Face ID is added, `NSFaceIDUsageDescription` would be required)
      before each submission — this list should be revisited whenever a
      new system capability is adopted, not just at first launch.

## App icon / screenshots

- [ ] **App icon: NOT YET CREATED.** Needs a design asset (all required
      sizes) before an App Store Connect build can be submitted.
- [ ] **App Store screenshots: NOT YET CREATED.** Needs design assets for
      each required device size class before the listing can be
      published. Do not submit with placeholder/programmer-art screenshots.
- [ ] Launch screen storyboard/asset: verify it exists and is not a
      placeholder before submission (tracked with the app icon above,
      since both are visual-design deliverables outside this doc's scope).

## TestFlight steps

1. [ ] Confirm a Release-configuration build with no dev backend URL
       hardcoded (see `docs/RELEASE_CHECKLIST.md`) is archived in Xcode.
2. [ ] Validate the archive (Xcode Organizer → Validate App) — this runs
       many of the same checks App Review will (privacy manifest present,
       Info.plist keys present, entitlements consistent).
3. [ ] Upload the build to App Store Connect via Xcode Organizer or
       `xcrun altool`/`xcrun notarytool` as appropriate.
4. [ ] Wait for the build to finish backend processing (App Store
       Connect emails/shows status); resolve any automated warnings.
5. [ ] Add the build to a TestFlight internal testing group; confirm
       internal testers can install and run it without a public review.
6. [ ] For external TestFlight testing, submit the build for TestFlight's
       (lighter-weight) Beta App Review, and provide test notes describing
       how to exercise the scan flow.
7. [ ] Collect feedback and crash reports from TestFlight before
       proceeding to a full App Store submission.

## Versioning scheme

- **Marketing version** (`CFBundleShortVersionString`, e.g. `1.2.0`):
  semantic-versioning-style `MAJOR.MINOR.PATCH`, bumped for user-visible
  changes; this is what's shown on the App Store listing.
- **Build number** (`CFBundleVersion`): a monotonically increasing integer
  (or timestamp-based value), bumped on **every** build submitted to App
  Store Connect (including TestFlight-only builds) — App Store Connect
  requires a unique build number per marketing version and will reject a
  re-upload with a repeated one.
- Both are set via build configuration/xcconfig (see
  `docs/RELEASE_CHECKLIST.md`), not edited ad hoc in the Xcode project
  file, so the bump is a single, reviewable change.
