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
  - `compose-core`: Pure Rust composition rule engine (Rules A–G, yaw/pitch classification, multi-subject arbitration). Zero UI or platform dependencies.
  - `compose-ffi`: UniFFI-based C/Swift binding layer exporting `LiveComposer` and data structures.
  - `perception-onnx`: Desktop/eval ONNX model inference.
- **Rule**: All core composition and lighting evaluation algorithms must reside here and match golden test vectors.

### `apple/Packages/` (Modular Swift Packages)
- **`ComposeKit`**: Swift wrapper over UniFFI `compose-ffi` bindings. Exposes actor-isolated `LiveComposer` and Sendable Swift models.
- **`CaptureKit`**: Pure AVFoundation pipeline for 24MP capture, zero shutter lag, responsive capture, and iOS 18 Camera Control sliders.
- **`PerceptionKit`**: Vision framework and CoreMotion attitude tracking pipelines (`FrameSyncHub`, 1€ filter, pose estimation).
- **`SyncKit`**: Cross-device E2EE ephemeral session synchronization. **Strictly 100% pure Swift** with zero C/Rust dependencies.

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

#### 3. Build CameraApp (Main App)
```bash
# Build Rust static library first
make rust-ios

# Build application
make dev-camera-app
# (or cd apple/CameraApp && xtool dev build)
```
Output bundle: `apple/CameraApp/xtool/CameraApp.app`.

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
4. **Golden Vector Runner**: `cargo test -p compose-core --test golden_runner` (validates all 13+ golden test vectors)
5. **Microbenchmarks SLA**: `cargo bench --workspace -- --test` (engine & FFI latency SLAs)
6. **Model Manifest Audit**: `python3 scripts/audit-models.py`
7. **App Clip Isolation & Size**: `python3 scripts/check-appclip-size.py` (verifies zero Rust/UniFFI leakage and bundle size budget)
8. **Swift Parity & Tests**: `scripts/run-swift-tests.sh` (validates Swift package declarations and schema parity)
9. **Desktop Decoders Audit**: `python3 scripts/audit-image-decoders.py`
10. **24MP Capture Benchmark**: `python3 scripts/evaluate-capture-quality.py --self-test`

### App Clip Size & Decoupling Gate
To verify App Clip compliance independently:
```bash
python3 scripts/check-appclip-size.py
```
This script scans all Swift/C source files in `apple/CameraAppClip` and `apple/Packages/SyncKit` for forbidden Rust/UniFFI tokens and verifies the uncompressed payload size is safely within budget (< 15 MB).
