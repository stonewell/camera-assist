// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PerceptionKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PerceptionKit",
            targets: ["PerceptionKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PerceptionKit",
            dependencies: [],
            path: "Sources/PerceptionKit"
        ),
        .testTarget(
            name: "PerceptionKitTests",
            dependencies: ["PerceptionKit"],
            path: "Tests/PerceptionKitTests"
        ),
    ]
)
