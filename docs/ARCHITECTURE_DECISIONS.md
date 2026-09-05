# Architecture Decision Records

This file tracks significant architectural decisions for SerialSnap as
lightweight ADRs. For the current system design itself, see
`docs/CLOUD_ARCHITECTURE.md` — this file is the historical/rationale log,
not a duplicate of that description.

Each entry should be short: context, decision, consequences. Add new
entries at the top (most recent first).

## Format

```
## ADR-NNN: <short title>
Date: YYYY-MM-DD
Status: Proposed | Accepted | Superseded by ADR-NNN

**Context:** What problem or question prompted this decision.

**Decision:** What was decided.

**Consequences:** What this makes easier/harder, and any follow-up work
it implies.
```

---

## ADR-005: Strings via a String Catalog in a dedicated `Localization` package
Date: 2026-09-05
Status: Accepted

**Context:** The product spec requires zero hardcoded user-facing strings
in views and full translatability from a single source of truth.

**Decision:** All user-facing strings live in
`Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`
(a String Catalog), exposed to the rest of the app only through the
type-safe `L10n` enum (`Packages/Localization/Sources/Localization/L10n.swift`).
Views must never construct a localized string from an inline literal.

**Consequences:** Centralizing every key in one catalog with `en` as the
base locale makes translation completeness mechanically checkable and
"zero hardcoded strings" enforceable by code review (search for a literal
`Text("...")`). Adding a new string requires adding a key to the catalog
and a case to `L10n` — a small amount of ceremony traded for translation
completeness guarantees.

---

## ADR-004: Module boundaries as local Swift Packages
Date: 2026-09-05
Status: Accepted

**Context:** The spec requires strict layering — e.g. `Parsing` must never
import UIKit/SwiftUI and must be independently unit-testable.

**Decision:** Every module (`Core`, `DesignSystem`, `Localization`,
`Parsing`, `OCR`, `Scanner`, `Auth`, `Workspace`, `Assets`, `Sync`,
`Export`, `Settings`) is a separate local Swift Package under `Packages/`,
consumed by a thin `App` target, rather than one flat app target or a
single monolithic internal framework.

**Consequences:** Enforces the dependency direction as a build-time
guarantee rather than a code-review convention — `Parsing` declares no
UIKit/SwiftUI dependency in its `Package.swift`, so it cannot accidentally
gain one. `Core`, `Parsing`, `Export`, and the pure-logic parts of `Sync`
build and test on Linux/CI without Xcode (verified in this container — see
`docs/CLOUD_CONTINUATION.md`). Trade-off: more `Package.swift` boilerplate
than a single-target app, and cross-module changes require bumping local
`path:` package dependencies (handled automatically by SwiftPM).

---

## ADR-003: Local cache & offline write queue via SwiftData
Date: 2026-09-05
Status: Accepted

**Context:** A scan must never be lost due to no connectivity, and retried
writes after a dropped network response must not create duplicate assets.

**Decision:** Use SwiftData (iOS 17+) for the on-device asset cache and a
durable, ordered write-operation queue. Each queued write carries a stable
idempotency key (`Packages/Sync/Sources/Sync/WriteQueue.swift`); the
server enforces a unique constraint on `(workspace_id, idempotency_key)`
(see `supabase/migrations/20260901000001_initial_schema.sql`) so a
resubmitted operation is a no-op rather than a duplicate insert. Conflict
resolution between a queued local edit and a newer server-side edit uses
last-write-wins by `updated_at` (`Packages/Sync/Sources/Sync/SyncEngine.swift`).

**Consequences:** The `Sync` package's core logic (idempotency key
generation, queue draining, conflict resolution) is written against
protocol seams (`WriteQueueStore`, `RemoteAssetService`) specifically so it
is unit-testable without SwiftData or a network connection — verified with
`swift test` in this container (see `docs/CLOUD_CONTINUATION.md`).
SwiftData itself is Apple-only and cannot be exercised by `swift test` on
Linux; the concrete SwiftData-backed store is implemented when the app
target is built out in Xcode.

---

## ADR-002: On-device OCR/barcode extraction only — no external vision API, no custom ML model
Date: 2026-09-05
Status: Accepted

**Context:** The product must extract Manufacturer/Model/Serial/Asset
ID/Barcode fields from a photographed label, without uploading raw images
by default and while working fully offline.

**Decision:** Use only Apple's native Vision (`VNRecognizeTextRequest`,
`VNDetectBarcodesRequest`) and AVFoundation/VisionKit APIs, running
entirely on-device (`OCR` package). Field extraction from recognized text
is a pure, deterministic, rule-based parser (`Parsing` package) — no LLM,
no custom Core ML model, no network call for recognition or extraction.

**Consequences:** Enables offline-first scanning and avoids uploading
camera images by default (see `docs/PRIVACY.md`). Pushes complexity into a
well-tested, inspectable rules engine rather than a model's generalization
— accuracy on label formats the rules don't cover will be lower than an ML
approach, which is why the review/edit UI treats extraction as a
best-effort first draft the user confirms, never a silent auto-save.

---

## ADR-001: Cloud backend — Supabase (Postgres + Auth + RLS)
Date: 2026-09-05
Status: Accepted

**Context:** SerialSnap requires authenticated users, isolated workspaces
shared by a small team, and asset records synced across a user's devices,
with server-enforced multi-tenant isolation as the actual security
boundary (not just client-side filtering).

**Decision:** Use Supabase: Postgres as the canonical data store, Supabase
Auth for authentication (Sign in with Apple as the primary provider), and
Row Level Security enforced in Postgres as the only authorization boundary
for tenant isolation. Supabase Storage is not used in milestone 1 since raw
images are not uploaded by default (see ADR-002); it's reserved for a
later, explicitly opt-in "attach a photo" feature.

Alternatives considered: Firebase/Firestore (weaker relational modeling
for workspace membership; a second identity system to reconcile with Sign
in with Apple) and a custom backend (materially more infrastructure to
build/operate for milestone 1 with no offsetting benefit).

**Consequences:** The app depends on the `supabase-swift` client SDK (to
be added when `Sync`/`Auth` are wired to a live project). All authorization
logic must be expressed as SQL migrations under `supabase/migrations/`,
reviewed with the same rigor as application code, and covered by the tests
under `supabase/tests/` (verified for real against a local Postgres 16
instance — see `docs/CLOUD_ARCHITECTURE.md` and
`docs/CLOUD_CONTINUATION.md`). No service-role key is ever embedded in the
shipped app — only the anonymous/public key, safe to ship because every
query still goes through RLS.
