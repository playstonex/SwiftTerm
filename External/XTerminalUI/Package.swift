// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "XTerminalUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "XTerminalUI",
            targets: ["XTerminalUI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "XTerminalUI",
            dependencies: [],
            resources: [.copy("xterm")]
        ),
    ]
)
