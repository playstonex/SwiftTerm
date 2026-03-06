// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NMMoshShell",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "NMMoshShell",
            type: .static,
            targets: ["NMMoshShell"]
        ),
    ],
    dependencies: [
        .package(name: "NSRemoteShell", path: "../../External/NSRemoteShell"),
    ],
    targets: [
        .target(
            name: "NMMoshShell",
            dependencies: [
                "NSRemoteShell",
            ],
            cSettings: [
                .define("MOSH_IOS_BUILD", .when(platforms: [.iOS, .tvOS, .watchOS])),
            ]
        ),
        .executableTarget(
            name: "MoshTest",
            dependencies: ["NMMoshShell"]
        ),
        .testTarget(
            name: "NMMoshShellTests",
            dependencies: ["NMMoshShell"]
        ),
    ]
)
