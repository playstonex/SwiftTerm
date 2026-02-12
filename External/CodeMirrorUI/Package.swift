// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeEditorUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CodeEditorUI",
            targets: ["CodeEditorUI"]
        ),
    ],
    targets: [
        .target(
            name: "CodeEditorUI",
            resources: [.copy("webpack")]
        ),
    ]
)
