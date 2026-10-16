// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SyncKit",
            targets: ["SyncKit"]
        ),
    ],
    dependencies: [
        // Strictly ZERO external dependencies or C/Rust bindings
    ],
    targets: [
        .target(
            name: "SyncKit",
            dependencies: [],
            path: "Sources/SyncKit"
        ),
        .testTarget(
            name: "SyncKitTests",
            dependencies: ["SyncKit"],
            path: "Tests/SyncKitTests"
        ),
    ]
)
