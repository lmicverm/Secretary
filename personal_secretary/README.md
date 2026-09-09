# Secretary

Local-first digital secretary for personal + BV documents on **macOS** and **iOS**.

Documents live as a real folder tree (Finder / Files). Classification *is* the path. A rebuildable SQLite + FTS5 index powers search, OCR text, favorites, and expiry reminders. Sync uses **iCloud Drive** — no always-on Mac server.

## Requirements

- Xcode 15+ (macOS 14+, iOS 17+)
- Apple ID with iCloud Drive enabled (falls back to local Application Support if iCloud is unavailable)
- Apple Developer team for device installs and the iCloud container `iCloud.be.vermeir.secretary`

## Open & run

1. Open [`Secretary.xcodeproj`](Secretary.xcodeproj) in Xcode.
2. Select your **Team** on targets `Secretary`, `SecretaryMac`, and `ShareExtension`.
3. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/), create the iCloud container `iCloud.be.vermeir.secretary` (or change the ID in entitlements + `LibraryLocation.swift` to match yours).
4. Run **SecretaryMac** on your Mac, or **Secretary** on an iPhone/simulator.

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
| Classify (move into tree) | yes | yes |
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
