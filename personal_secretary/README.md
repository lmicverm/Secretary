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
2. Select your **Team** on targets `Secretary`, `SecretaryMac`, and `ShareExtension`.
3. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/), create the iCloud container `iCloud.be.vermeir.secretary` (or change the ID in entitlements + `LibraryLocation.swift` to match yours).
4. Pick the scheme that matches the device:

| What you want | Scheme | Destination |
|---|---|---|
| Daily Mac desktop app | **SecretaryMac** | My Mac |
| iPhone / iPad | **Secretary** | a physical device or Simulator |

**Do not run `Secretary` → My Mac (Designed for iPad).** That destination is an iOS/iPadOS binary scaled onto the Mac. It looks zoomed and blurry, and Debug + Metal API Validation can abort when you open a document (`synchronizeResource` / `MTLResourceStorageModeShared`). The iOS target now sets `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` so that destination should not appear. If an old Xcode window still offers it, switch to **SecretaryMac**.

If you must debug the iOS app on a Mac anyway, turn off **Scheme → Run → Diagnostics → Metal API Validation** — that only hides the assert; it is not the desktop app.

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
