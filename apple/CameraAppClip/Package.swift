// swift-tools-version: 5.9
import PackageDescription

#if !os(macOS)
let appClipExcludes = ["Assets.xcassets"]
#else
let appClipExcludes: [String] = []
#endif

var appClipResources: [Resource] = [
    .process("PrivacyInfo.xcprivacy")
]
#if os(macOS)
appClipResources.append(.process("Assets.xcassets"))
#endif

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
            exclude: appClipExcludes,
            sources: [
                "AppClipStub.swift",
                "AppClipInvocationParser.swift",
                "AppClipCoordinator.swift",
                "AppClipHelperView.swift"
            ],
            resources: appClipResources
        ),
    ]
)
