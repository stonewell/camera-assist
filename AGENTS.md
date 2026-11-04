# Agent Guidelines for Camera Assist Monorepo

This document outlines the architectural boundaries, build workflows with `xtool`, and quality gate standards for agents and contributors working in this repository.

---

## 1. Architectural Roles & Boundaries

The repository is organized into distinct layers to enforce clean separation of concerns, testability, and App Clip size constraints:

```
camera-assist/
├── core/                  # Core Rust Workspace (Rule Engine & FFI)
├── apple/
│   ├── Packages/          # Modular Swift Packages (Frameworks & Business Logic)
│   ├── CameraApp/         # Full iOS Main Application
│   └── CameraAppClip/     # Ultra-lightweight App Clip (< 15MB, Zero-Rust)
├── scripts/               # Automation, Verification, & Quality Interceptors
└── fixtures/              # Golden Vectors & Evaluation Datasets
```

### `core/` (Rust Workspace)
- **Role**: Single source of truth for composition rules, geometric reasoning, lighting models, and arbitration.
- **Modules**:
  - `compose-core`: Pure Rust composition rule engine (rules A–G implemented — 19 rules; deferred: `light.sun_in_frame`, `lens.smudge`, `distance.fill_range`; completed in TASK-04), yaw/pitch classification, multi-subject arbitration. Zero UI or platform dependencies.
  - `compose-ffi`: UniFFI-based C/Swift binding layer exporting `LiveComposer` and data structures.
  - `perception-onnx`: (planned — not yet in the workspace) Desktop/eval ONNX model inference.
- **Rule**: All core composition and lighting evaluation algorithms must reside here and match golden test vectors.

### `apple/Packages/` (Modular Swift Packages)
- **`ComposeKit`**: Swift wrapper over UniFFI `compose-ffi` bindings. Exposes actor-isolated `LiveComposer` and Sendable Swift models (TASK-01 completed strict `.binaryTarget` linking without silent mock).
- **`CaptureKit`**: Pure AVFoundation pipeline for 24MP capture, zero shutter lag, responsive capture, `CVPixelBuffer` & EXIF/metadata pass-through, real KVO `RotationCoordinator`, and 60->30fps thermal throttling & restore (completed in TASK-06).
- **`PerceptionKit`**: Vision framework and CoreMotion attitude tracking pipelines (`FrameSyncHub`, 1€ filter, pose estimation).
- **`SyncKit`**: Cross-device E2EE ephemeral session synchronization (Curve25519 + HKDF + AES-GCM, reference/capture packages, session tokens, WebSocket and Bonjour transport abstraction, 17 unit tests; completed in TASK-10). **Strictly 100% pure Swift** with zero C/Rust dependencies.

### `apple/CameraApp/` (Main iOS Application)
- **Role**: Full-featured iOS camera assistant application.
- **Dependencies**: Depends on `CaptureKit`, `PerceptionKit`, `ComposeKit`, and `SyncKit`.
- **Entry**: `CameraApp.swift` (SwiftUI `@main`) providing the viewfinder, HUD toggle, and embedding `PerceptionDebugHUD`.
- **Target Type**: SwiftPM library target built with `xtool`.

### `apple/CameraAppClip/` (App Clip)
- **Role**: Instant, zero-install helper mode experience launched via NFC or App Clip Code.
- **CRITICAL ARCHITECTURAL BOUNDARY**:
  - **Zero Rust / UniFFI**: Must NOT import `ComposeKit`, `compose_ffi`, or any C/Rust static libraries.
  - **Single Dependency**: Only depends on `SyncKit` and standard Apple system frameworks (`SwiftUI`, `AVFoundation`, `CoreMotion`).
  - **Size Ceiling**: Must never exceed the 15 MB uncompressed App Store ceiling (target < 8 MB).

---

## 2. Build Rules with `xtool` & Cargo

`xtool` provides cross-platform building of SwiftPM-based iOS applications on Linux and macOS environments.

### Prerequisites
- **xtool**: Cross-platform SwiftPM build tool installed (`/usr/local/bin/xtool`).
- **Darwin Swift SDK**: Installed at `~/.config/swiftpm/swift-sdks/darwin.artifactbundle`.
- **Rust Toolchain**: Cargo with target `aarch64-apple-ios` installed (`rustup target add aarch64-apple-ios`).

### Build Commands

#### 1. Compile Rust iOS Static Library
```bash
# Via Makefile
make rust-ios

# Or directly via script
./scripts/build-rust-ios.sh aarch64-apple-ios
```
This produces `core/target/aarch64-apple-ios/release/libcompose_ffi.a`.

#### 2. Build CameraAppClip (App Clip)
```bash
# Via Makefile
make dev-camera-clip

# Or directly in directory
cd apple/CameraAppClip && xtool dev build
```
Output bundle: `apple/CameraAppClip/xtool/CameraAppClip.app`.

