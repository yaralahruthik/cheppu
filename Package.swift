// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cheppu",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Parakeet TDT v3 on CoreML, per ADR-0001. Reached only by CheppuEngine.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        // The headless core. `Scripts/check-core-is-headless.sh` keeps it from
        // reaching an OS framework, which is what keeps its suite runnable with
        // nothing granted, downloaded or plugged in.
        .target(name: "CheppuCore"),

        // The Engine: Parakeet, the download that puts it on the machine, and
        // nothing else. A target of its own rather than part of the app so that
        // the download can be tested without launching a menu bar.
        .target(
            name: "CheppuEngine",
            dependencies: [
                "CheppuCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),

        // The microphone: the one place Cheppu opens an audio device and asks
        // for Microphone access. A target of its own rather than part of the
        // app so that everything except the device itself — what is asked for
        // and when, what is kept, what is let go of, and the level the Pill
        // draws — is testable with nothing granted and nothing plugged in.
        .target(
            name: "CheppuAudio",
            dependencies: ["CheppuCore"]
        ),

        // The keyboard: the one place Cheppu watches keys it was not sent and
        // the one place it asks for Accessibility. A target of its own rather
        // than part of the app so that what counts as the Hotkey — and what
        // Cheppu does about a key it was not meant to see — is testable with
        // nothing granted and no event tap anywhere near the machine running
        // the suite.
        .target(
            name: "CheppuKeyboard",
            dependencies: ["CheppuCore"]
        ),

        // The pasteboard and the one keystroke Cheppu ever types: Insertion.
        // A target of its own rather than part of the app so that what the
        // Target App is handed, what the user's clipboard looks like
        // afterwards, and what happens when the user has moved on are testable
        // with no clipboard of theirs to borrow and no keystroke ever leaving
        // the suite.
        .target(
            name: "CheppuInsertion",
            dependencies: ["CheppuCore"]
        ),

        // History: the one place Cheppu writes what was said to the disk, and
        // the window the user reads it back in. A target of its own rather than
        // part of the app so that the promises History makes — text and a
        // timestamp and nothing else, a hundred Dictations and no more, a file
        // nobody but its owner can open, and an emptying that leaves nothing
        // behind — are testable against a real file in a temporary directory,
        // with no menu bar launched and the user's own History never touched.
        .target(
            name: "CheppuHistory",
            dependencies: ["CheppuCore"]
        ),

        // The Diagnostics Log: the one file Cheppu writes about itself, and
        // the whole of its diagnostic story — no telemetry, no crash reporter,
        // no analytics. A target of its own rather than part of the app so that
        // the promises the log makes — nothing of what was said anywhere in it,
        // a bound it cannot grow past, and a write that never waits on the path
        // between a user finishing a sentence and the words appearing — are
        // testable against a real file in a temporary directory, with the
        // user's own log never written to.
        .target(
            name: "CheppuDiagnostics",
            dependencies: ["CheppuCore"]
        ),

        // The Pill and the Cues: the one place Cheppu draws over another app's
        // window and the one place it makes a sound. A target of its own rather
        // than part of the app so that where the Pill goes so as not to cover
        // what the user is dictating into, what each Cue sounds like, and what
        // "Cues off" means are testable with no screen to put a panel on and
        // nothing audible ever leaving the suite.
        .target(
            name: "CheppuFeedback",
            dependencies: ["CheppuCore"]
        ),

        // Settings: everything the user can set, and the one window they set it
        // in. A target of its own rather than part of the app so that what a
        // fresh install does before anybody has opened the window — every
        // Cleanup rule on, the Cues audible — and what survives a relaunch are
        // testable against a real preferences domain, without the user's own
        // defaults being written to and with no window ever opened.
        .target(
            name: "CheppuSettings",
            dependencies: ["CheppuCore"]
        ),

        // The OS-facing shell: the menu bar app that renders what the core decides.
        .executableTarget(
            name: "Cheppu",
            dependencies: [
                "CheppuCore", "CheppuEngine", "CheppuAudio", "CheppuKeyboard", "CheppuInsertion",
                "CheppuFeedback", "CheppuHistory", "CheppuSettings", "CheppuDiagnostics",
            ]
        ),

        .testTarget(
            name: "CheppuCoreTests",
            dependencies: ["CheppuCore"]
        ),

        .testTarget(
            name: "CheppuEngineTests",
            dependencies: ["CheppuEngine"]
        ),

        .testTarget(
            name: "CheppuAudioTests",
            dependencies: ["CheppuAudio"]
        ),

        .testTarget(
            name: "CheppuKeyboardTests",
            dependencies: ["CheppuKeyboard"]
        ),

        .testTarget(
            name: "CheppuInsertionTests",
            dependencies: ["CheppuInsertion"]
        ),

        .testTarget(
            name: "CheppuHistoryTests",
            dependencies: ["CheppuHistory"]
        ),

        .testTarget(
            name: "CheppuFeedbackTests",
            dependencies: ["CheppuFeedback"]
        ),

        .testTarget(
            name: "CheppuSettingsTests",
            dependencies: ["CheppuSettings"]
        ),

        .testTarget(
            name: "CheppuDiagnosticsTests",
            dependencies: ["CheppuDiagnostics"]
        ),

        // Accuracy: the real Engine, over audio of the author's own voice,
        // measured against what was actually said. A test target of its own
        // rather than more of `CheppuEngineTests` because it is the one part of
        // the suite a fake would defeat entirely — and because loading 480 MB of
        // Parakeet must never be something `swift test` does on the way past.
        // The measurement runs only under `CHEPPU_ACCURACY`; the arithmetic
        // underneath it runs always, and costs microseconds.
        .testTarget(
            name: "CheppuAccuracyTests",
            dependencies: ["CheppuCore", "CheppuEngine"],

            // The files the fixtures were converted from, kept because the same
            // sentence cannot be said twice: if the Engine ever hears in at
            // something other than 16 kHz, a fixture downsampled to it is not
            // recoverable and the author's voice would have to be recorded
            // again. Excluded rather than made a resource — nothing opens them,
            // and bundling them would put two megabytes into the test binary
            // that no test reads.
            exclude: ["Originals"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
