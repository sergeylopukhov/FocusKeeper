// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusKeeper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FocusBackend",
            targets: ["FocusBackend"]
        ),
        .executable(
            name: "focuskeeper-debug",
            targets: ["focuskeeper-debug"]
        ),
        .executable(
            name: "FocusKeeperApp",
            targets: ["FocusKeeperApp"]
        )
    ],
    targets: [
        .target(
            name: "FocusBackend"
        ),
        .executableTarget(
            name: "focuskeeper-debug",
            dependencies: ["FocusBackend"]
        ),
        .executableTarget(
            name: "FocusKeeperApp",
            dependencies: ["FocusBackend"]
        )
    ]
)
