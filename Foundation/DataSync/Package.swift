// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "DataSync",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "DataSync", targets: ["DataSync"]),
    ],
    
    targets: [
        .target(name: "DataSync"),
        
    ]
)
