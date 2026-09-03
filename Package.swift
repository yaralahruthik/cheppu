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

        // The OS-facing shell: the menu bar app that renders what the core decides.
        .executableTarget(
            name: "Cheppu",
            dependencies: ["CheppuCore", "CheppuEngine", "CheppuAudio", "CheppuKeyboard"]
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
    ],
    swiftLanguageModes: [.v6]
)
