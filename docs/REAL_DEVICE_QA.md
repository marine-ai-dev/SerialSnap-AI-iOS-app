# Real Device QA Checklist

Manual checklist for validating SerialSnap on a real iPhone. Automated
tests (`docs/TESTING.md`) cover logic; this checklist covers everything
that depends on real camera hardware, real network conditions, real
permission prompts, and real multi-device behavior, none of which are
meaningfully simulated in CI.

Use two physical devices signed into the **same** SerialSnap account for
the multi-device sync section. Prefer running this whole checklist once
before each TestFlight build and once before each App Store submission
(see `docs/RELEASE_CHECKLIST.md`).

## 1. Camera permission

1. Fresh install the app (or reset privacy permissions: Settings →
   SerialSnap → reset, or delete/reinstall).
2. Launch the app and navigate to the scan screen for the first time.
   **Expected:** The system camera-permission prompt appears, showing the
   custom usage-description string (not a generic/blank message).
3. Tap **Don't Allow**.
   **Expected:** The app does not crash; it shows an in-app explanation
   that camera access is required to scan, with a path to Settings to
   grant it (not a silent blank screen).
4. Go to iOS Settings → SerialSnap → enable Camera, return to the app.
   **Expected:** The scan screen now works without needing to relaunch
   the app, or the app clearly instructs the user to relaunch if a
   relaunch is genuinely required.

## 2. Camera launch

5. From a clean app state, tap the scan/add-asset button.
   **Expected:** The camera preview appears within ~1 second on a modern
   device, no black-screen flash longer than a normal transition.
6. Rotate the device (if the scan screen supports rotation) or background
   and foreground the app while the camera is active.
   **Expected:** Camera preview recovers correctly; no frozen frame, no
   crash.

## 3. Label text scan (OCR)

7. Point the camera at a printed asset/serial-number label with clear,
   well-lit text.
   **Expected:** The app highlights/detects text within a couple of
   seconds and surfaces a candidate serial number.
8. Repeat with a label at a slight angle (~20-30°) and in dimmer lighting.
   **Expected:** Detection still succeeds, or the app gives a clear
   "move closer / improve lighting" hint rather than silently failing.

## 4. Serial extraction accuracy

9. Scan at least 5 different real (or realistic mock) labels with varying
   formats (e.g. alphanumeric with dashes, all-digits, mixed case).
   **Expected:** For each, the extracted serial number exactly matches
   what's printed on the label, or the app flags low confidence rather
   than silently accepting a wrong value.
10. Scan a label with a serial number adjacent to other text (model
    number, manufacture date).
    **Expected:** The app extracts the serial number specifically, not an
    unrelated adjacent number, or clearly lets the user pick among
    candidates.

## 5. Barcode scan

11. Point the camera at a barcode (1D, e.g. Code128/UPC) on a label.
    **Expected:** Detected quickly, decoded value shown, and correctly
    mapped to a field (e.g. serial number or SKU) on the review screen.
12. Repeat with a 2D barcode (QR/DataMatrix) if the app supports it.
    **Expected:** Same as above — correct decode, correctly mapped.

## 6. OCR ambiguity handling

13. Scan a label with a character that's commonly ambiguous (e.g. `0` vs
    `O`, `1` vs `I`/`l`, `5` vs `S`).
    **Expected:** The app either resolves it correctly via context, or
    flags the field as low-confidence / highlights the character for the
    user to confirm on the review screen — it must not silently save a
    wrong character without giving the user a chance to notice.
14. Scan a blurry or partially obscured label.
    **Expected:** App declines to extract a confident result rather than
    guessing silently, and invites a re-scan.

## 7. Review screen

15. After a successful scan, confirm the review screen shows all
    extracted fields, each is editable, and required fields are marked.
16. Edit a field manually (e.g. correct a misread serial) and proceed.
    **Expected:** The edited value — not the original OCR value — is what
    gets saved.
17. Attempt to save with a required field empty.
    **Expected:** Clear validation message; save is blocked until fixed.

## 8. Save

18. Save a newly reviewed asset.
    **Expected:** It appears immediately in the asset list on the same
    device, with all fields correct.

## 9. Offline scan + airplane mode

19. Enable Airplane Mode on the device.
20. Scan a new label and save it as in steps 7-8.
    **Expected:** Scan, OCR, review, and save all work fully offline
    (on-device processing — see `docs/PRIVACY.md`); the asset appears in
    the local list with some visible "pending sync" indicator (if the UI
    has one) rather than an error.
21. While still offline, edit an existing asset and delete another.
    **Expected:** Both operations succeed locally without error.

## 10. Reconnect + sync

22. Disable Airplane Mode (restore connectivity).
    **Expected:** Within a reasonable window (a few seconds to ~1 minute
    depending on network), the pending create/edit/delete from step
    19-21 sync to the backend — any "pending sync" indicator clears.
23. Force-quit and relaunch the app.
    **Expected:** All changes persisted correctly (no data loss, no
    duplicate records created from the offline queue).

## 11. Multi-device sync visibility

24. On Device B (same account, already online), confirm the asset created
    on Device A in step 20 appears without manual refresh (or with a
    simple pull-to-refresh if push-based sync isn't implemented yet).
25. Edit an asset on Device B.
    **Expected:** Device A reflects the edit within the same sync window
    as step 22, and there is no duplicate/conflicting record.
26. Create an asset on Device A and Device B at nearly the same time
    while both are online.
    **Expected:** Both assets are preserved (no silent overwrite of one
    by the other) unless they were genuinely edits to the very same
    record, in which case the conflict-resolution behavior documented for
    `Sync` applies consistently.

## 12. Sign in with Apple

27. From a signed-out state, tap "Sign in with Apple."
    **Expected:** Native Apple sign-in sheet appears; completing it signs
    the user in and lands them on their existing data (if returning) or
    an empty state (if new).
28. Choose "Hide My Email" during Sign in with Apple (new account).
    **Expected:** App functions normally; account is created and usable
    without the app needing the real email address.
29. Sign out, then sign back in with the same Apple ID.
    **Expected:** Previously synced assets reappear.

## 13. Account deletion

30. Navigate to Settings → Account → Delete Account.
    **Expected:** A clear warning that this is irreversible and what will
    be deleted (see `docs/PRIVACY.md`), requiring explicit confirmation.
31. Confirm deletion.
    **Expected:** The app signs the user out and clears local data; on
    attempting to sign back in with the same credentials, no prior asset
    data is present (a fresh account/empty state), confirming server-side
    deletion took effect.
32. On a second device still signed into the now-deleted account (if
    available), attempt an action.
    **Expected:** The app detects the invalid session and prompts
    re-authentication rather than silently continuing to operate.

## Sign-off

Record device model, iOS version, app build number, date, and pass/fail
per numbered step for each QA pass. Any failed step blocks release until
resolved or explicitly waived with rationale in `docs/RELEASE_CHECKLIST.md`.
