// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "RayonLiveActivity",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "RayonLiveActivity",
            type: .static,
            targets: ["RayonLiveActivity"]
        ),
    ],
    targets: [
        .target(
            name: "RayonLiveActivity",
            dependencies: []
        ),
    ]
)
