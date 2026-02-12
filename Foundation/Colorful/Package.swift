// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Colorful",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Colorful", targets: ["Colorful"]),
    ],
    targets: [
        .target(name: "Colorful", dependencies: []),
    ]
)
