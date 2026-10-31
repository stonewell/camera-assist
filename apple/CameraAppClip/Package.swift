// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameraAppClip",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CameraAppClip",
            targets: ["CameraAppClip"]
        ),
    ],
    dependencies: [
        .package(path: "../Packages/SyncKit")
    ],
    targets: [
        .target(
            name: "CameraAppClip",
            dependencies: [
                .product(name: "SyncKit", package: "SyncKit")
            ],
            path: ".",
            sources: ["AppClipStub.swift"]
        ),
    ]
)
