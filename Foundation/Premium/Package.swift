// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Premium",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "Premium",
            targets: ["Premium"]),
    ],
    dependencies: [
        .package(name: "PropertyWrapper", path: "../PropertyWrapper"),
        .package(name: "Keychain", path: "../Keychain"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "Premium",
            dependencies: [
                "PropertyWrapper",
                "Keychain",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            linkerSettings: [
                .linkedFramework("StoreKit"),
            ]
        ),
    ]
)
