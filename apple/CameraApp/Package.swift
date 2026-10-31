// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameraApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CameraApp",
            targets: ["CameraApp"]
        ),
    ],
    dependencies: [
        .package(path: "../Packages/CaptureKit"),
        .package(path: "../Packages/PerceptionKit"),
        .package(path: "../Packages/ComposeKit"),
        .package(path: "../Packages/SyncKit")
    ],
    targets: [
        .target(
            name: "CameraApp",
            dependencies: [
                .product(name: "CaptureKit", package: "CaptureKit"),
                .product(name: "PerceptionKit", package: "PerceptionKit"),
                .product(name: "ComposeKit", package: "ComposeKit"),
                .product(name: "SyncKit", package: "SyncKit"),
            ],
            path: ".",
            sources: [
                "CameraApp.swift",
                "CameraFeature/PerceptionDebugHUD.swift"
            ]
        ),
    ]
)
