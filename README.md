# SwordReader

[![Apple platform builds](https://github.com/orbeavers14/SwordReader/actions/workflows/ci.yml/badge.svg)](https://github.com/orbeavers14/SwordReader/actions/workflows/ci.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)

SwordReader is a multiplatform SwiftUI Bible reader for iOS, iPadOS, macOS, and
watchOS. It consumes the public `SwordKit` 0.6.0 package and keeps SWORD modules
in the application's Application Support container.

## Open and run

Open `SwordReader.xcodeproj` in Xcode 26 or later. Choose `SwordReader` for iOS
and iPadOS, or `SwordReader-macOS` for macOS.

The current development-preview identity is version `0.3.0` (build 3), with bundle identifiers
under `com.orbeavers14.SwordReader`. Register these identifiers with the Apple
Developer account before creating distribution profiles or App Store records.

SwordKit does not bundle or implicitly download Bible modules. Use **Library →
Get Bibles** to review the privacy notice, browse and search the CrossWire Bible
Society catalog over HTTPS, and download a translation. Download progress can be
cancelled, and publisher-supplied licensing metadata is shown before installation.
**Import Local Catalog** remains available as an advanced offline option for a
SWORD repository containing a `mods.d` directory. Swipe an
installed Bible on iPhone or iPad, or use its context menu on any platform, to
remove it after confirmation.

## Architecture

- `AppModel` is the shared, main-actor application model.
- `SwordScriptureService` is the sole SwordKit integration boundary and keeps
  live library/module objects out of views.
- Immutable app snapshots cross from the service into SwiftUI.
- Compact layouts use a native tab-based hierarchy; iPad and macOS use a
  `NavigationSplitView` workspace.
- Platform-specific commands and toolbar placement stay in platform files.
- App preferences and reading position use `UserDefaults`, which participates in
  normal encrypted device backups; SwordReader does not require an account or server.
- SwordReader contains no advertising or analytics SDKs, does not track people,
  and does not collect personal data. Network access occurs only when the user
  chooses to browse or download modules from CrossWire; the app explains this
  before the first request. App and Watch privacy manifests declare only their
  local, app-scoped preferences access.
- Reader appearance uses semantic Dynamic Type styles with persisted system,
  serif, or rounded design, text-size, spacing, and verse-number choices.
- Publisher-supplied Scripture headings are rendered as accessible headings in
  the native reading flow.
- Supported module markup is rendered as native attributed text with a
  plain-text fallback. Verse notes and parsed cross-references open in a native
  sheet, and Scripture references navigate through the shared reader model.
- Search supports phrase, all-word, regular-expression, Strong’s-number, and
  morphology matching across the whole Bible or either testament. Results are
  ranked, matched text is emphasized, progress is visible, and recent searches
  remain on-device.
- Bookmarks and personal verse notes are stored separately from Bible modules in
  a versioned SwiftData schema with an explicit migration plan. Removing or
  updating a module does not silently delete the app-owned study records.
- Installed translations can be compared in canonical verse alignment. Compact
  layouts stack translations, wider layouts place them side by side, missing
  verses stay explicit, and genuine Strong’s links expose original-language
  relationships without implying links that the modules do not provide.
- Reading history is bounded and deduplicated, `swordreader://read` links carry
  stable module/reference destinations, and each iPad or Mac window owns its own
  restorable reading model. Mac commands follow the focused window.

## Verify

```sh
xcodebuild test \
  -project SwordReader.xcodeproj \
  -scheme SwordReader-macOS \
  -destination 'platform=macOS'
```

CI also builds the generic iOS destination to validate iPhone and iPad support.

For a clean pre-release audit that also validates metadata and compiles Release
configurations for every current platform, run:

```sh
./Scripts/release-check.sh
```

The signing, physical-device, TestFlight, privacy, and store-listing gates are
tracked in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

## App Store privacy summary

- Data collection: None
- Tracking: None
- Required-reason API: app-scoped `UserDefaults` (`CA92.1`)
- User-initiated network services: approved HTTPS SWORD module catalogs and downloads

Recheck this summary and generate Xcode's privacy report before every release,
especially after adding a dependency or network feature.

## Development policy

SwordReader is both a potential shipping application and the reference consumer
for public SwordKit releases. It must depend on a tagged public SwordKit version,
not a modified local copy.

Reproduce framework problems in SwordKit and fix them upstream. After a tagged
SwordKit release contains the correction, update SwordReader's pinned dependency.
Application behavior, persistence, navigation, and presentation remain here.

See [ROADMAP.md](ROADMAP.md) for the ordered product milestones.