#### 3. Build CameraApp (Main App) — requires macOS + Xcode
`make dev-camera-app` depends on the `xcframework` target. `ComposeCore.xcframework` can **only** be assembled on macOS with Xcode (`scripts/build-xcframework.sh` merely does a cross-compilation dry-run on non-Darwin hosts and never emits the artifact). On Linux the `xcframework` target fails fast instead of silently producing a ComposeKit that cannot compile.

```bash
# Build Rust static library first
make rust-ios

# Build application (macOS + Xcode only)
make dev-camera-app
# (or cd apple/CameraApp && xtool dev build)
```
Output bundle: `apple/CameraApp/xtool/CameraApp.app`.

> **Linux users**: `make dev-camera-app` is not supported here. Run `make verify` for the structural parity gate (`validate-swift-parity.py`) instead.

**`COMPOSE_REQUIRE_FFI=1`**: hard gate for CI and device builds. When set, `apple/Packages/ComposeKit/Package.swift` calls `fatalError` if `apple/Frameworks/ComposeCore.xcframework` is missing. Without the XCFramework, ComposeKit **fails to compile** — expected, not a bug — because `Generated/compose_ffi.swift` unconditionally references the `compose_ffiFFI` C types/symbols that only the XCFramework headers/modulemap provide. There is no silent mock fallback.

### Target Configuration (`xtool.yml` & `Info.plist`)
Both `apple/CameraApp` and `apple/CameraAppClip` contain:
- `Package.swift`: Declares the library product and target with `path: "."` and explicit `sources`.
- `xtool.yml`: Defines bundle identifier (`bundleID`) and `infoPath: Info.plist`.
- `Info.plist`: Defines bundle name, display name, permissions (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`), and App Clip metadata.
- Note: Build artifacts in `xtool/` and `.bsp/` are ignored in `.gitignore`.

---

## 3. Quality Gates & Verification

All code changes must pass the automated quality gates before submission:

```bash
# Run full 10-step unified verification suite
./scripts/verify-all.sh
# (or: make verify / make test)
```

The unified verification pipeline enforces:
1. **Rust Format Check**: `cargo fmt --check`
2. **Clippy Linter**: `cargo clippy --workspace --benches --tests -- -D warnings`
3. **Rust Workspace Tests**: `cargo test --workspace`
4. **Golden Vector Runner**: `cargo test -p compose-core --test golden_runner` (validates 20 golden test vectors, `001`–`020`; asserts exact count derived from `EXPECTED_VECTORS` constant with exact finding-set equality per vector)
5. **Microbenchmarks SLA**: `cargo bench --workspace -- --test` (engine & FFI latency SLAs)
6. **Model Manifest Audit**: `python3 scripts/audit-models.py`
7. **App Clip Isolation & Size**: `python3 scripts/check-appclip-size.py` (verifies zero Rust/UniFFI leakage and real compiled `.app` bundle size ceiling, falling back to source bytes with an explicit warning; established in TASK-02)
8. **Swift Parity & Tests**: `scripts/run-swift-tests.sh` (on Linux this runs `validate-swift-parity.py`, enforcing field-level struct and 19-joint enum schema parity against `compose-core` plus exact 20 golden vector schema parity; established in TASK-02; on macOS with a Swift toolchain it executes real package tests)
9. **Desktop Decoders Audit**: `python3 scripts/audit-image-decoders.py`
10. **24MP Capture Benchmark**: `python3 scripts/evaluate-capture-quality.py --self-test` (output explicitly labelled `SYNTHETIC_SELF_TEST`; established in TASK-02)

### App Clip Size & Decoupling Gate
To verify App Clip compliance independently:
```bash
python3 scripts/check-appclip-size.py
```
This script scans all Swift/C source files in `apple/CameraAppClip` and `apple/Packages/SyncKit` for forbidden Rust/UniFFI tokens and measures the real compiled `.app` bundle size (`apple/CameraAppClip/xtool/CameraAppClip.app`), reporting `du` disk usage and payload bytes against the 15 MB ceiling (falling back to uncompressed source bytes with an explicit warning or via `--source-only`).

### ComposeKit Linking Constraint

`ComposeKit` must be linked against the Rust static library via `apple/Frameworks/ComposeCore.xcframework`. When it is missing, ComposeKit does **not** fall back to a mock `LiveComposer`; it fails to compile (missing `compose_ffiFFI` C symbols). `COMPOSE_REQUIRE_FFI=1` turns the missing XCFramework into an explicit manifest-level `fatalError` (TASK-01). Any verification run where `LiveComposer.isMockMode == true` must still be treated as **failed** — mock-mode results are never acceptable as acceptance evidence.
