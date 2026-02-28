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
        .package(path: "../../External/MachineStatus"),
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
            ]
        ),
    ]
)
