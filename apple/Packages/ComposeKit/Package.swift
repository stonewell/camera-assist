// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ComposeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ComposeKit",
            targets: ["ComposeKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ComposeKit",
            dependencies: [],
            path: "Sources/ComposeKit"
        ),
        .testTarget(
            name: "ComposeKitTests",
            dependencies: ["ComposeKit"],
            path: "Tests/ComposeKitTests"
        ),
    ]
)
