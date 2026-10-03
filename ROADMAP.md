# SwordReader Roadmap

SwordReader is developed as both a launchable Bible app and an integration test
bed for public SwordKit releases. Complete and commit one milestone at a time.

Reviewed October 3, 2026 against `main` through `c01115f`. Framework integration
is merged in PR #16. Current pins are SwordKit 0.6.1, BibleKit 0.3.2, and
BibleUI 0.2.3; physical-device acceptance remains pending.

## Completed

- [x] Shared observable application model
- [x] Public SwordKit 0.6.1 dependency
- [x] Adaptive iPhone, iPad, and Mac navigation shell
- [x] Chapter reading and translation selection
- [x] Cancellable Scripture search
- [x] Local SWORD catalog inspection and installation
- [x] Initial Swift Testing coverage
- [x] Canonical book and chapter navigation with state restoration
- [x] First-launch onboarding and production module-library management
- [x] HTTPS module discovery, licensing review, progress, and cancellation
- [x] Accessible reader typography, spacing, verse-number controls, and headings
- [x] Rich attributed Scripture content, footnotes, and cross references
- [x] Advanced search modes, scope, progress, highlighting, and recent searches
- [x] App-owned study-data persistence and schema migrations
- [x] Parallel translation and original-language comparison
- [x] Reading history, deep links, scene restoration, and multiple windows
- [x] Native watchOS reading with paired module delivery, standalone downloads,
  and book/chapter navigation
- [x] Handoff continuity for reading locations across iPhone, iPad, and Mac
- [x] Optional built-in reading plans, saved progress, and opt-in reminders
- [x] System-aware Dark Mode with optional appearance overrides, non-color-only
  selection states, VoiceOver traits, and native Mac keyboard navigation
- [x] App and Watch privacy manifests with documented no-collection and
  no-tracking posture
- [x] In-app privacy, open-source attribution, and installed-module licensing
  information
- [x] Bounded large-module search presentation with full result counts and
  stale-search isolation
- [x] Off-main Watch chapter decoding with cancellation and stale-load isolation
- [x] Separate English string catalogs for the shared app and Watch, with
  explicit localization for runtime labels, plans, notifications, and errors
- [x] Original app icon artwork and native iOS, iPadOS, macOS, and watchOS icon
  assets
- [x] Pre-release versioning, production bundle identity, launch metadata, and
  independent Watch companion declaration
- [x] Repeatable offline release audit and physical-device/TestFlight acceptance
  checklist
- [x] User-reviewed feature and bug reporting with privacy-safe diagnostics,
  editable GitHub issue drafts, and native Copy and Share alternatives
- [x] User-approved CrossWire, eBible.org, and custom HTTPS SWORD module
  sources with persistent source management and catalog compatibility checks
- [x] System-selected iOS and iPadOS light, dark, and tinted app-icon artwork
  with release-time dimension, opacity, and appearance validation
- [x] GitHub-hosted macOS preview releases with an in-app latest-release check
- [x] Native Settings/Preferences with persistent red-letter controls and confirmed
  deletion of installed modules; shared font/style controls live in the reader toolbar
- [x] System-aware persistent module language filtering, independent per-tab module
  switching, split-reading fixes, and native Mac launch and Settings behavior
- [x] Privacy-first Apple MetricKit crash diagnostics with local-only retention,
  editable review, full-payload sharing, and user-approved GitHub issue drafts
- [x] Independent Bible/keyed-module pane navigation and module switching
- [x] Native selected-text copy, notes, and Pink/Blue/Yellow/Green highlight actions
- [x] Internal SWORD link routing and module-download entry point from the reader menu
- [x] Markup-free search results opening a new tab at the clicked reference
- [x] Persistent selectable/closable split-tab groups with `Reference | Reference`
  titles, session restoration, and splitting back into individual tabs
- [x] Stale-chapter completion protection and Xcode 27/Swift 6.4 local validation
- [x] Continuous build-number policy across marketing versions

## Ordered milestones

### Framework integration baseline

- [x] Adopt tagged BibleKit/BibleKitSword for app and Watch engine operations;
  use BibleUI for regular-book text, reference popovers, and custom-feed catalogs.
  Local macOS tests and generic iOS/watchOS builds pass. Device acceptance and
  extracting the advanced Scripture study renderer remain pending.
- [ ] Continue extracting BibleUI reader/catalog components without losing
  current rendering, study data, links, or offline use.
- [x] Add a user-visible custom-feed path with explicit license and trust
  constraints, bounded HTTPS transport, and session-only content.
- [x] Baseline integration merged in PR #16; macOS tests and iOS/watchOS builds
  passed both locally and on GitHub.
- [ ] Complete device/accessibility acceptance and continued study-renderer
  extraction. Native shutdown reproduction remains a separate SwordKit/host
  safety task.

