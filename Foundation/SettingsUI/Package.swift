// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SettingsUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
    ],
    dependencies: [
        .package(path: "../RayonModule"),
        .package(path: "../Premium"),
        .package(path: "../DataSync"),
        .package(path: "../Colorful"),
        .package(path: "../MachineStatus"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "SettingsUI",
            dependencies: [
                "RayonModule",
                "Premium",
                "DataSync",
                "Colorful",
                "MachineStatus",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
    ]
)
