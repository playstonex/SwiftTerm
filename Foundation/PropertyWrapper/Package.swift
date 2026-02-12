// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PropertyWrapper",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PropertyWrapper", targets: ["PropertyWrapper"]),
    ],
    targets: [
        .target(name: "PropertyWrapper", dependencies: []),
    ]
)
