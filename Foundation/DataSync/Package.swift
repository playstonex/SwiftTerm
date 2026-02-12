// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DataSync",
    platforms: [
        .iOS(.v17),
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
