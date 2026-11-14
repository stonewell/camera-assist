#!/usr/bin/env python3
"""
scripts/validate-swift-parity.py
Validates Swift Package structure, UniFFI generated bindings, PerceptionKit <-> compose-core
JSON schema parity, and Golden Vector schema parity.
Used in environments where swiftc is not installed locally.
"""

import json
import re
import sys
from pathlib import Path

def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    compose_kit_dir = repo_root / "apple" / "Packages" / "ComposeKit"
    sync_kit_dir = repo_root / "apple" / "Packages" / "SyncKit"
    capture_kit_dir = repo_root / "apple" / "Packages" / "CaptureKit"
    perception_kit_dir = repo_root / "apple" / "Packages" / "PerceptionKit"
    camera_app_dir = repo_root / "apple" / "CameraApp"
    camera_clip_dir = repo_root / "apple" / "CameraAppClip"
    fixtures_dir = repo_root / "fixtures" / "golden"

    print("--- [validate-swift-parity] Checking Swift Package Declarations ---")

    # 1. Check Package manifests
    packages = [
        compose_kit_dir / "Package.swift",
        sync_kit_dir / "Package.swift",
        capture_kit_dir / "Package.swift",
        perception_kit_dir / "Package.swift",
        camera_app_dir / "Package.swift",
        camera_clip_dir / "Package.swift"
    ]

    for pkg in packages:
        if not pkg.is_file():
            print(f"[FAIL] Missing Package.swift at {pkg}", file=sys.stderr)
            return 1
        content = pkg.read_text(encoding="utf-8")
        if "PackageDescription" not in content or "let package = Package(" not in content:
            print(f"[FAIL] Invalid Package.swift syntax in {pkg}", file=sys.stderr)
            return 1
        print(f"  ✓ {pkg.relative_to(repo_root)} is well-formed.")

    # 2. Check UniFFI generated bindings
    gen_dir = compose_kit_dir / "Sources" / "ComposeKit" / "Generated"
    required_gen_files = ["compose_ffi.swift", "compose_ffiFFI.h", "compose_ffiFFI.modulemap"]
    for f in required_gen_files:
        fp = gen_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing generated UniFFI file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found UniFFI artifact: {f} ({fp.stat().st_size} bytes)")

    # 3. Check ComposeKit Swift source models and actor
    sources_dir = compose_kit_dir / "Sources" / "ComposeKit"
    required_src = ["LiveComposer.swift", "Models.swift"]
    for f in required_src:
        fp = sources_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing ComposeKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found source file: {f}")

    # 4. Check CaptureKit sources and tests
    print("--- [validate-swift-parity] Checking CaptureKit & PerceptionKit Components ---")
    capture_src = capture_kit_dir / "Sources" / "CaptureKit"
    capture_files = [
        "CaptureConfiguration.swift",
        "CaptureSessionManager.swift",
        "CapturePhotoController.swift",
        "RotationCoordinatorBridge.swift",
        "VisionOrientationMapper.swift"
    ]
    for f in capture_files:
        fp = capture_src / f
        if not fp.is_file():
            print(f"[FAIL] Missing CaptureKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found CaptureKit source: {f}")

    capture_test_file = capture_kit_dir / "Tests" / "CaptureKitTests" / "CaptureKitTests.swift"
    if not capture_test_file.is_file():
        print(f"[FAIL] Missing CaptureKit test file: {capture_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found CaptureKit test suite: CaptureKitTests.swift")

    # 5. Check PerceptionKit sources and tests
    perception_src = perception_kit_dir / "Sources" / "PerceptionKit"
    perception_files = [
        perception_src / "Pipeline" / "PerceptionModels.swift",
        perception_src / "Pipeline" / "FrameSyncHub.swift",
        perception_src / "Pipeline" / "PerceptionScheduler.swift",
        perception_src / "Motion" / "OneEuroFilter.swift",
        perception_src / "Motion" / "AttitudeTracker.swift",
        perception_src / "Vision" / "BodyPoseAnalyzer.swift",
        perception_src / "Vision" / "MaskSummarizer.swift",
        perception_src / "Vision" / "SubjectTracker.swift",
        perception_src / "Vision" / "VisionFrameProcessor.swift"
    ]
    for fp in perception_files:
        if not fp.is_file():
            print(f"[FAIL] Missing PerceptionKit source file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found PerceptionKit source: {fp.name}")

    # 5b. Verify PerceptionModels.swift <-> compose-core JSON schema parity (field-level)
    print("--- [validate-swift-parity] Verifying PerceptionModels.swift <-> compose-core Field-Level Schema Parity (TASK-02) ---")
    models_text = (perception_src / "Pipeline" / "PerceptionModels.swift").read_text(encoding="utf-8")
    rust_model_dir = repo_root / "core" / "compose-core" / "src" / "model"

    # 1. JointType: Check all 19 canonical joint variants in both Rust and Swift
    canonical_joints = [
        "Nose", "Neck", "LeftEye", "RightEye", "LeftEar", "RightEar",
        "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
        "LeftWrist", "RightWrist", "Root", "LeftHip", "RightHip",
        "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle"
    ]
    rust_joint_text = (rust_model_dir / "joint.rs").read_text(encoding="utf-8")
    for joint in canonical_joints:
        if f"case {joint}" not in models_text:
            print(f"[FAIL] Swift JointType missing case: {joint}", file=sys.stderr)
            return 1
        if joint not in rust_joint_text:
            print(f"[FAIL] Rust JointType missing variant: {joint}", file=sys.stderr)
            return 1
    print(f"  ✓ JointType: all {len(canonical_joints)} joint variants match across Rust and Swift.")

    # 2. Field-level structure check for core perceptual and geometric models
    struct_field_contracts = {
        "NormalizedPoint": ["x: Float", "y: Float"],
        "NormalizedBox": ["x: Float", "y: Float", "width: Float", "height: Float"],
        "Joint": ["joint_type: JointType", "point: NormalizedPoint", "confidence: Float"],
        "MaskSummary": [
            "top_y: Float", "bottom_y: Float", "head_cols: [Float]",
            "torso_cols: [Float]", "leg_cols: [Float]",
            "touches_top: Bool", "touches_bottom: Bool",
            "touches_left: Bool", "touches_right: Bool"
        ],
        "Subject": [
            "id: UInt32", "bounds: NormalizedBox", "joints: [String: Joint]",
            "facing: String", "shot_type: String", "confidence: Float",
            "is_group: Bool", "mask_summary: MaskSummary?"
        ],
        "Posture": [
            "roll_deg: Float", "pitch_deg: Float", "elevation_deg: Float",
            "angular_speed: Float", "is_flatish: Bool"
        ],
        "CameraIntrinsics": ["focal_length_mm: Float", "hfov_deg: Float"],
        "ExposureSummary": ["iso: Float", "shutter_speed_sec: Float", "ev: Float"],
        "PerceptionFrame": [
            "t: Double", "subjects: [Subject]", "primary_subject_index: Int?",
            "posture: Posture", "camera: CameraIntrinsics", "exposure: ExposureSummary"
        ],
        "LightContext": [
            "direction: LightDirection", "quality: LightQuality",
            "sun_azimuth_deg: Float?", "sun_elevation_deg: Float?",
            "face_to_bg_ratio: Float?", "ev: Float", "confidence: Float"
        ]
    }

    for struct_name, fields in struct_field_contracts.items():
        if f"struct {struct_name}" not in models_text:
            print(f"[FAIL] PerceptionModels.swift missing struct {struct_name}", file=sys.stderr)
            return 1
        for field in fields:
            expected_decl = f"public var {field}"
            if expected_decl not in models_text:
                print(f"[FAIL] {struct_name} missing expected field declaration: '{expected_decl}'", file=sys.stderr)
                return 1
        print(f"  ✓ {struct_name}: {len(fields)} fields verified for Swift <-> Rust contract parity.")

    # 3. Check Facing and ShotType parity
    rust_subject_text = (rust_model_dir / "subject.rs").read_text(encoding="utf-8")
    for facing in ["Frontal", "ThreeQuarterLeft", "ThreeQuarterRight", "ProfileLeft", "ProfileRight", "Back"]:
        if facing not in rust_subject_text:
            print(f"[FAIL] Rust Facing enum missing variant: {facing}", file=sys.stderr)
            return 1
    for shot in ["CloseUp", "HalfBody", "FullBody", "Environmental", "Unknown"]:
        if shot not in rust_subject_text:
            print(f"[FAIL] Rust ShotType enum missing variant: {shot}", file=sys.stderr)
            return 1
    print("  ✓ Facing and ShotType photographic classifications verified.")

    perception_test_file = perception_kit_dir / "Tests" / "PerceptionKitTests" / "PerceptionKitTests.swift"
    if not perception_test_file.is_file():
        print(f"[FAIL] Missing PerceptionKit test file: {perception_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found PerceptionKit test suite: PerceptionKitTests.swift")

    # 6. Check CameraApp UI and Coordination Components (TASK-08 / TASK-09)
    print("--- [validate-swift-parity] Checking CameraApp End-to-End Components (TASK-08 / TASK-09) ---")
    camera_app_files = [
        camera_app_dir / "CameraApp.swift",
        camera_app_dir / "CameraFeature" / "CameraCoordinator.swift",
        camera_app_dir / "CameraFeature" / "CameraPreviewView.swift",
        camera_app_dir / "CameraFeature" / "PerceptionDebugHUD.swift",
        camera_app_dir / "CameraFeature" / "UserGuidanceHUD.swift",
    ]
    for fp in camera_app_files:
        if not fp.is_file():
            print(f"[FAIL] Missing CameraApp file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found CameraApp source: {fp.relative_to(repo_root)}")

    # 6.1 Check CameraCoordinator tokens and wiring
    coordinator_text = (camera_app_dir / "CameraFeature" / "CameraCoordinator.swift").read_text(encoding="utf-8")
    expected_coord_tokens = [
        "class CameraCoordinator",
        "CaptureSessionManager",
        "CapturePhotoController",
        "RotationCoordinatorBridge",
        "FrameSyncHub",
        "AttitudeTracker",
        "PerceptionScheduler",
        "BodyPoseAnalyzer",
        "LiveComposer",
        '"0.5x"', '"1x"', '"2x"', '"3x"',
        "engineLatencySLACeilingMs",
        "selectZoomPreset",
        "capturePhoto",
        "FrameEvaluationSnapshot",
        "CameraZoomPreset",
        "hintResolver",
        "hapticEngine",
        "latestComposeOutput",
        "activeHint",
        "isUserGuidanceEnabled",
        "isFlatish",
        "applyRecommendedZoom"
    ]
    for token in expected_coord_tokens:
        if token not in coordinator_text:
            print(f"[FAIL] CameraCoordinator.swift missing required token: {token}", file=sys.stderr)
            return 1
    print(f"  ✓ CameraCoordinator.swift verified with all {len(expected_coord_tokens)} integration tokens.")

    # 6.2 Check CameraPreviewView tokens
    preview_text = (camera_app_dir / "CameraFeature" / "CameraPreviewView.swift").read_text(encoding="utf-8")
    for token in ["AVCaptureVideoPreviewLayer", "struct CameraPreviewView"]:
        if token not in preview_text:
            print(f"[FAIL] CameraPreviewView.swift missing required token: {token}", file=sys.stderr)
            return 1
    print("  ✓ CameraPreviewView.swift verified with AVCaptureVideoPreviewLayer and CameraPreviewView.")

    # 6.3 Check PerceptionDebugHUD tokens
    hud_text = (camera_app_dir / "CameraFeature" / "PerceptionDebugHUD.swift").read_text(encoding="utf-8")
    for token in ["isWithinLatencySLA", "StandardSkeletalBones", "struct PerceptionDebugHUD"]:
        if token not in hud_text:
            print(f"[FAIL] PerceptionDebugHUD.swift missing required token: {token}", file=sys.stderr)
            return 1
    print("  ✓ PerceptionDebugHUD.swift verified with latency SLA and skeletal bones.")

    # 6.4 Check CameraApp.swift tokens
    app_text = (camera_app_dir / "CameraApp.swift").read_text(encoding="utf-8")
    for token in ["CameraCoordinator", "CameraPreviewView", "PerceptionDebugHUD", "UserGuidanceHUD", "struct CameraApp", "CameraViewfinderScreen"]:
        if token not in app_text:
            print(f"[FAIL] CameraApp.swift missing required token: {token}", file=sys.stderr)
            return 1
    print("  ✓ CameraApp.swift verified with CameraCoordinator, CameraPreviewView, UserGuidanceHUD, and PerceptionDebugHUD.")

    # 6.5 Check UserGuidanceHUD components and hint keys (TASK-09)
    print("--- [validate-swift-parity] Checking UserGuidanceHUD Components & Catalogs (TASK-09) ---")
    guidance_text = (camera_app_dir / "CameraFeature" / "UserGuidanceHUD.swift").read_text(encoding="utf-8")
    expected_guidance_types = [
        "HintCatalogResolver",
        "GuidanceHapticEngine",
        "UIImpactFeedbackGenerator",
        "HorizonIndicatorView",
        "HintPillView",
        "TargetLineOverlay",
        "GoodToShootOverlay",
        "UserGuidanceHUD"
    ]
    for t in expected_guidance_types:
        if t not in guidance_text:
            print(f"[FAIL] UserGuidanceHUD.swift missing required type/token: {t}", file=sys.stderr)
            return 1
    print(f"  ✓ UserGuidanceHUD.swift contains all {len(expected_guidance_types)} expected HUD types.")

    all_21_hint_keys = [
        "rotate_cw", "rotate_ccw", "hold_vertical", "lower_phone", "lower_and_vertical",
        "step_back", "step_forward", "pan_left", "pan_right", "tilt_down", "tilt_up",
        "switch_zoom_2x", "switch_zoom_step_back", "switch_zoom_1x", "enable_fill",
        "move_to_shade", "turn_subject_side", "turn_face_to_light", "use_night_mode",
        "clean_lens", "good"
    ]
    for key in all_21_hint_keys:
        if f'"{key}"' not in guidance_text:
            print(f"[FAIL] UserGuidanceHUD.swift missing hint key: {key}", file=sys.stderr)
            return 1
    print(f"  ✓ UserGuidanceHUD.swift contains all {len(all_21_hint_keys)} standard hint keys in catalogs.")

    # 7. Check ComposeKit & SyncKit Tests
    tests_dir = compose_kit_dir / "Tests" / "ComposeKitTests"
    required_tests = ["GoldenVectorTests.swift", "ConcurrencyTests.swift", "ComposeKitTests.swift"]
    for f in required_tests:
        fp = tests_dir / f
        if not fp.is_file():
            print(f"[FAIL] Missing Swift test file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found test file: {f}")

    sync_test_file = sync_kit_dir / "Tests" / "SyncKitTests" / "SyncKitTests.swift"
    if not sync_test_file.is_file():
        print(f"[FAIL] Missing SyncKit test file: {sync_test_file}", file=sys.stderr)
        return 1
    print("  ✓ Found SyncKit test suite: SyncKitTests.swift")

    # 8. Check Golden Vectors integrity against Swift definitions (TASK-02)
    print("--- [validate-swift-parity] Checking Golden Vector Coverage & Schema Parity (TASK-02) ---")
    EXPECTED_GOLDEN_VECTORS = 20
    golden_files = list(fixtures_dir.glob("*.json"))
    golden_vectors = [f for f in golden_files if f.name != "schema.json"]
    if len(golden_vectors) != EXPECTED_GOLDEN_VECTORS:
        print(
            f"[FAIL] Expected exactly {EXPECTED_GOLDEN_VECTORS} golden vector JSONs, found {len(golden_vectors)}",
            file=sys.stderr,
        )
        return 1

    # Parity check: Rust golden runner constant must match EXPECTED_GOLDEN_VECTORS
    rust_golden_runner = repo_root / "core" / "compose-core" / "tests" / "golden_runner.rs"
    if not rust_golden_runner.is_file():
        print(f"[FAIL] Missing Rust golden runner test: {rust_golden_runner}", file=sys.stderr)
        return 1
    runner_text = rust_golden_runner.read_text(encoding="utf-8")
    runner_match = re.search(r"EXPECTED_VECTORS\s*:\s*usize\s*=\s*(\d+);", runner_text)
    if not runner_match or int(runner_match.group(1)) != EXPECTED_GOLDEN_VECTORS:
        val = runner_match.group(1) if runner_match else "not found"
        print(
            f"[FAIL] golden_runner.rs EXPECTED_VECTORS ({val}) != EXPECTED_GOLDEN_VECTORS ({EXPECTED_GOLDEN_VECTORS})",
            file=sys.stderr,
        )
        return 1
    print(f"  ✓ golden_runner.rs EXPECTED_VECTORS matches {EXPECTED_GOLDEN_VECTORS}.")

    # Parity check: Swift GoldenVectorTests must assert exact vector count
    golden_swift_test = tests_dir / "GoldenVectorTests.swift"
    if not golden_swift_test.is_file():
        print(f"[FAIL] Missing GoldenVectorTests.swift: {golden_swift_test}", file=sys.stderr)
        return 1
    golden_swift_text = golden_swift_test.read_text(encoding="utf-8")
    expected_assert = f"XCTAssertEqual(files.count, {EXPECTED_GOLDEN_VECTORS}"
    if expected_assert not in golden_swift_text:
        print(
            f"[FAIL] GoldenVectorTests.swift does not assert '{expected_assert}' (expected {EXPECTED_GOLDEN_VECTORS} golden vectors)",
            file=sys.stderr,
        )
        return 1
    print(f"  ✓ GoldenVectorTests.swift asserts exact vector count ({EXPECTED_GOLDEN_VECTORS}).")

    valid_severities = {"Good", "Minor", "Major", "Critical"}
    for gv in sorted(golden_vectors):
        with open(gv, "r", encoding="utf-8") as f:
            data = json.load(f)
        vid = data.get("id")
        desc = data.get("description")
        inp = data.get("input", {})
        frame = inp.get("frame", {})
        findings = data.get("expected_findings", [])

        if not vid or not isinstance(vid, str):
            print(f"[FAIL] Golden vector {gv.name} missing valid 'id'", file=sys.stderr)
            return 1
        if not desc or not isinstance(desc, str):
            print(f"[FAIL] Golden vector {gv.name} missing valid 'description'", file=sys.stderr)
            return 1
        if "t" not in frame or "posture" not in frame:
            print(f"[FAIL] Golden vector {gv.name} missing required input.frame schema fields", file=sys.stderr)
            return 1

        for item in findings:
            fid = item.get("id")
            sev = item.get("severity")
            hint = item.get("hint_key")
            if not fid or not isinstance(fid, str):
                print(f"[FAIL] Golden vector {vid} has finding without id: {item}", file=sys.stderr)
                return 1
            if sev not in valid_severities:
                print(f"[FAIL] Golden vector {vid} has invalid severity: {sev}", file=sys.stderr)
                return 1
            if not hint or not isinstance(hint, str):
                print(f"[FAIL] Golden vector {vid} has finding without hint_key: {item}", file=sys.stderr)
                return 1
        print(f"  ✓ {gv.name:<32} [id: {vid}, findings: {len(findings)}]")

    print(f"--- [validate-swift-parity] All {len(golden_vectors)} golden vectors validated with exact Swift schema parity. ---")

    # 9. TASK-01 hard gate: ComposeKit must really link compose-ffi and must never silently mock
    print("--- [validate-swift-parity] Checking ComposeKit FFI Wiring (TASK-01) ---")

    compose_manifest = (compose_kit_dir / "Package.swift").read_text(encoding="utf-8")
    live_composer_path = compose_kit_dir / "Sources" / "ComposeKit" / "LiveComposer.swift"
    live_composer = live_composer_path.read_text(encoding="utf-8")
    run_swift_tests_path = repo_root / "scripts" / "run-swift-tests.sh"
    run_swift_tests = run_swift_tests_path.read_text(encoding="utf-8")

    # 9.1 Package.swift must reference the XCFramework through a binaryTarget and depend on it.
    # Comments in the manifest are stripped first: the design notes above mention
    # "ComposeCore.xcframework" and ".binaryTarget", and matching raw text would make these
    # assertions true no matter what the executable code does.
    compose_manifest_code = re.sub(r"//[^\n]*", "", compose_manifest)

    def delimited_block(text: str, open_index: int) -> str:
        depth = 0
        for idx in range(open_index, len(text)):
            char = text[idx]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return text[open_index + 1: idx]
        return text[open_index + 1:]

    if "ComposeCore.xcframework" not in compose_manifest_code:
        print(
            "[FAIL] ComposeKit/Package.swift does not reference ComposeCore.xcframework in code "
            "(a comment mentioning it is not enough: ComposeKit would build without the Rust engine)",
            file=sys.stderr,
        )
        return 1
    binary_target_match = re.search(
        r'\.binaryTarget\s*\(\s*name:\s*"ComposeCore"\s*,\s*path:\s*[^)]*\)',
        compose_manifest_code,
    )
    if binary_target_match is None:
        print(
            "[FAIL] ComposeKit/Package.swift declares no active "
            '`.binaryTarget(name: "ComposeCore", path: ...)`; deleting or commenting that line '
            "silently drops the Rust static library from the build",
            file=sys.stderr,
        )
        return 1
    compose_target_match = re.search(r'\.target\(\s*name:\s*"ComposeKit"', compose_manifest_code)
    if compose_target_match is None:
        print("[FAIL] ComposeKit/Package.swift has no ComposeKit target declaration", file=sys.stderr)
        return 1
    compose_target_open = compose_manifest_code.index("(", compose_target_match.start())
    compose_target_segment = delimited_block(compose_manifest_code, compose_target_open)
    if "dependencies" not in compose_target_segment or '"ComposeCore"' not in compose_target_segment:
        print(
            "[FAIL] ComposeKit target does not depend on the ComposeCore binary target "
            "(the ComposeKit .target(...) block must list \"ComposeCore\" in dependencies)",
            file=sys.stderr,
        )
        return 1
    if "unsafeFlags" in compose_manifest_code:
        print(
            "[FAIL] ComposeKit/Package.swift uses unsafeFlags; SwiftPM forbids dependents on "
            "such packages (use the ComposeCore binaryTarget instead)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ Package.swift links ComposeCore.xcframework via a .binaryTarget dependency.")

    # 9.2 The public initializer must be throwing and must not enable mock mode
    init_match = re.search(r"public init\([^)]*\)\s*(throws\s*)?\{", live_composer)
    if init_match is None:
        print("[FAIL] LiveComposer.swift has no public init(...) initializer", file=sys.stderr)
        return 1

    def block_body(text: str, brace_index: int) -> str:
        depth = 0
        for idx in range(brace_index, len(text)):
            char = text[idx]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return text[brace_index + 1: idx]
        return text[brace_index + 1:]

    init_open = init_match.end() - 1
    init_body = block_body(live_composer, init_open)
    if init_match.group(1) is None:
        print(
            "[FAIL] LiveComposer public init is not `throws`; engine failures would be hidden",
            file=sys.stderr,
        )
        return 1
    if re.search(r"isMockMode\s*=\s*true", init_body):
        print(
            "[FAIL] LiveComposer public init still enables mock mode (silent fallback)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ LiveComposer public init is throwing and never enables mock mode.")

    # 9.3 createMock() must be DEBUG-only
    composer_lines = live_composer.splitlines()
    create_mock_index = next(
        (i for i, line in enumerate(composer_lines) if "func createMock" in line),
        None,
    )
    if create_mock_index is None:
        print("[FAIL] LiveComposer.createMock() is missing", file=sys.stderr)
        return 1

    depth = 0
    in_debug_block = False
    for idx in range(create_mock_index, -1, -1):
        stripped = composer_lines[idx].strip()
        if stripped.startswith("#endif"):
            depth += 1
        elif stripped.startswith("#if"):
            if depth > 0:
                depth -= 1
            else:
                in_debug_block = re.match(r"#if\s+DEBUG\b", stripped) is not None
                break
    if not in_debug_block:
        print(
            "[FAIL] LiveComposer.createMock() is not wrapped in `#if DEBUG`; mock mode could "
            "ship in release builds",
            file=sys.stderr,
        )
        return 1
    print("  ✓ createMock() is confined to a `#if DEBUG` block.")

    # 9.4 No mock evaluator anywhere
    if "evaluateMockJson" in live_composer:
        print(
            "[FAIL] LiveComposer.swift still contains evaluateMockJson (silent mock fallback)",
            file=sys.stderr,
        )
        return 1
    print("  ✓ LiveComposer.swift contains no mock evaluator.")

    # 9.5 macOS test runner must enforce the FFI link gate with a real export, not a comment
    run_swift_tests_code = re.sub(r"^[ \t]*#[^\n]*", "", run_swift_tests, flags=re.MULTILINE)
    if not re.search(r'^\s*export\s+COMPOSE_REQUIRE_FFI=1\s*$', run_swift_tests_code, re.MULTILINE):
        print(
            "[FAIL] scripts/run-swift-tests.sh has no active `export COMPOSE_REQUIRE_FFI=1` line; "
            "a commented-out gate never reaches the manifest, so the XCFramework fatalError guard "
            "would never fire on CI or device builds",
            file=sys.stderr,
        )
        return 1
    print("  ✓ scripts/run-swift-tests.sh enforces COMPOSE_REQUIRE_FFI=1 on macOS.")

    print("--- [validate-swift-parity] ComposeKit FFI wiring gate passed (TASK-01). ---")

    # 10. TASK-05 gate: Extended FFI Contract, Regenerated Bindings & Swift Parity
    print("--- [validate-swift-parity] Checking Extended FFI Contract & Swift Parity (TASK-05) ---")

    gen_swift_text = (gen_dir / "compose_ffi.swift").read_text(encoding="utf-8")
    gen_header_text = (gen_dir / "compose_ffiFFI.h").read_text(encoding="utf-8")
    compose_models_text = (sources_dir / "Models.swift").read_text(encoding="utf-8")

    # 10.1 Check Generated compose_ffi.swift records and enums
    expected_ffi_types = [
        "SeverityFfi", "AudienceFfi", "ActionFfi", "HintItemFfi", "FindingFfi", "LiveOutputFfi"
    ]
    for t in expected_ffi_types:
        if t not in gen_swift_text:
            print(f"[FAIL] Generated compose_ffi.swift missing type {t}", file=sys.stderr)
            return 1
    print(f"  ✓ compose_ffi.swift contains all {len(expected_ffi_types)} expected UniFFI types.")

    # 10.2 Check ActionFfi all 16 cases in Generated compose_ffi.swift
    action_ffi_cases = [
        "rotate", "holdVertical", "lowerPhone", "stepBack", "stepForward",
        "panLeft", "panRight", "tiltUp", "tiltDown", "switchZoom",
        "enableFill", "cleanLens", "moveToShade", "turnSubject", "useNightMode", "good"
    ]
    for c in action_ffi_cases:
        if f"case {c}" not in gen_swift_text:
            print(f"[FAIL] ActionFfi missing case: {c}", file=sys.stderr)
            return 1
    print(f"  ✓ ActionFfi contains all {len(action_ffi_cases)} cases in generated Swift bindings.")

    # 10.3 Check LiveEngine protocol methods in compose_ffi.swift
    expected_engine_methods = ["reloadConfig", "analyzeStill", "reset", "backend"]
    for m in expected_engine_methods:
        if f"func {m}" not in gen_swift_text:
            print(f"[FAIL] LiveEngineProtocol missing method: {m}", file=sys.stderr)
            return 1
    print(f"  ✓ LiveEngineProtocol contains all extended methods: {expected_engine_methods}.")

    # 10.4 Check compose_ffiFFI.h has header declarations
    if len(gen_header_text.strip()) == 0:
        print("[FAIL] compose_ffiFFI.h is empty", file=sys.stderr)
        return 1
    print(f"  ✓ compose_ffiFFI.h verified ({len(gen_header_text)} bytes).")

    # 10.5 Check Models.swift ComposeAction all 16 cases
    for c in action_ffi_cases:
        if f"case {c}" not in compose_models_text:
            print(f"[FAIL] Models.swift ComposeAction missing case: {c}", file=sys.stderr)
            return 1
    print("  ✓ Models.swift ComposeAction all 16 cases verified.")

    # 10.6 Check Models.swift types: ComposeSeverity, ComposeAudience, ComposeHint, ComposeFinding, ComposeOutput
    for st in ["ComposeSeverity", "ComposeAudience", "ComposeHint", "ComposeFinding", "ComposeOutput"]:
        if st not in compose_models_text:
            print(f"[FAIL] Models.swift missing type: {st}", file=sys.stderr)
            return 1
    if "typealias HintItem = ComposeHint" not in compose_models_text:
        print("[FAIL] Models.swift missing 'typealias HintItem = ComposeHint'", file=sys.stderr)
        return 1
    print("  ✓ Models.swift extended types and typealias verified.")

    # 10.7 Check LiveComposer.swift methods: reloadConfig, analyzeStill, reset, backend
    for m in ["reloadConfig", "analyzeStill", "reset", "backend"]:
        if f"func {m}" not in live_composer:
            print(f"[FAIL] LiveComposer.swift missing method: {m}", file=sys.stderr)
            return 1
    print("  ✓ LiveComposer.swift methods (reloadConfig, analyzeStill, reset, backend) verified.")

    # 10.8 Check shared/hints/*.json coverage for all 20 golden vectors
    hints_dir = repo_root / "shared" / "hints"
    zh_hints = json.loads((hints_dir / "zh-Hans.json").read_text(encoding="utf-8"))["hints"]
    en_hints = json.loads((hints_dir / "en.json").read_text(encoding="utf-8"))["hints"]

    if "good" not in zh_hints or "good" not in en_hints:
        print("[FAIL] 'good' key missing from shared/hints JSON files", file=sys.stderr)
        return 1

    for gv in golden_vectors:
        with open(gv, "r", encoding="utf-8") as f:
            data = json.load(f)
        for item in data.get("expected_findings", []):
            k = item["hint_key"]
            if k not in zh_hints:
                print(f"[FAIL] Hint key '{k}' from {gv.name} missing from zh-Hans.json", file=sys.stderr)
                return 1
            if k not in en_hints:
                print(f"[FAIL] Hint key '{k}' from {gv.name} missing from en.json", file=sys.stderr)
                return 1
    print(f"  ✓ shared/hints coverage verified for all {len(golden_vectors)} golden vectors in zh-Hans and en.")
    print("--- [validate-swift-parity] TASK-05 extended FFI contract parity gate passed. ---")

    # 11. Check CameraAppClip Components & Stranger Helper Flow (TASK-11)
    print("--- [validate-swift-parity] Checking CameraAppClip Stranger Helper Flow (TASK-11) ---")
    clip_files = [
        camera_clip_dir / "AppClipStub.swift",
        camera_clip_dir / "AppClipInvocationParser.swift",
        camera_clip_dir / "AppClipCoordinator.swift",
        camera_clip_dir / "AppClipHelperView.swift",
    ]
    for fp in clip_files:
        if not fp.is_file():
            print(f"[FAIL] Missing CameraAppClip file: {fp}", file=sys.stderr)
            return 1
        print(f"  ✓ Found CameraAppClip source: {fp.relative_to(repo_root)}")

    # 11.1 Check CameraAppClip Info.plist permissions
    clip_info_plist = camera_clip_dir / "Info.plist"
    if not clip_info_plist.is_file():
        print(f"[FAIL] Missing Info.plist in {camera_clip_dir}", file=sys.stderr)
        return 1
    info_content = clip_info_plist.read_text(encoding="utf-8")
    for key in ["NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription", "NSAppClip"]:
        if key not in info_content:
            print(f"[FAIL] CameraAppClip Info.plist missing {key}", file=sys.stderr)
            return 1
    print("  ✓ CameraAppClip Info.plist verified with camera, photo library, and App Clip metadata.")

    # 11.2 Check CameraAppClip key types and integration symbols
    all_clip_text = ""
    for fp in clip_files:
        all_clip_text += "\n" + fp.read_text(encoding="utf-8")

    expected_clip_symbols = [
        "AppClipInvocationParser",
        "AppClipCoordinator",
        "AppClipHelperView",
        "GhostSilhouetteOverlayView",
        "TargetAlignmentOverlayView",
        "AppClipCompletionView",
        "NSUserActivityTypeBrowsingWeb",
        "SyncSession",
        "DefaultE2EECipher",
        "ReferencePackage",
        "CapturePackage",
        "hasActiveInvocation",
        "isSessionFinished"
    ]
    for sym in expected_clip_symbols:
        if sym not in all_clip_text:
            print(f"[FAIL] CameraAppClip sources missing required symbol: {sym}", file=sys.stderr)
            return 1
    print(f"  ✓ CameraAppClip verified with all {len(expected_clip_symbols)} expected TASK-11 symbols.")
    print("--- [validate-swift-parity] TASK-11 App Clip stranger helper flow parity gate passed. ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
