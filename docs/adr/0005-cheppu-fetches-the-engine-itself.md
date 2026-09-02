---
status: accepted
---

# Cheppu fetches the Engine itself

FluidAudio ships a downloader. `AsrModels.downloadAndLoad()` is one line, puts the model under Application Support, resumes an interrupted transfer by byte range, retries, and validates what it got. Cheppu does not use it. `Sources/CheppuEngine/EngineDownload.swift` asks the repository what the Engine is made of, adds up what it weighs, and fetches it — and `Scripts/check-the-download-is-the-only-network-path.sh` fails the build if anything that can open a connection appears anywhere else in `Sources/`.

Two things drove this, and both are promises the product makes rather than preferences about code.

The first is the total size. A 600 MB download that shows a percentage and no size reads the same whether the remainder is ten seconds or ten minutes, which is how a download comes to look like a stall on the one screen a new user judges the app by. FluidAudio's progress reports a fraction and a file count and no byte total, and it cannot easily report one, because it learns the sizes while listing and never surfaces that listing. Asking the repository ourselves — one request, before a byte is fetched — is where the total comes from.

The second is that "no network access after the Engine download" is the strongest claim Cheppu makes, and it should be checkable by reading one file rather than by trusting a dependency of a hundred. With the download ours, the answer to "what does this app talk to" is a script and a file. FluidAudio's own outbound paths are then shut off at the source: `ParakeetEngine` sets `ModelHub.offlineMode` before anything else touches the library, so a model it decides is corrupt fails loudly instead of quietly re-fetching itself mid-Dictation.

## Considered options

- **`AsrModels.downloadAndLoad()`**: one line, and everything except the total size. Rejected because the size is an acceptance criterion, and because closing that gap would have meant asking the repository for the listing ourselves anyway — adding a second network stack rather than replacing one.
- **A declared constant for the total size**: simplest of all, and wrong within a release. The published bundles are reissued when a conversion bug is fixed, and a constant nobody remembers to edit turns a progress bar into a lie.
- **Downloading the whole repository**: makes the file list trivially correct, at 3.5 GB against the 480 MB the Engine actually runs. The repository carries several encoder precisions, several joints, and the `.mlpackage` sources they were compiled from.

## Consequences

- The Engine lives in a target of its own, `CheppuEngine`, rather than in the app. It is where FluidAudio, CoreML and the one network path are, and having it apart from the menu bar is what lets the download's resume be tested against a stubbed repository without launching an app or fetching 480 MB.
- The file names come from FluidAudio's own `ModelNames`, not from a list written out in Cheppu, so the files the download fetches and the files FluidAudio later opens cannot drift apart across a version bump.
- Retry and back-off are not reimplemented. A failed download throws, keeps what arrived, and resumes when it is asked again — which is what the user's "try again" already means.
- The revision fetched is `main` rather than a pinned commit, so a reissued bundle reaches users without an edit here. The cost is that the total size can change between two runs; it is read fresh each time rather than remembered.
- CI gains a second guard script alongside the headless-core one, and the core suite still runs with no Engine downloaded and no network.