1. Reader and library polish
   - Add a dedicated Installed Modules section that clearly separates local
     content from modules available to download and provides native management
     actions.
   - Audit and correct compact iPhone layouts, including spacing, safe areas,
     toolbar density, sheets, Dynamic Type, and landscape behavior.
   - Verify shared toolbar typography updates every Bible, book, devotional, and
     split pane live; retain regression coverage for font/style and appearance changes.
   - Verify the adopted BibleUI book/chapter controls' native anchored popovers
     and compact iPhone presentation in the running app.
   - Continue expanding readable book and devotional compatibility. Categorize
     modules currently reported as incompatible, distinguish unsupported content
     from metadata/parser defects, and route reproducible framework problems
     through the SwordKit feedback loop below.
   - Refine Bible text measure, margins, paragraph and verse spacing, headings,
     and responsive layout across iPhone, iPad, and Mac.
   - Verify selected-text/context-menu actions in single and split readers,
     including colored swatches, repeated words, multi-verse selections, module
     attribution, and VoiceOver/keyboard alternatives. The actions are implemented;
     end-to-end usability and consistent selection semantics remain acceptance work.
   - Review the notes/highlights collection and reference deep links across modules.
   - Review help-tag responsiveness using native behavior and accessibility;
     do not claim a fixed hover delay without a measured implementation.

2. Native Read Aloud
   - [ ] Add an optional audible reader for Bible chapters, books, and devotionals
     using Apple's speech synthesis; start with macOS and iPhone/iPad.
   - [ ] Offer play/pause/resume/stop, available system voice and language
     selection, speaking rate, and previous/next chapter or entry controls.
   - [ ] Track and optionally highlight the spoken passage, support continuous
     reading, and restore the user's listening position without autoplay.
   - [ ] Keep playback/session ownership in SwordReader, source content and
     permissions through BibleKit, and reusable controls in BibleUI.
   - [ ] Handle audio interruptions, headphones, background/locked-screen
     playback where supported, accessibility coexistence, and local privacy.
     Validate behavior on devices rather than assuming parity across platforms.
   - [ ] Evaluate standalone Watch narration and audio routing after the larger
     platform reader is validated; tvOS/visionOS app presentation stays deferred.
   - [ ] Respect provider/module terms; saved or exported audio is a separate,
     explicitly permission-gated feature, not part of the initial reader.

3. Siri and Shortcuts
   - [ ] Add app-owned App Intents/App Shortcuts for reading the current chapter
     or a chosen passage, resuming listening, and supported playback controls.
   - [ ] Resolve references and translations through the shared application
     model; when a module is missing, offer the existing translation or an
     explicit download instead of silently installing or speaking different text.
   - [ ] Test discoverability, supported Siri phrases, foreground/background
     execution, locked-device restrictions, cancellation, and clear error results
     on each supported platform. Siri triggers the reader; system speech voices
     provide narration without promising Siri's exact voice.
   - [ ] Keep Siri metadata and invocation behavior out of the content frameworks;
     native in-app playback remains usable without enabling Siri.

4. Liquid Glass layered app icon
   - Rebuild the current book-and-sword mark as editable layers in Apple Icon
     Composer rather than relying only on flattened PNG artwork.
   - Import the existing default, dark, and monochrome artwork and tune Default,
     Dark, Clear Light, Clear Dark, Tinted Light, and Tinted Dark appearances on
     iPhone, iPad, and Mac while keeping the same recognizable silhouette.
   - Provide the native layered watchOS rendering, recognizing that watchOS does
     not currently expose the appearance variants available on iOS and macOS.
   - Verify legibility and contrast at every system-generated size, on varied
     wallpapers, with system tint colors, and with Increase Contrast enabled.
   - Retain the current asset-catalog icons as compatibility fallbacks until the
     minimum supported OS and Xcode release make the Icon Composer asset safe to
     adopt exclusively.

5. Signed automatic Mac updates
   - Add Sparkle 2 to the macOS target after a repeatable release workflow and
     Apple Developer ID signing are available.
   - Publish EdDSA-signed update archives and an appcast alongside GitHub
     Releases, keeping the private update key outside the repository.
   - Add user-controlled automatic update checks while retaining the native
     Check for Updates command.

6. Launch coordination
   - Complete Apple Developer signing, physical-device testing, App Store
     records, screenshots, support and privacy-policy URLs, and beta feedback.

## Platform direction

- iPhone and iPad are the primary product surfaces and use native tab,
  navigation-stack, gesture, pointer, and keyboard behaviors.
- Apple Watch reads locally installed SWORD modules and supports both paired
  iPhone delivery and standalone CrossWire downloads. Its focused interface is
  Digital Crown friendly; search and heavier study tools remain on larger screens.
- macOS retains its native sidebar, commands, keyboard navigation, and windowed
  reading workspace.
- tvOS and visionOS remain later presentation targets. Shared domain values and
  service boundaries must stay UI-independent so each can adopt its own native
  focus or spatial navigation instead of inheriting a touch interface.

## Framework feedback loop

When an app milestone exposes a possible SwordKit issue:

1. Reproduce it directly with public SwordKit.
2. Record the SwordKit and SWORD versions, platform, module, and reference/query.
3. Add a focused regression test in SwordKit.
4. Fix and release SwordKit upstream.
5. Update the pinned SwordKit version here after the release.
