# SerialSnap — Asset & Serial Number Scanner

A cloud-first native iOS app that scans device labels (serial numbers,
asset tags, barcodes) entirely **on-device**, then syncs a minimal
structured record of each asset to a shared, multi-tenant cloud backend so
a team's inventory stays in sync across devices.

## Architecture at a glance

- **Cloud is the source of truth**: Supabase (Postgres + Auth + Row Level
  Security). See `docs/ARCHITECTURE_DECISIONS.md` (ADR-001) and
  `docs/CLOUD_ARCHITECTURE.md`.
- **OCR/barcode extraction is 100% on-device**, via Apple's Vision/
  AVFoundation APIs only — no external vision API, no LLM, no custom Core
  ML model (ADR-002). Extraction into fields (Manufacturer/Model/Serial/
  Asset ID) is a deterministic, pure-Swift rules engine (`Parsing`
  package), not a model.
- **Offline-first**: a local write queue (SwiftData) means a scan is never
  lost without connectivity; retries are idempotent (ADR-003).
- **Server-enforced multi-tenant isolation**: Row Level Security policies
  in Postgres, not client-side filtering — verified with a real test run
  against a live Postgres instance (see `docs/CLOUD_ARCHITECTURE.md` and
  `docs/CLOUD_CONTINUATION.md`).
- **Modular by package**: every layer (`Core`, `DesignSystem`,
  `Localization`, `Parsing`, `OCR`, `Scanner`, `Auth`, `Workspace`,
  `Assets`, `Sync`, `Export`, `Settings`) is an independent local Swift
  Package under `Packages/`, consumed by the thin `App` target (ADR-004).

## Repository layout

```
App/                      SwiftUI app target (thin — composes the packages)
Packages/
  Core/                   Domain models (Asset, Workspace, User, SyncStatus) — pure Swift
  Parsing/                Deterministic field extraction + OCR ambiguity handling — pure Swift
  Export/                 CSV/JSON export — pure Swift
  Sync/                   Offline write queue, idempotency, conflict resolution — pure Swift
  OCR/                    Vision/AVFoundation wrappers — iOS only
  Scanner/                Camera capture + permission states — iOS only
  Auth/                   Sign in with Apple session state machine — iOS-leaning
  Workspace/              Workspace create/select/membership state — iOS-leaning
  Assets/                 Asset repository, duplicate detection, search — pure Swift + Core/Sync/Parsing
  Settings/               Settings screen view-model logic
  DesignSystem/           Semantic colors, Liquid-Glass-style surfaces, Dynamic Type text styles
  Localization/           Localizable.xcstrings (String Catalog) + type-safe L10n accessors
supabase/
  migrations/             Versioned SQL: schema + Row Level Security policies
  tests/                  SQL tests proving cross-tenant access is denied
docs/                     Architecture, security, privacy, testing, and continuation docs
project.yml               XcodeGen spec (generates SerialSnap.xcodeproj on macOS)
```

## Setup

**Requirements**: Xcode 16+, iOS 17+ deployment target, a Supabase project.

1. Generate the Xcode project (macOS only):
   ```sh
   brew install xcodegen
   xcodegen generate
   open SerialSnap.xcodeproj
   ```
2. Copy `.env.example` to `.env` and fill in your Supabase project's URL
   and anon key (see `docs/CLOUD_ARCHITECTURE.md`).
3. Apply the database schema to your Supabase project:
   ```sh
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```
4. Build and run the `SerialSnap` scheme on a simulator or device.

To run the pure-Swift package unit tests individually (no Xcode project
needed — these build with the Swift toolchain alone):

```sh
cd Packages/Core && swift test
cd Packages/Parsing && swift test
cd Packages/Export && swift test
cd Packages/Sync && swift test
cd Packages/Assets && swift test
```

See `docs/TESTING.md` for the full testing strategy and
`docs/CLOUD_CONTINUATION.md` for exactly what has and has not been
verified in this development environment so far, plus the next milestone.

## Status

This is milestone 1 (foundation) of a multi-milestone build. See
`docs/CLOUD_CONTINUATION.md` for the authoritative, up-to-date state of
what exists, what's verified, and what's next.
