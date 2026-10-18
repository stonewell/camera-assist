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
            path: "Sources/ComposeKit",
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Sources/ComposeKit/Generated",
                    "-Xcc", "-fmodule-map-file=Sources/ComposeKit/Generated/compose_ffiFFI.modulemap"
                ])
            ]
        ),
        .testTarget(
            name: "ComposeKitTests",
            dependencies: ["ComposeKit"],
            path: "Tests/ComposeKitTests",
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Sources/ComposeKit/Generated",
                    "-Xcc", "-fmodule-map-file=Sources/ComposeKit/Generated/compose_ffiFFI.modulemap"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "../../../core/target/debug",
                    "-lcompose_ffi"
                ])
            ]
        ),
    ]
)
