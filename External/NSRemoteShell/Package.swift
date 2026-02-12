// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NSRemoteShell",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NSRemoteShell",
            targets: ["NSRemoteShell"]
        ),
    ],
    dependencies: [
        .package(name: "CSSH", path: "External/CSSH"),
    ],
    targets: [
        .target(
            name: "NSRemoteShell",
            dependencies: ["CSSH"]
        ),
    ]
)
