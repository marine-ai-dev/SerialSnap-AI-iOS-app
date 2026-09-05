# Privacy

SerialSnap is a **cloud-first** app: to make a user's scanned asset inventory
available across their own devices, structured asset data is synced to a
Supabase backend the user's account controls access to. This document states
plainly what is and is not collected, so it should never be read as "no data
leaves the device" — it does, by design, because sync is a core feature. For
backend/system layout see `docs/CLOUD_ARCHITECTURE.md`; for how that data is
protected in transit and at rest, see `docs/SECURITY.md`.

## What is collected

**Account data**

- Email address (or Apple-provided identifier, if the user signs in with
  Apple) and a stable user ID, used solely to authenticate the user and
  scope their data.

**Asset inventory data (structured fields only)**

- The structured fields a scan produces and the user confirms/edits on the
  review screen: e.g. serial number, model/product name, category, notes,
  scan timestamp, and any tags the user adds.
- Workspace/organization membership, if the user is part of a shared
  workspace.

**What is explicitly NOT collected**

- **Raw camera images are not uploaded or retained by default.** Camera
  frames are used transiently, on-device, to run OCR and barcode detection;
  once the structured fields are extracted and confirmed, the underlying
  image is discarded unless the user explicitly opts to attach a photo to
  an asset record as part of that asset's notes (a deliberate, visible
  user action — not a background upload of camera data).
- No third-party analytics SDKs.
- No advertising SDKs or ad identifiers.
- No third-party/cloud vision or OCR APIs — text and barcode recognition
  run on-device using Apple's Vision/VisionKit frameworks (see `OCR` and
  `Scanner` packages), so scanned images and text are never sent to an
  external recognition service.
- No location data.
- No contacts, photo library access beyond what's needed for the
  user-initiated "attach a photo" action described above, or microphone
  access.

## On-device processing

- Barcode and label-text recognition happen entirely on-device via Apple's
  native frameworks. The only data that leaves the device as part of a scan
  is the structured result the user reviews and confirms — not the image
  or video frames themselves.
- This means SerialSnap can create and edit asset records fully offline;
  sync to the backend happens opportunistically when connectivity is
  available (see `docs/REAL_DEVICE_QA.md` for the offline/reconnect test
  flow).

## No third-party analytics, ads, or external vision APIs

To be explicit, since this is a common App Store review question:
SerialSnap does not integrate any third-party analytics platform, does not
serve or measure advertising, and does not send images or scan data to any
external (non-Apple, non-Supabase) service. The only network destination
for user data is the project's own Supabase backend, used to sync the
user's own data back to their own devices.

## Data retention

- Asset and account data is retained for as long as the account exists.
- A user can delete individual asset records at any time from within the
  app; deletion is synced to the backend and removed from all the user's
  devices.
- Locally cached data (on-device copies used for offline access) is
  cleared on sign-out.

## Account and data deletion

Users can delete their account and all associated data from within the app
(Settings → Account → Delete Account). Deleting an account:

1. Deletes all asset records owned by that user from the backend.
2. Deletes the user's account/auth record from Supabase Auth.
3. Clears all locally cached data and tokens on the requesting device.
4. Is irreversible — there is no "undo" or recovery window once confirmed,
   and this is stated to the user before they confirm.

If a user is a member of a shared workspace, deleting their personal
account removes their personal data and membership; it does not delete
assets owned by the workspace itself unless they are the sole owner and
choose to delete the workspace as a separate, explicit step.

## App Store "nutrition label" mapping

For the App Store Connect privacy questionnaire (App Privacy details), this
app should declare:

| Data type | Linked to identity? | Used for tracking? | Purpose |
|---|---|---|---|
| Email address / User ID | Yes | No | Account authentication, app functionality |
| Asset inventory data (serial numbers, product names, notes, etc.) | Yes | No | App functionality (the core sync feature) |
| Photos (only if user opts to attach one) | Yes | No | App functionality, at user's request |

- **Tracking: No.** SerialSnap does not link data collected from this app
  with third-party data for advertising, and does not share data with data
  brokers.
- **Data linked to third parties for advertising: No.**
- No data categories beyond the table above should be declared — in
  particular, do not declare "raw images" as collected data unless the
  opt-in photo-attachment feature is shipped and in active use, in which
  case "Photos" should be added as above.

Keep this table in sync with the actual `PrivacyInfo.xcprivacy` manifest
(see `PrivacyManifest/PrivacyInfo.xcprivacy` and
`docs/APP_STORE_READINESS.md`) and with the real answers entered in App
Store Connect before submission — a mismatch between declared and actual
behavior is an App Review rejection risk.
