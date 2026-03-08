// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SwiftTerminal",
            targets: ["SwiftTerminal"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/playstonex/SwiftTerm.git", branch: "main"),
//        .package(path: "../../External/SwiftTerm")
        
    ],
    targets: [
        .target(
            name: "SwiftTerminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
    ]
)
