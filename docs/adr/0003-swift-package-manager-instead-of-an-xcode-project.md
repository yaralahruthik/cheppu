---
status: accepted
---

# Swift Package Manager instead of an Xcode project

Cheppu is built as a Swift package — a `CheppuCore` library target, a `Cheppu` executable target, and a test target — with `Scripts/make-app.sh` assembling `Cheppu.app` around the built executable. There is no `.xcodeproj`.

The core/shell split the project requires is a target boundary, and SwiftPM expresses that boundary in fifteen readable lines of `Package.swift` rather than in a project file no one reads and every merge fights over. It also means the whole build is reproducible from a checkout with only the Command Line Tools installed, which matters for an open-source app whose contributors should not need a 15 GB download to fix a Cleanup rule. `swift build` and `swift test` are the whole of the local workflow that touches code; the two scripts in `Scripts/` only assemble the bundle and guard the core's boundary, and CI runs exactly what a contributor runs.

## Considered options

- **An Xcode project**: the default for a macOS app, with signing, entitlements and the app bundle handled by the IDE. Rejected because the project file is the least reviewable artefact in the repo, and because it makes Xcode a hard requirement for anyone who wants to run the test suite.
- **XcodeGen or Tuist generating a project from a manifest**: keeps the manifest reviewable, but adds a build-time dependency and a generation step to get back to where SwiftPM already is.

## Consequences

- The app bundle is assembled by a script, not by a build system. `App/Info.plist` is a committed file, so `LSUIElement` and the minimum system version are read directly rather than derived from build settings. The permission usage descriptions join it as each permission's own ticket lands, since a usage description for a permission the app never requests is a promise it cannot keep.
- Signing and notarization operate on the bundle the script produces, and are a CI step rather than an Xcode setting.
- The Swift Testing suite needs a toolchain that ships the testing runtime. Xcode provides it; the Command Line Tools alone can compile and link the suite but cannot run it, so contributors without Xcode rely on CI for the test result.
- SwiftUI views, added by later tickets, live in the executable target and are built by SwiftPM like any other source. No storyboards, xibs or asset catalogues are used.
