// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cheppu",
    platforms: [.macOS(.v15)],
    targets: [
        // The headless core. `Scripts/check-core-is-headless.sh` keeps it from
        // reaching an OS framework, which is what keeps its suite runnable with
        // nothing granted, downloaded or plugged in.
        .target(name: "CheppuCore"),

        // The OS-facing shell: the menu bar app that renders what the core decides.
        .executableTarget(
            name: "Cheppu",
            dependencies: ["CheppuCore"]
        ),

        .testTarget(
            name: "CheppuCoreTests",
            dependencies: ["CheppuCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
