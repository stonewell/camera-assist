// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReviewApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReviewApp",
            targets: ["ReviewApp"]
        ),
    ],
    dependencies: [
        .package(path: "../Packages/ComposeKit")
    ],
    targets: [
        .target(
            name: "ReviewApp",
            dependencies: [
                .product(name: "ComposeKit", package: "ComposeKit"),
            ],
            path: ".",
            sources: [
                "ReviewApp.swift",
                "ReviewFeature/NonDestructiveAdjustmentStore.swift",
                "ReviewFeature/PhotoReviewCoordinator.swift"
            ]
        ),
    ]
)
