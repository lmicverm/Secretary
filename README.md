# Secretary

**Local-first digital secretary for Mac and iOS** — organize Personal and BV (Belgian limited company) documents with a folder-based taxonomy synced via iCloud Drive.

Documents live as real files in a Finder/Files-visible folder tree. Classification *is* the path. A rebuildable SQLite + FTS5 index powers search, OCR, favorites, and expiry reminders.

## Getting Started

On a Mac, run scheme **SecretaryMac** (destination **My Mac**). The **Secretary** scheme is the iOS app — use it on an iPhone or Simulator only. **Do not** choose `Secretary` → **My Mac (Designed for iPad)**; that is a scaled iPad binary, not the desktop app, and can abort under Metal API Validation when you click a document.

See [`personal_secretary/README.md`](personal_secretary/README.md) for:

- Requirements (Xcode, Personal Team vs paid Apple Developer)
- How to run scheme **SecretaryMac** (Debug = local library; Release/paid team = iCloud)
- Library layout and naming conventions
- Feature matrix (Mac vs iOS)
- Architecture overview

## Quick Start (Core Package)

If you only want to build the core library without Xcode.app:

```bash
cd personal_secretary/Packages/SecretaryCore
swift build
swift run SecretarySmoke
```

## License

See [LICENSE](LICENSE).
