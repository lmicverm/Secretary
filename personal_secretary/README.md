# Secretary

Local-first digital secretary for personal + BV documents on **macOS** and **iOS**.

Documents live as a real folder tree (Finder / Files). Classification *is* the path. A rebuildable SQLite + FTS5 index powers search, OCR text, favorites, and expiry reminders. Sync uses **iCloud Drive** when the paid-team entitlements are enabled — no always-on Mac server.

## Requirements

- Xcode 15+ (macOS 14+, iOS 17+)
- A free **Personal Team** is enough to run **SecretaryMac** Debug locally
- A paid Apple Developer team is required for iCloud Drive (`iCloud.be.vermeir.secretary`) and for installing on a physical iPhone

## Open & run (Mac, Personal Team)

Use the **SecretaryMac** scheme. Do **not** run the iOS **Secretary** scheme as “Designed for iPad” on the Mac — that path is a different target and still expects device/iCloud signing.

1. Open [`Secretary.xcodeproj`](Secretary.xcodeproj) in Xcode.
2. In the scheme menu, choose **SecretaryMac** (not **Secretary**).
3. Select the **SecretaryMac** target → **Signing & Capabilities**.
4. Set **Team** to your **Personal Team** (free Apple ID).
5. Leave the configuration as **Debug** (the default for Run). Debug uses [`Secretary-macOS-Debug.entitlements`](Apps/Secretary/Resources/Secretary-macOS-Debug.entitlements): sandbox + file/network access, **no iCloud**. Xcode can then create a Mac development profile.
6. Run (⌘R). The library lives under Application Support (`~/Library/Application Support/Secretary`) unless you pick a custom folder in Settings.

Personal Team = **local library only**. iCloud Drive is not available on a free team.

## iCloud (paid Apple Developer team)

Release builds of SecretaryMac keep iCloud via [`Secretary-macOS.entitlements`](Apps/Secretary/Resources/Secretary-macOS.entitlements).

1. Join the [Apple Developer Program](https://developer.apple.com/programs/).
2. Set **Team** on `Secretary`, `SecretaryMac`, and `ShareExtension` to that paid team.
3. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/), create the iCloud container `iCloud.be.vermeir.secretary` (or change the ID in the Release/iOS entitlements + `LibraryLocation.swift` to match yours).
4. For a Mac Release build, confirm **SecretaryMac** → **Release** still uses `Secretary-macOS.entitlements` (iCloud Cloud Documents + ubiquity container).
5. Run **SecretaryMac** (Release) on Mac, or **Secretary** on an iPhone.

The app already falls back to Application Support when the iCloud container is missing or unsigned — Debug Personal Team uses that path.

Core library smoke checks (no Xcode.app required if Command Line Tools can build):

```bash
cd Packages/SecretaryCore
swift build
swift run SecretarySmoke
```

Regenerate the Xcode project after adding source files:

```bash
python3 Scripts/generate_xcodeproj.py
```

## Library layout

```
Secretary/
  Inbox/
  Personal/{Insurance,Tax,Banking,School,Housing,Identity,Health,Vehicles,Work}/
  BV/{Governance,Tax,Accounting,Banking,Insurance,SocialSecretariat,Contracts,Invoices}/
  .secretary/index.sqlite
```

Filenames: `YYYY-MM-DD__type__short-title.ext`

## Features

| Feature | Mac | iOS |
|---|---|---|
| Import / drag-drop | yes | Photos, Files |
| Document scanner | — | VisionKit |
| AgentMail ingest (email attachments) | yes | yes |
| Classify (move into tree) | yes | yes |
| Find in open PDF (⌘F) | yes | preview find bar |
| Resizable detail split | yes (persisted) | stacked |
| Category list grouped by year / type | yes | yes |
| Invoice paid / unpaid | yes | yes |
| Search (name, notes, OCR, FTS) | yes | yes |
| Reveal in Finder / Open | yes | Share |
| Favorites + iCloud download | yes | yes |
| Duplicate detection (SHA-256) | yes | yes |
| Expiry reminders | yes | yes |
| Share extension → Inbox | — | yes |
| Rebuild index | yes | yes |

## Architecture

- [`Packages/SecretaryCore`](Packages/SecretaryCore) — folder schema, import/classify, SQLite FTS5, OCR (PDFKit + Vision), Spotlight, reminders
- [`Apps/Secretary`](Apps/Secretary) — shared SwiftUI UI + platform targets
- [`Apps/ShareExtension`](Apps/ShareExtension) — “Save to Secretary”

Files on disk are the source of truth. Use **Rebuild Index** if the database ever drifts.

## Document understanding

On-device only. **No cloud LLM** (unless you later opt in).

| Path | When it runs | What it does |
|---|---|---|
| **Heuristic** (default) | macOS 14 / iOS 17+ (current deployment, including Personal Team Debug) | Filename + OCR, NaturalLanguage names, Belgian invoice/tax patterns → title, type, tags, optional amount / dates / correspondent |
| **Foundation Models** (Apple Intelligence) | App built with an SDK that has `FoundationModels` **and** OS **macOS 26 / iOS 26+** | `extractAsync` tries the on-device model first, then falls back to heuristics. The classify/filename path stays sync-heuristic so Move never blocks on a model. |

Classify always writes `YYYY-MM-DD__type__{slug(cleaned title)}.ext` from the cleaned title — never raw OCR tokens (`PfO6D4aa`, `import`, …).

**TODO when raising the deployment target:** implement `DocumentUnderstanding.extractWithFoundationModels` with `LanguageModelSession` + a `@Generable` schema. Keep the heuristic fallback. Weak-link via `#if canImport(FoundationModels)`; `foundationModelsAvailable` already checks OS major version ≥ 26.
