// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CaptureKit",
            targets: ["CaptureKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CaptureKit",
            dependencies: [],
            path: "Sources/CaptureKit"
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit"],
            path: "Tests/CaptureKitTests"
        ),
    ]
)
