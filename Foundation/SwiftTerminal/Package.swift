// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localSwiftTermURL = packageDirectory
    .appendingPathComponent("../../External/SwiftTerm")
    .standardizedFileURL
let useLocalSwiftTerm = FileManager.default.fileExists(atPath: localSwiftTermURL.appendingPathComponent("Package.swift").path)
let swiftTermDependency: Package.Dependency = useLocalSwiftTerm
    ? .package(path: localSwiftTermURL.path)
    : .package(url: "https://github.com/playstonex/SwiftTerm.git", branch: "main")

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
        swiftTermDependency
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
