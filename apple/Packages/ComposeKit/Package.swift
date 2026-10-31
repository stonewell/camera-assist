// swift-tools-version: 5.9
//
// TASK-01: ComposeKit must really link the Rust `compose-ffi` static library, and it must
// never silently degrade to a Swift mock.
//
// Why a local binaryTarget (and not `linkerSettings: .unsafeFlags(["-L..."] )`):
//   SwiftPM rejects every package that depends on a package declaring `unsafeFlags`.
//   `apple/CameraApp/Package.swift` depends on ComposeKit by path, so unsafe linker flags
//   would break the CameraApp build outright. A local `.binaryTarget` is the supported,
//   dependency-safe way to ship a prebuilt static library, and it is exactly what
//   `scripts/build-xcframework.sh` produces at
//   `apple/Frameworks/ComposeCore.xcframework` (iOS device + iOS simulator + macOS slices).
//
// `COMPOSE_REQUIRE_FFI=1` is the hard gate for CI and real-device builds: with it set the
// manifest fails fast (`fatalError`) when the XCFramework is missing, instead of producing
// a ComposeKit that cannot evaluate anything.
//
// Linux / missing XCFramework: `hasXCFramework` is false, so no ComposeCore binary target is
// declared. The generated `Sources/ComposeKit/Generated/compose_ffi.swift` references the
// `compose_ffiFFI` C types and symbols unconditionally (only its `import` sits behind
// `#if canImport`), and those declarations come only from the XCFramework headers — so
// ComposeKit FAILS TO COMPILE without the XCFramework. It never silently builds a mock.
// `COMPOSE_REQUIRE_FFI=1` turns that into an explicit manifest error instead of an opaque
// symbol-resolution failure.

import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let xcfPath = packageDir + "/../../Frameworks/ComposeCore.xcframework"
// SwiftPM rejects absolute paths here ("path expected to be relative to package root"),
// so the artifact is referenced relative to this package root.
let xcfRelativePath = "../../Frameworks/ComposeCore.xcframework"
let requireFFI = ProcessInfo.processInfo.environment["COMPOSE_REQUIRE_FFI"] == "1"
let hasXCFramework = FileManager.default.fileExists(atPath: xcfPath)

if requireFFI && !hasXCFramework {
    fatalError("ComposeCore.xcframework missing: run ./scripts/build-xcframework.sh (COMPOSE_REQUIRE_FFI=1)")
}

var targets: [Target] = [
    .target(
        name: "ComposeKit",
        dependencies: hasXCFramework ? ["ComposeCore"] : [],
        path: "Sources/ComposeKit"
    ),
    .testTarget(
        name: "ComposeKitTests",
        dependencies: ["ComposeKit"],
        path: "Tests/ComposeKitTests"
    ),
]

if hasXCFramework {
    // Local binary target shipped by scripts/build-xcframework.sh.
    targets.insert(.binaryTarget(name: "ComposeCore", path: xcfRelativePath), at: 0)
}

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
    targets: targets
)
