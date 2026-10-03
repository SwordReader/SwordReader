# SwordReader Agent Instructions

## Project

SwordReader is a multiplatform SwiftUI Bible app and reference consumer for the
public SwordKit package. It targets iOS, iPadOS, macOS, and a native watchOS
companion. tvOS and visionOS presentation are intentionally deferred.

## Required workflow

Work on one roadmap milestone at a time.

For every milestone:

1. Inspect the existing implementation.
2. Write or update tests first when practical.
3. Implement the smallest complete change.
4. Run the macOS test suite and generic iOS build described in `README.md`.
5. Do not commit unless all tests and builds pass.
6. Review the diff for unrelated changes.
7. Commit the completed milestone with a descriptive message.
8. Stop after the commit unless explicitly instructed to continue.

## SwordKit boundary

BibleKit/BibleKitSword and BibleUI integration is being developed separately.
Use tagged public dependencies and preserve rich content, module identifiers,
study-data destinations, and offline behavior during adoption. Keep navigation,
scenes, persistence, Watch transfer, Handoff, and reminders in the application.

Depend on a tagged public SwordKit release. Do not patch or vendor SwordKit in
this repository. Reproduce framework defects in SwordKit, fix and release them
there, and then update this app's dependency.

## Testing

Use local tests/builds for intermediate milestones to conserve GitHub Actions
usage. Include a generic watchOS build when changing Watch code or shared
dependencies. Source/compiler checks do not replace running-app and physical
device acceptance. Keep `ROADMAP.md` synchronized with committed implementation;
do not mark work in another branch/worktree complete before it lands.

Keep the marketing version separate from a monotonically increasing build
number. Do not reset the build counter for a new marketing version; increment
it for each new distributable/test app build, not ordinary test compilation.

Use Swift Testing only:

```swift
import Testing
```
